use Mojo::Base -strict;

use File::Find::Rule ();
use Mojo::File qw(curfile);

use Test::Mojo;
use Test::More;

my $t = Test::Mojo::Session->new(curfile->dirname->sibling('mojobible.pl'));

subtest widgets => sub {
  $t->get_ok($t->app->url_for('index'))
    ->status_is(200)
    # ->text_is('h3' => 'Court de Gébelin', 'has page title')
    # ->element_exists('button[value="view"]', 'has View btn')
  ;
};

done_testing();
