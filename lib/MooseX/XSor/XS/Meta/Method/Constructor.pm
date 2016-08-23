package MooseX::XSor::XS::Meta::Method::Constructor;

use Moose::Role;

with 'MooseX::XSor::XS::Meta::Method::InlineXS';

sub _build_body_boot {
	my ($self) = @_;
	return $self->associated_metaclass->_xs_boot;
}

sub _build_body_headers {
	my ($self) = @_;
	return $self->associated_metaclass->_xs_headers;
}

sub _build_body_source {
	my ($self) = @_;
	return [ $self->associated_metaclass->_xs_new_object ];
}

1;
