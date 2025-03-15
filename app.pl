#!/usr/bin/env perl
use Mojolicious::Lite -signatures;

use Capture::Tiny qw(capture_stdout);
use Crypt::Passphrase ();
use Crypt::Passphrase::Argon2 ();
use Data::Dumper::Compact qw(ddc);
use Encoding::FixLatin qw(fix_latin);
use JSON::MaybeXS qw(decode_json encode_json);
use Mojo::SQLite;
use Time::Piece;

use constant MAX_SEEN => 25;
use constant THROTTLE => 60 * 2; # 2 minutes

helper is_demo => sub ($c) { # for use in the template
  my $user = $c->session('user');
  return $user eq 'guest' ? 1 : 0;
};

helper fix_latin => sub ($c, $string) { # for use in the template
  return fix_latin($string);
};

helper sql => sub ($c) {
  return state $sql = Mojo::SQLite->new('sqlite:app.db');
};

helper auth => sub ($c) {
  my $user = $c->param('username');
  my $pass = $c->param('password');
  return 0 unless $user && $pass;
  my $record = $c->sql->db->query('select id, name, password from account where name = ? and active = 1', $user)->hash;
  my $password = $record ? $record->{password} : undef;
  my $authenticator = Crypt::Passphrase->new(encoder => 'Argon2');
  if (!$authenticator->verify_password($pass, $password)) {
    return 0;
  }
  $c->session(auth => 1);
  $c->session(user => $record->{name});
  $c->session(user_id => $record->{id});
  return 1;
};

helper seen => sub ($c) {
  my $record = $c->sql->db->query(
    'insert into seen (account_id, ip) values (?, ?)',
    $c->session('user_id'),
    $c->remote_addr
  )->hash;
};

helper times_seen => sub ($c) {
  my $record = $c->sql->db->query(
    "select count(*) as 'count' from seen where account_id = ? and created >= datetime('now', '-1 days') and created < datetime('now')",
    $c->session('user_id')
  )->hash;
  return $record->{count};
};

helper last_seen => sub ($c) {
  my $record = $c->sql->db->query(
    "select unixepoch(created) as 'epoch' from seen where account_id = ? order by created desc",
    $c->session('user_id')
  )->hash;
  return $record->{epoch};
};

get '/' => sub { shift->redirect_to('login') } => 'index';

get '/login' => sub { shift->render } => 'login';

post '/login' => sub ($c) {
  if ($c->auth) {
    return $c->redirect_to('app');
  }
  $c->flash('error' => 'Invalid login');
  $c->redirect_to('login');
} => 'auth';

get '/logout' => sub ($c) {
  delete $c->session->{auth};
  delete $c->session->{user};
  delete $c->session->{user_id};
  $c->session(expires => 1);
  $c->redirect_to('login');
} => 'logout';

under sub ($c) {
  return 1 if ($c->session('auth') // '') eq '1';
  $c->redirect_to('login');
  return undef;
};

get '/app' => sub ($c) {
warn __PACKAGE__,' L',__LINE__,' ',,"HELLO??\n";
  my $action  = $c->param('action')  || '';  # user action like 'interp'
  my $seek    = $c->param('seek')    || '';  # concepts user is seeking
  my $comment = $c->param('comment') || 0;   # for interpretation

  my $user_id = $c->session('user_id');
  my $sql = Mojo::SQLite->new('sqlite:app.db');

  my $interpretation = ''; # AI interpretations

  my $responses = [];
  if ($action eq 'interp' && $seek) {
    if ($c->times_seen < MAX_SEEN) {
      my $t = localtime;
      my $last_seen = $c->last_seen;
      if ($last_seen + THROTTLE < $t->epoch) {
        $interpretation = _interpret($seek, $comment);
        $c->seen;
      }
      else {
        $c->flash('error' => 'Please wait ' . ($last_seen + THROTTLE - $t->epoch) . ' seconds...');
        return $c->redirect_to($c->url_for('app')->query(
          seek    => $seek,
          comment => $comment,
        ));
      }
    }
    else {
      $c->flash('error' => 'Max daily query limit reached');
      return $c->redirect_to('app');
    }
  }

  $c->render(
    template => 'app',
    mobile   => $c->browser->mobile ? 1 : 0,
    interp   => $interpretation,
    can_chat => $ENV{OPENAI_API_KEY} ? 1 : 0,
    seek     => $seek,
    comment  => $comment,
  );
} => 'app';

sub _interpret ($seeking, $comment) {
  my $prompt = "You are a Stoic scholar. Generate high quality text concerning '$seeking', quoting specific excepts from the writings of Stoic thinkers.";
  $prompt .= <<"PROMPT";

VOICE RULES:
- Skip ALL standard AI openings ('let's dive in, delve into' etc.)
PROMPT

if ($comment) {
  $prompt .= <<"PROMPT";
- Jump straight into the Stoic advice
- Talk like a traditional philosophy scholar, not a corporate chatbot

READING STRUCTURE:
- Build a flowing narrative between excerpts
- Balance mystery with clear insights
PROMPT
}

  $prompt .= <<"PROMPT";

ABSOLUTELY AVOID:
- Using any preamble or introductory text
- Academic language
- Customer service politeness
- Meta-commentary about the advice
- Fancy vocabulary
- Cookie-cutter transitions
- Hedging words (perhaps/maybe/might)
- ANY intro phrases or other narrative devices common to AI
- Suggesting the creation of a vision board, list, or journal
PROMPT

  my $response = _get_response('user', $prompt);
  $response =~ s/\*\*//g;
  $response =~ s/##+//g;
  $response =~ s/\n+/<p><\/p>/g;
  return $response;
}

sub _get_response ($role, $prompt) {
  return unless $prompt;
  my @message = { role => $role, content => $prompt };
  my $json_string = encode_json([@message]);
  my @cmd = (qw(python3 chat.py), $json_string);
  my $stdout = capture_stdout { system(@cmd) };
  chomp $stdout;
  return $stdout;
}

app->plugin('AdditionalValidationChecks');
app->plugin('browser_detect');
app->plugin('RemoteAddr');

app->start;

__DATA__

@@ login.html.ep
% layout 'default';
% title 'Stoic Scholar Login';
<p></p>
<form action="<%= url_for('auth') %>" method="post">
  <input class="form-control" type="text" name="username" placeholder="Username (min=3, max=20)">
  <br>
  <input class="form-control" type="password" name="password" placeholder="Password (min=10, max=20)">
  <br>
  <input class="form-control btn btn-primary" type="submit" name="submit" value="Login">
</form>

@@ app.html.ep
% layout 'default';
% title 'Stoic Scholar';
<p></p>
% # Interpret
%   if ($can_chat) {
  <form method="get">
    <textarea class="form-control" name="seek" placeholder="Concept, question, or verse"><%= $seek %></textarea>
    <p></p>
%     if (is_demo()) {
    <a type="button" href="<%= url_for('signup') %>" title="Interpret this reading" class="btn btn-info">Interpret</a>
%     }
%     else {
    <button type="submit" name="action" title="Interpret this reading" value="interp" class="btn btn-primary" id="interp">
      Ask</button>
%     }
    &nbsp;
    <input class="form-check-input" type="checkbox" value="1" id="comment" name="comment" <%= $comment ? 'checked' : '' %> style="margin-top: 9px;">
    <label class="form-check-label" for="comment">
      Commentary</label>
  </form>
  <p></p>
  <p>* Please allow two minutes between queries.</p>
%   }
<p></p>
% # Response
% if ($interp) {
    <hr>
    <%== fix_latin($interp) %>
% }

@@ layouts/default.html.ep
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="icon" type="image/png" href="/favicon.ico">
    <link href="/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-EVSTQN3/azprG1Anm3QDgpJLIm9Nao0Yz1ztcQTwFspd3yD65VohhpuuCOmLASjC" crossorigin="anonymous">
    <script src="/js/jquery.min.js"></script>
    <script src="/js/bootstrap.min.js" integrity="sha384-cVKIPhGWiC2Al4u+LWgxfKTRIcfu0JTxR+EQDz/bgldoEyl4H0zUF0QKbrJ0EcQF" crossorigin="anonymous"></script>
    <link rel="stylesheet" href="/css/style.css">
    <title><%= title %></title>
    <script>
    $(document).ready(function() {
      $("#interp").click(function() {
        $('#loading').show();
      });
    });
    $(window).on('load', function() {
        $('#loading').hide();
    })
    </script>
  </head>
  <body>
    <div id="loading">
      <img id="loading-image" src="/loading.gif" alt="Loading..." />
    </div>
    <div class="container padpage">
% if (flash('error')) {
      <h2 style="color:red"><%= flash('error') %></h2>
% }
      <h3><img src="/favicon.ico"> <a href="<%= url_for('app') %>"><%= title %></a></h3>
      <%= content %>
      <p></p>
      <div id="footer" class="small">
        <hr>
        <a href="<%= url_for('logout') %>">Logout</a>
      </div>
      <p></p>
    </div>
  </body>
</html>
