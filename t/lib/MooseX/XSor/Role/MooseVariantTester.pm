package MooseX::XSor::Role::MooseVariantTester;

use v5.14;
use Moose::Role;
use Moose::Util::TypeConstraints;
use Test::Most;
use Test::Fatal;

with 'Test::Class::Moose::Role::ParameterizedInstances';

has 'moose',
	is       => 'ro',
	required => 1;

has '_no_attr_class',
	is      => 'ro',
	lazy    => 1,
	default => sub {
	my ($self) = @_;
	my $class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Class' => $class);
		package #Class;
		use #Moose;
		__PACKAGE__->meta->make_immutable;
END
	$class;
	};

sub _constructor_parameter_sets {
	if (my $mv = $ENV{TEST_MOOSE_VARIANT}) {
		return ($mv => {moose => $mv});
	}
	map { $_ => { moose => $_ } } qw(MooseX::XSor::PP MooseX::XSor::XS Moose::XSor::XS::Struct);
}

sub _eval_class {
	my ($self, $str, %replacements) = @_;
	eval _replace($str, %replacements, '#Moose' => $self->moose);
	die if $@;
}

sub _get_anon_package {
	state $i = 0;
	ref($_[0]) . '::__ANON__::SERIAL::' . ++$i;
}

sub _replace {
	my ($str, %replacements) = @_;
	while (my ($key, $value) = each %replacements) {
		$str =~ s/$key/$value/g;
	}
	$str;
}

1;
