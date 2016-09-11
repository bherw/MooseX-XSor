package MooseX::XSor::XS::Meta::Instance::Hash;

use Moose::Role;
use MooseX::XSor::Util qw(quotecmeta);

with 'MooseX::XSor::XS::Meta::Instance::XSInlinable';

sub xs_create_instance {
	my ($self, $instance, $instance_slots, $class) = @_;
	<<"END"
	HV* $instance_slots = newHV();
	SV* $instance = newRV_noinc((SV*)$instance_slots);
	sv_bless($instance, gv_stashsv($class, GV_ADD));
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
		if (!SvHROK($from)) croak("Expected \$self to be a hashref");
END
	}

	push @code, ("SV* $instance = $from;", "HV* $instance_slots = MUTABLE_HV(SvRV($instance));",);

	@code;
}

sub xs_deinitialize_slot {
	my ($self, $instance_slots, $slot_name) = @_;
	sprintf 'hv_delete(%s, "%s", %d, 0)', $instance_slots, quotecmeta($slot_name),
		length $slot_name;
}

sub xs_get_slot_value {
	my ($self, $instance_slots, $slot_name) = @_;
	sprintf '_instance_slot_get(aTHX_ %s, "%s", %d)', $instance_slots, quotecmeta($slot_name),
		length $slot_name;
}

sub xs_headers {
	<<END
	PERL_STATIC_INLINE SV*
	_instance_slot_get(pTHX_ HV* instance_slots, const char* slot_name, int slot_name_len) {
		SV** slotref = hv_fetch(instance_slots, slot_name, slot_name_len, 0);
		return slotref ? *slotref : &PL_sv_undef;
	}
END
}

sub xs_is_slot_initialized {
	my ($self, $instance_slots, $slot_name) = @_;
	sprintf 'hv_exists(%s, "%s", %d)', $instance_slots, quotecmeta($slot_name), length $slot_name;
}

sub xs_set_slot_value {
	my ($self, $instance_slots, $slot_name, $value) = @_;
	sprintf '*hv_store(%s, "%s", %d, %s, 0)', $instance_slots, quotecmeta($slot_name),
		length $slot_name, $value;
}

1;

=head1 DESCRIPTION

L<MooseX::XSor::XS::Meta::Instance::Hash> is a meta instance role implementing
L<MooseX::XSor::XS::Meta::Instance::XSInlinable>. It uses a hashref to store
slots and should be fully compatible with an ordinary L<Moose::Meta::Instance>.
It does not require immutablity to produce inline XS code.

See L<MooseX::XSor::XS::Meta::Instance::XSInlinable> for documentation of the
methods this class implements.

=cut
