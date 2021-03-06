use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use Test::Exception;

my $t_anyone = Test::Mojo->new('BibSpace');
my $self     = $t_anyone->app;

use BibSpace::TestManager;
TestManager->apply_fixture($self->app);

my $repo            = $self->app->repo;
my @all_authorships = $repo->authorships_all;

my $limit_num_tests = 200;

note "============ Testing "
  . scalar(@all_authorships)
  . " entries ============";

foreach my $authorship (@all_authorships) {
  last if $limit_num_tests < 0;

  note "============ Testing Labeling ID " . $authorship->id . ".";

  ok($authorship->id, "id");

  lives_ok(sub { $authorship->equals($authorship) },
    'equals expecting to live');
  lives_ok(sub { $authorship->equals_id($authorship) },
    'equals_id expecting to live');
  dies_ok(sub { $authorship->equals(undef) }, 'equals undef expecting to die');

  $limit_num_tests--;
}

subtest "Serializing to JSON should not remove fields from super-class" => sub {
  use JSON -convert_blessed_universally;
  my $l = $all_authorships[0];

  my $pre_1 = $l->entry_id;
  my $pre_2 = $l->author_id;

  my $json = JSON->new->convert_blessed->utf8->pretty->encode($l);
  chomp $json;
  cmp_ok($json, 'ne', "{}", "JSON representation should not be empty");

  my $post_1 = $l->entry_id;
  my $post_2 = $l->author_id;

  is($post_1, $pre_1,
    "Data field entry_id should be identical before and after serialization");
  is($post_2, $pre_2,
    "Data field author_id should be identical before and after serialization");
};

ok(1);
done_testing();
