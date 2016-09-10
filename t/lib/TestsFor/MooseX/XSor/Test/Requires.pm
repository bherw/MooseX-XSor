package TestsFor::MooseX::XSor::Test::Requires;
use Test::Class::Moose;

use parent qw(MooseX::XSor::Test::Requires);

has 'ran_good_test', is => 'rw';

sub test_bad : Requires(MooseX::XSor::This::Will::Never::Exist) {
	fail "didn't skip test that requires a module that doesn't exist";
}

sub test_good : Requires(Test::More) {
	my ($self) = @_;
	$self->ran_good_test(1);

	# This one because otherwise Test::Class::Moose will fail this test.
	pass "Didn't skip a good test";
}

sub test_real {
	my ($self) = @_;

	# This one in case the previous one got skipped erroneously.
	ok $self->ran_good_test, "Didn't skip a good test";
}

1;
