package MooseX::XSor::XS::Meta::Instance::XSOnly;

use Moose::Role;
use MooseX::XSor::Util qw(quotecmeta);

requires qw(xs_create_instance xs_deinitialize_slot xs_get_slot_value
	xs_is_slot_initialized xs_get_slot_value);

with 'MooseX::XSor::XS::Meta::Instance::RequiresImmutability';
with 'MooseX::XSor::XS::Meta::Instance::XSInlinable';

sub INSTANCE_CLONE() { 0 }
sub INSTANCE_CREATE() { 1 }
sub INSTANCE_DEINITIALIZE_SLOT() { 2 }
sub INSTANCE_INITIALIZE_SLOT() { 3 }
sub INSTANCE_IS_SLOT_INITIALIZED() { 4 }
sub INSTANCE_GET_SLOT_VALUE() {5 }
sub INSTANCE_REBLESS_INSTANCE_STRUCTURE() {6}
sub INSTANCE_SET_SLOT_VALUE() { 7}
sub INSTANCE_SLOT_VALUE_IS_WEAK() {8}
sub INSTANCE_STRENGTHEN_SLOT_VALUE() {9}
sub INSTANCE_WEAKEN_SLOT_VALUE() {10}

has 'xs_proxy',
	is  => 'rw',
	isa => 'CodeRef';

sub create_instance {
	my ($self) = @_;
	$self->xs_proxy->(INSTANCE_CREATE);
}

sub clone_instance {
	my ($self, $instance) = @_;
	$self->xs_proxy->(INSTANCE_CLONE, $instance);
}

sub deinitialize_slot {
	my ($self, $instance, $slot_name) = @_;
	$self->xs_proxy->(INSTANCE_DEINITIALIZE_SLOT, $instance, $slot_name);
}

sub initialize_slot {
	my ($self, $instance, $slot_name) = @_;
	$self->xs_proxy->(INSTANCE_INITIALIZE_SLOT,$instance,  $slot_name);
}

sub is_slot_initialized {
	my ($self, $instance, $slot_name) = @_;
	$self->xs_proxy->(INSTANCE_IS_SLOT_INITIALIZED, $instance,$slot_name );
}

sub get_slot_value {
	my ($self, $instance, $slot_name) = @_;
	$self->xs_proxy->(INSTANCE_GET_SLOT_VALUE,$instance, $slot_name );
}

sub rebless_instance_structure {
	my ($self, $instance, $metaclass) = @_;
	$self->xs_proxy->(INSTANCE_REBLESS_INSTANCE_STRUCTURE, $instance,$metaclass );
}

sub set_slot_value {
	my ($self, $instance, $slot_name, $value) = @_;
	$self->xs_proxy->(INSTANCE_SET_SLOT_VALUE, $instance,$slot_name,  $value);
}

sub slot_value_is_weak {
	my ($self, $instance, $slot_name) = @_;
	$self->xs_proxy->(INSTANCE_SLOT_VALUE_IS_WEAK, $instance, $slot_name);
}

sub strengthen_slot_value {
	my ($self, $instance, $slot_name) = @_;
	$self->xs_proxy->(INSTANCE_STRENGTHEN_SLOT_VALUE, $instance, $slot_name);
}
sub weaken_slot_value {
	my ($self, $instance, $slot_name) = @_;
	$self->xs_proxy->(INSTANCE_WEAKEN_SLOT_VALUE, $instance, $slot_name);
}

sub xs_boot {
	return (
		'CV* xs_instance_proxy = newXS(NULL, instance_proxy, __FILE__);',
		'PUSHMARK(SP);',
		'XPUSHs(meta);',
		'PUTBACK;',
		'call_method("get_meta_instance", G_SCALAR);',
		'SPAGAIN;',
		'SV* meta_instance = POPs;',
		'PUSHMARK(SP);',
		'XPUSHs(meta_instance);',
		'XPUSHs(newRV_noinc(xs_instance_proxy));',
		'PUTBACK;',
		'call_method("xs_proxy", G_DISCARD);',
	);
}

sub xs_headers {
	my ($self) = @_;
	my @slots = sort $self->get_all_slots;
	my $for_slots = sub {
		my ($then, $xsreturn) = @_;
		
		return (
			'char* slot_name = SvPV_nolen(ST(2));',
			(map { ('if (strEQ(slot_name, "' . quotecmeta($_) . '")) {', $then->($_), "XSRETURN(" . $xsreturn . ');', '}') } @slots),
		);
	};

	#<<<
	return (
		'#define INSTANCE_CLONE ' . INSTANCE_CLONE,
		'#define INSTANCE_CREATE ' . INSTANCE_CREATE,
		'#define INSTANCE_DEINITIALIZE_SLOT ' . INSTANCE_DEINITIALIZE_SLOT,
		'#define INSTANCE_INITIALIZE_SLOT ' . INSTANCE_INITIALIZE_SLOT,
		'#define INSTANCE_IS_SLOT_INITIALIZED ' . INSTANCE_IS_SLOT_INITIALIZED,
		'#define INSTANCE_GET_SLOT_VALUE ' . INSTANCE_GET_SLOT_VALUE,
		'#define INSTANCE_REBLESS_INSTANCE_STRUCTURE ' . INSTANCE_REBLESS_INSTANCE_STRUCTURE,
		'#define INSTANCE_SET_SLOT_VALUE ' . INSTANCE_SET_SLOT_VALUE,
		'#define INSTANCE_SLOT_VALUE_IS_WEAK ' . INSTANCE_SLOT_VALUE_IS_WEAK,
		'#define INSTANCE_STRENGTHEN_SLOT_VALUE ' . INSTANCE_STRENGTHEN_SLOT_VALUE,
		'#define INSTANCE_WEAKEN_SLOT_VALUE ' . INSTANCE_WEAKEN_SLOT_VALUE,
		'XS(instance_proxy) {',
			'dXSARGS;',
			'int mode = SvIV(ST(0));',
			'if (mode == INSTANCE_CREATE) {',
				$self->xs_create_instance('instance', 'instance_slots', 'class_name'),
				$self->xs_initialize_all_slots('instance_slots'),
				'ST(0) = instance;',
				'XSRETURN(1);',
			'}',
			$self->xs_define_instance('instance', 'instance_slots', 'ST(1)'),

			'switch (mode) {',
				'case INSTANCE_CLONE: {',
				$self->xs_clone_instance('instance', 'instance_slots', 'clone', 'clone_slots'),
				'ST(0) = clone;',
				'XSRETURN(1);',
				'}',

				'case INSTANCE_DEINITIALIZE_SLOT: {',
				$for_slots->(sub {
					$self->xs_deinitialize_slot('instance_slots', $_, 'ST(0)')
				}, 1),
				'}',

				'case INSTANCE_INITIALIZE_SLOT: {',
				$for_slots->(sub {
					$self->xs_initialize_slot('instance_slots', $_)
				}, 0),
				'}',

				'case INSTANCE_IS_SLOT_INITIALIZED: {',
				$for_slots->(sub {
					'ST(0) = ' . $self->xs_is_slot_initialized('instance_slots', $_)
						. ' ? &PL_sv_yes : &PL_sv_no;'
				}, 1),
				'}',

				'case INSTANCE_GET_SLOT_VALUE: {',
				$for_slots->(sub {
					'ST(0) = sv_mortalcopy(' . $self->xs_get_slot_value('instance_slots', $_) . ');'
				}, 1),
				'}',

				'case INSTANCE_REBLESS_INSTANCE_STRUCTURE: {',
				'ST(0) = ' . $self->xs_rebless_instance_structure('instance', 'instance_slots') . ';',
				'XSRETURN(1);',
				'}',

				'case INSTANCE_SET_SLOT_VALUE: {',
				$for_slots->(sub {
					$self->xs_set_slot_value('instance_slots', $_, 'newSVsv(ST(3))');
				}, 0),
				'}',

				'case INSTANCE_SLOT_VALUE_IS_WEAK: {',
				$for_slots->(sub {
					'ST(0) = ' . $self->xs_slot_value_is_weak('instance_slots', $_)
						. ' ? &PL_sv_yes : &PL_sv_no;'
				}, 1),
				'}',

				'case INSTANCE_STRENGTHEN_SLOT_VALUE: {',
				$for_slots->(sub {
					$self->xs_strengthen_slot_value('instance_slots', $_)
				}, 0),
				'}',

				'case INSTANCE_WEAKEN_SLOT_VALUE: {',
				$for_slots->(sub {
					$self->xs_weaken_slot_value('instance_slots', $_)
				}, 0),
				'}',

				'default:',
				'croak("Invalid instance operation mode");',
			'}',
		'}',
	);
	#>>>	
}

1;
