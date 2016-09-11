package MooseX::XSor::XS::Meta::Method::Accessor;

use Moose;

extends 'Moose::Meta::Method::Accessor';
with 'MooseX::XSor::XS::Meta::Method::InlineXS';
with 'MooseX::XSor::XS::Meta::Method::Generated';
with 'MooseX::XSor::Role::XSGenerator';

sub _build_body_boot {
	my ($self) = @_;
	$self->associated_attribute->_xs_boot;
}

sub _build_body_headers {
	my ($self) = @_;
	$self->associated_attribute->_xs_headers;
}

sub _build_body_source {
	my ($self) = @_;
	my $method_name = join "_", ('_generate', $self->accessor_type, 'method_xs');
	[ $self->$method_name ];
}

sub _generate_accessor_method_xs {
	my ($self) = @_;
	my $attr = $self->associated_attribute;
	#<<<
	return (
		$self->_xs_instance_define('instance', 'instance_slots', 'ST(0)'),
		'if (items > 1) {',
			$attr->_xs_set_value('instance', 'instance_slots', 'ST(1)'),
		'}',
		$attr->_xs_get_value('instance', 'instance_slots'),
	)
	#>>>
}

sub _generate_clearer_method_xs {
	my ($self) = @_;
	my $attr = $self->associated_attribute;
	#<<<
	return (
		$self->_xs_instance_define('instance', 'instance_slots', 'ST(0)'),
		$attr->_xs_clear_value('instance_slots'),
	)
	#>>>
}

sub _generate_predicate_method_xs {
	my ($self) = @_;
	my $attr = $self->associated_attribute;
	#<<<
	return (
		$self->_xs_instance_define('instance', 'instance_slots', 'ST(0)'),
		$attr->_xs_has_value('instance_slots'),
	)
	#>>>
}

sub _generate_reader_method_xs {
	my ($self) = @_;
	my $attr = $self->associated_attribute;
	#<<<
	return (
		$self->_xs_instance_define('instance', 'instance_slots', 'ST(0)'),
		'if (items > 1) {',
			$self->_xs_throw_moose_exception(
				'CannotAssignValueToReadOnlyAccessor',
				class_name       => 'sv_ref(0, instance, 1)',
				value            => 'ST(1)',
				attribute_name   => \($attr->name),
			),
		'}',
		$attr->_xs_get_value('instance', 'instance_slots'),
	)
	#>>>
}

sub _generate_writer_method_xs {
	my ($self) = @_;
	my $attr = $self->associated_attribute;
	#<<<
	return (
		$self->_xs_instance_define('instance', 'instance_slots', 'ST(0)'),
		'SV* new = items > 1 ? ST(1) : &PL_sv_undef;',
		$attr->_xs_set_value('instance', 'instance_slots', 'new'),
		$attr->_xs_get_value('instance', 'instance_slots'),
	)
	#>>>
}

sub _initialize_body {
	my ($self) = @_;
	return $self->SUPER::_initialize_body unless $self->_instance_is_xs_inlinable;

	$self->{'body'} = $self->_build_body;
}

sub _instance_is_xs_inlinable {
	shift->associated_attribute->_instance_is_xs_inlinable;
}

sub _xs_instance_define {
	shift->associated_attribute->_xs_instance_define(@_);
}

__PACKAGE__->meta->make_immutable(replace_constructor => 1);
