use Test::Class::Moose::Load 't/lib';
use Test::Class::Moose::Runner;
Test::Class::Moose::Runner->new(
	test_classes => $ENV{TEST_CLASS},
	$ENV{TEST_INCLUDE} ? (include => qr/$ENV{TEST_INCLUDE}/) : (),
)->runtests;
