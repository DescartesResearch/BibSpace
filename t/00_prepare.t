use Mojo::Base -strict;
use Test::More;
use Test::Mojo;

use Hex64Publications;
use Hex64Publications::Controller::Core;
use Hex64Publications::Controller::Backup;
use Hex64Publications::Functions::BackupFunctions;
use Hex64Publications::Functions::EntryObj;


my $t_anyone = Test::Mojo->new('Hex64Publications');
my $t_logged_in = Test::Mojo->new('Hex64Publications');
$t_logged_in->post_ok(
    '/do_login' => { Accept => '*/*' },
    form        => { user   => 'pub_admin', pass => 'asdf' }
);

my $dbh = $t_logged_in->app->db;
my $self = $t_logged_in->app;



done_testing();

