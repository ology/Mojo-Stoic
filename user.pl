#!/usr/bin/env perl
use strict;
use warnings;

use Crypt::Passphrase ();
use Crypt::Passphrase::Argon2 ();
use Mojo::SQLite ();
use Term::ReadKey qw(ReadMode ReadLine);

my ($action, $user, $email, $pass) = @ARGV;

die "Usage: perl $0 add|act|dea|pass username [email] [password]\n"
  unless $user;

if ($action eq 'add') {
  add($user, $email, $pass);
}
elsif ($action eq 'act') {
  activate($user);
}
elsif ($action eq 'dea') {
  deactivate($user);
}
elsif ($action eq 'pass') {
  change_pwd($user, $pass);
}

sub activate {
  my $sql = Mojo::SQLite->new('sqlite:app.db');
  my $record = $sql->db->query('select id from account where name = ?', $user)->hash;
  my $id = $record ? $record->{id} : undef;
  if ($id) {
    $sql->db->query('update account set active = 1 where id = ?', $id);
    print "User: $user successfully activated.\n";
  }
  else {
    warn "Can't activate user '$user'.\n";
  }
}

sub deactivate {
  my $sql = Mojo::SQLite->new('sqlite:app.db');
  my $record = $sql->db->query('select id from account where name = ?', $user)->hash;
  my $id = $record ? $record->{id} : undef;
  if ($id) {
    $sql->db->query('update account set active = 0 where id = ?', $id);
    print "User: $user successfully deactivated.\n";
  }
  else {
    warn "Can't deactivate user '$user'.\n";
  }
}

sub add {
  my $sql = Mojo::SQLite->new('sqlite:app.db');
  my $record = $sql->db->query('select id from account where name = ?', $user)->hash;
  my $id = $record ? $record->{id} : undef;
  if ($id) {
    warn "User '$user' is already known.\n";
  }
  else {
    unless ($pass) {
      ReadMode('noecho');
      print "Password for user '$user': ";
      $pass = ReadLine(0);
      chomp $pass;
      print "\n";
      ReadMode('restore');
    }
    my $authenticator = Crypt::Passphrase->new(encoder => 'Argon2');
    my $new_hash = $authenticator->hash_password($pass);
    $sql->db->query('insert into account (name, email, password) values (?, ?, ?)', $user, $email, $new_hash);
    print "User: $user, email: $email successfully inserted.\n";
  }
};

sub change_pwd {
  my $sql = Mojo::SQLite->new('sqlite:app.db');
  my $record = $sql->db->query('select id from account where name = ?', $user)->hash;
  my $id = $record ? $record->{id} : undef;
  if ($id) {
    unless ($pass) {
      ReadMode('noecho');
      print "Password for user '$user': ";
      $pass = ReadLine(0);
      chomp $pass;
      print "\n";
      ReadMode('restore');
    }
    my $authenticator = Crypt::Passphrase->new(encoder => 'Argon2');
    my $new_hash = $authenticator->hash_password($pass);
    $sql->db->query('update account set password = ? where id = ?', $new_hash, $id);
    print "User: $user password changed successfully.\n";
  }
  else {
    warn "Can't change password for user '$user'.\n";
  }
};
