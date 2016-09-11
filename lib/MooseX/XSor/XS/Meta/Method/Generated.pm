package MooseX::XSor::XS::Meta::Method::Generated;
# ABSTRACT: Abstract base metaclass for generated methods

use Moose::Role;

has 'associated_metaclass',
	is       => 'ro',
	init_arg => 'metaclass',
	weak_ref => 1;

has 'body',
	is      => 'ro',
	isa     => 'CodeRef',
	builder => '_build_body',
	lazy    => 1;

has 'definition_context',
	is      => 'ro',
	isa     => 'HashRef',
	lazy    => 1,
	builder => '_build_body';

has 'name',
	is       => 'ro',
	isa      => 'Str',
	required => 1;

has 'options',
	is      => 'ro',
	isa     => 'HashRef',
	default => sub { {} };

has 'package_name',
	is      => 'ro',
	default => sub { shift->associated_metaclass->name };

requires qw(_build_body);

sub _build_definition_context {
	my ($self) = @_;
	return {
		description => $self->associated_metaclass->name . '::' . $self->name,
		file        => $self->options->{file},
		line        => $self->options->{line},
	};
}

1;

=head1 DESCRIPTION

An abstract base class for generated methods. Note that Class::MOP doesn't seem
to strictly distinguish what generated and inlined mean. For the purpose of
this module, a generated method can be a closure or an inlined function made by
compiling generated code.
