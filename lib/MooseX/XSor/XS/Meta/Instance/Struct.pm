package MooseX::XSor::XS::Meta::Instance::Struct;

use Moose::Role;

with 'MooseX::XSor::XS::Meta::Instance::XSOnly';

sub xs_create_instance {
	my ($self, $instance, $instance_slots, $class) = @_;
	<<"END"
	InstanceSlots* $instance_slots;
	Newx($instance_slots, 1, InstanceSlots);

	SV* ${instance}_p = newSViv((IV)$instance_slots);
	SV* $instance     = newRV_noinc((SV*)${instance}_p);

	sv_bless($instance, gv_stashsv($class, GV_ADD));
	SvREADONLY_on(${instance}_p);
	sv_2mortal(instance);
END
}

sub xs_define_instance {
	my ($self, $instance, $instance_slots, $from) = @_;

	my @code;

	if ($self->associated_metaclass->xs_sanity_checking eq 'paranoid') {
		@code = <<"END";
		if (items == 0) croak("Call to class or instance method as a function not allowed");
		if (!sv_isobject($from)) croak("Expected \$self to be an object");
		if (!SvROK($from)) croak("Expected \$self to be a ref");
		if (!SvIOK(SvRV($from))) croak("Expected \$self to be a integer ref");
END
	}

	push @code, <<"END";
		SV* $instance = $from;
		InstanceSlots* $instance_slots = (InstanceSlots*)SvIV(SvRV($instance));
END

	@code;
}

sub xs_deinitialize_slot {
	my ($self, $instance_slots, $slot_name, $lvalue) = @_;
	my $struct_name = $self->_struct_name($slot_name);
	if ($lvalue) {
		<<"END";
		$lvalue = instance_slots->$struct_name;
		instance_slots->$struct_name = &PL_sv_undef;
END
	}
	else {
		<<"END";
		if (instance_slots->$struct_name != &PL_sv_undef) {
			SvREFCNT_dec_NN(instance_slots->$struct_name);
		}
		instance_slots->$struct_name = &PL_sv_undef;
END
	}
}

sub xs_initialize_slot {
	my ($self, $instance_slots, $slot_name) = @_;
	my $struct_name = $self->_struct_name($slot_name);
	return "$instance_slots->$struct_name = &PL_sv_undef;";
}

sub xs_get_slot_value {
	my ($self, $instance_slots, $slot_name) = @_;
	my $struct_name = $self->_struct_name($slot_name);
	"instance_slots->$struct_name";
}

around xs_headers => sub {
	my ($orig, $self) = @_;

	return (
		'typedef struct {',
		(map { 'SV* ' . $self->_struct_name($_) . ';' } sort $self->get_all_slots),
		'} InstanceSlots;',
		$self->$orig,
	);
};

sub xs_is_slot_initialized {
	my ($self, $instance_slots, $slot_name) = @_;
	my $struct_name = $self->_struct_name($slot_name);
	"(instance_slots->$struct_name != &PL_sv_undef)";
}

sub xs_set_slot_value {
	my ($self, $instance_slots, $slot_name, $value) = @_;
	my $struct_name = $self->_struct_name($slot_name);
	<<"END";
	if (instance_slots->$struct_name != &PL_sv_undef) {
		SvREFCNT_dec_NN(instance_slots->$struct_name);
	}
	instance_slots->$struct_name = $value;
END
}

sub _struct_name {
	my ($self, $slot_name) = @_;

	return "slot_${slot_name}" if $slot_name =~ /^[a-zA-Z0-9_]+$/;

	require Digest::MD5;
	return 'slot_' . Digest::MD5::md5_hex($slot_name);
}

1;
