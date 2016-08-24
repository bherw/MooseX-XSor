package MooseX::XSor::XS::Meta::Attribute;

use Moose::Role;
use MooseX::RelatedClasses;
use namespace::sweep;

with 'MooseX::XSor::Role::XSGenerator';

# Unfortunately, Moose doesn't let these get traits applied like other metaclasses
related_classes { Accessor => 'accessor_metaclass', Delegation => 'delegation_metaclass' },
	namespace => 'MooseX::XSor::XS::Meta::Method';

# Moose leaves out the compiled type constraint when it can be inlined,
# but we need it unless it can be xs inlined.
around _eval_environment => sub {
	my ($orig, $self) = @_;

	my $env = $self->$orig;

	if (my $tc = $self->type_constraint) {
		$env->{'$type_constraint'} = \($tc->_compiled_type_constraint)
			unless $tc->can('can_be_xs_inlined') && $self->can_be_xs_inlined;
	}

	$env;
};

# XXX: Is this useful for something?
sub can_be_xs_inlined {
	return shift->can_be_inlined;
}

sub _xs_boot {
	my ($self) = @_;

	# FIXME: Just using _eval_environment to get the values for now
	# This will segfault or something equally bad if moose changes anything
	my @code = <<"END";
	class_name = newSVpvs("@{[ $self->associated_class->name ]}");
	@{[ $self->_xs_class_of('class_name', 'meta') ]}
	SvREFCNT_inc_simple_NN(meta);
END

	my @env = $self->_xs_boot_env;

	if (@env || ($self->has_initializer && $self->is_lazy)) {
		push @code, <<"END";
			PUSHMARK(SP);
			EXTEND(SP, 2);
			PUSHs(meta);
			mPUSHs(newSVpvs("@{[ $self->name ]}"));
			PUTBACK;
			count = call_method("get_attribute");
			if (count != 1) croak("Metaclass failed to return attribute for @{[ $self->name ]}");
			SPAGAIN;
			attr = newSVsv(POPs);
			PUTBACK;
END
	}

	if (@env) {
		push @code, <<"END";
		PUSHMARK(SP);
		XPUSHs(attr);
		PUTBACK;
		count = call_method("_eval_environment");
		if (count != 1) croak("Metaattribute _eval_environment returned nothing!");
		SPAGAIN;
		HV* env = SvRV(POPs);
		SvREFCNT_inc_simple_NN(env); // Lazily keeping a ref to its contents
		PUTBACK;
END
		push @code, @env;
	}

	push @code, $self->associated_class->get_meta_instance->xs_boot;

	return @code;
}

sub _xs_boot_env {
	my ($self) = @_;

	my @env;
	push @env, 'trigger = SvRV(hv_fetch(env, "$trigger", 8));'           if $self->has_trigger;
	push @env, 'attr_default = SvRV(hv_fetch(env, "$attr_default", 13);' if $self->has_default;

	if ($self->has_type_constraint) {
		my $tc = $self->type_constraint;

		push @env, 'type_constraint = SvRV(hv_fetch(env, "$type_constraint", 16));'
			unless $tc->can('can_be_xs_inlined') && $tc->can_be_xs_inlined;
		push @env, 'type_coercion = SvRV(hv_fetch(env, "$type_coercion", 14));'
			if $tc->has_coercion;
		push @env, 'type_message = SvRV(hv_fetch(env, "$type_message", 12));';

		push @env, $tc->xs_inline_boot if $tc->can('xs_inline_boot');
	}

	@env;
}

sub _xs_call_coercion {
	my ($self, $value, $coercion) = @_;
	my $class_name = $self->associated_class->name;
	my $attr_name  = $self->name;
	<<"END"
	PUSHMARK(SP);
	XPUSHs($value);
	PUTBACK;
	
	count = call_sv($coercion, G_SCALAR);
	if (count != 1) croak("Coercion for ${class_name}::${attr_name} failed to return anything");
	SPAGAIN;
	SvREFCNT_dec_NN($value);
	$value = POPs;
	SvREFCNT_inc_simple_NN($value);
	PUTBACK;
END
}

sub _xs_call_tc_cv {
	my ($self, $value, $tc) = @_;
	my $class_name = $self->associated_class->name;
	my $attr_name  = $self->name;
	<<"END"
	PUSHMARK(SP);
	XPUSHs($value);
	PUTBACK;
	count = call_sv($tc, G_SCALAR);
	if (count != 1)
		croak("Type constraint for ${class_name}::${attr_name} failed to return anything");
	SPAGAIN;
END
}

sub _xs_check_required {
	my ($self) = @_;

	return unless $self->is_required;

	#<<<
	return (
		'if (items < 2) {',
			$self->_xs_throw_moose_exception(
				'AttributeIsRequired',
				attribute_name => \($self->name),
				class_name     => 'class_name',
			),
		'}',
	);
	#>>>
}

sub _xs_copy_value {
	my ($self, $value, $copy) = @_;

	return "SV* $copy = newSVsv($value);";
}

sub _xs_generate_default {
	my ($self, $instance, $default, $default_value) = @_;

	my $call_default
		= $self->can('_xs_generate_default_from') || __PACKAGE__->can('_xs_generate_default_from');

	if ($self->has_default) {
		if ($self->is_default_a_coderef) {
			return ($default, $self->$call_default($instance, $default, $default_value));
		}
		else {
			return $default_value;
		}
	}
	elsif ($self->has_builder) {
		return (
			$default,

			# Code
			$self->_xs_call_method($instance, \'can', [ \($self->builder) ], 'one'),
			'if (!SvOK(retST(0))) {',
			$self->_xs_throw_moose_exception(
				'BuilderMethodNotSupportedForInlineAttribute',
				class_name => "sv_isobject($instance) ? sv_ref(0, SvRV($instance), 1) : $instance",
				attribute_name => \($self->name),
				instance       => "$instance",
				builder        => \($self->builder),
			),
			'}',
			"SV* builder = POPs;",
			'PUTBACK;',
			$self->$call_default($instance, $default, 'builder', ' | G_METHOD'),
		);
	}
	else {
		return;
	}
}

sub _xs_generate_default_from {
	my ($self, $instance, $default, $sv, $is_method) = @_;
	$is_method //= '';
	# This method might be called on a Class::MOP::Attribute so let's just hardcode this.
	<<"END"
	PUSHMARK(SP);
	EXTEND(SP, 1);
	PUSHs($instance);
	PUTBACK;
	count = call_sv($sv, G_SCALAR$is_method);
	SPAGAIN;
	SV* $default = (count ? POPs : &PL_sv_undef);
	PUTBACK;
END
}

sub _xs_get_old_value_for_trigger {
	my ($self, $instance_slots, $old) = @_;

	return unless $self->has_trigger;

	return "SV* $old = sv_mortalcopy(" . $self->_xs_instance_get($instance_slots) . ');';
}

sub _xs_headers {
	my $self       = shift;
	my $class      = $self->associated_class->name;
	my $prefix     = $self->_xs_prefix;
	my $attr_count = scalar $self->get_all_attributes;

	my $type_constraint_headers;
	if ($self->has_type_constraint) {
		my $tc = $self->type_constraint;
		if ($tc->can('xs_inline_header')) {
			$type_constraint_headers = $tc->xs_inline_headers;
		}
	}

	<<"END"
	#define retST(offset) PL_stack_base[ax + items + (off)]

	SV *default, *attr, *trigger, *type_coercion, *type_constraint, *type_message;
	$type_constraint_headers;

	SV *class_name, *attr, *meta;
END
}

sub _xs_instance_get {
	my ($self, $instance_slots) = @_;

	my $mi = $self->associated_class->get_meta_instance;
	return $mi->xs_get_slot_value($instance_slots, $self->name);
}

sub _xs_instance_set {
	my ($self, $instance_slots, $value) = @_;

	my $mi = $self->associated_class->get_meta_instance;
	return $mi->xs_set_slot_value($instance_slots, $self->name, $value);
}

sub _xs_prefix {
	shift->associated_class->_xs_prefix;
}

sub _xs_set_value {
	my ($self, $instance, $instance_slots, $value, $tc, $coercion, $message, $purpose) = @_;

	my $old  = 'old';
	my $copy = 'val';
	$tc       ||= 'type_constraint';
	$coercion ||= 'type_coercion';
	$message  ||= 'type_message';

	my @code;
	# if ($self->_writer_value_needs_copy)
	# Moose makes an extra copy for coercions,
	# but we can make a single copy for both coercion and storage.
	{
		push @code, $self->_xs_copy_value($value, $copy);
		$value = $copy;
	}

	# Constructors already handle required checks
	push @code, $self->_xs_check_required unless $purpose eq 'constructor';

	push @code, $self->_xs_tc_code($value, $tc, $coercion, $message, $purpose);

	push @code, $self->_xs_get_old_value_for_trigger($instance_slots, $old)
		unless $purpose eq 'constructor';

	push @code, $self->_xs_instance_set($instance_slots, $value) . ';',
		$self->_xs_weaken_value($instance_slots, $value);

	# Constructors do triggers all at once at the end
	push @code, $self->_xs_trigger($instance, $value, $old) unless $purpose eq 'constructor';

	return @code;
}

sub _xs_tc_code {
	my ($self, $value, $tc_cv, $coercion, $message, $is_lazy, $purpose) = @_;

	return unless my $tc = $self->type_constraint;

	my $tc_inline    = $tc->can('can_be_xs_inlined') && $tc->can_be_xs_inlined;
	my $has_coercion = $self->should_coerce          && $tc->has_coercion;

	my @check_tc_code;
	if ($tc_inline) {
		@check_tc_code = 'valid = ' . $tc->_xs_inline_check . ';';
	}
	else {
		#<<<
		@check_tc_code = (
			$self->_xs_call_tc_cv($value, $tc_cv),

			# SvTRUE accesses this 4-5 times so copy first.
			'valid_sv = POPs;',
			'valid    = SvTRUE_NN(valid_sv);',
			'PUTBACK;',
		);
		#>>>
	}

	my @code = ('int valid;', 'SV* valid_sv;');
	if ($has_coercion) {
		#<<<
		push @code, (
			@check_tc_code,
			"if (!valid) {",
				$self->_xs_call_coercion($value, $coercion),
				@check_tc_code,
			'}',
		);
		#>>>
	}
	else {
		push @code, @check_tc_code;
	}

	#<<<
	push @code, (
		"if (!valid) {",
			$self->_xs_throw_tc_validation_failed($value, $message),
		'}'
	);
	#>>>

	return @code;
}

sub _xs_throw_tc_validation_failed {
	my ($self, $value, $msg) = @_;
	return <<"END"
	// XXX: I think this is affecting the scope the XSUB is called in, which is
	// wrong, but I'm not sure it matters since we're either in an eval block
	// or about to die anyways.
	SAVESPTR(GvSV(PL_defgv));
	GvSV(PL_defgv) = $value;

	PUSHMARK(SP);
	XPUSHs($value);
	PUTBACK;
	count = call_sv($msg, G_SCALAR);
	SPAGAIN;
	SV* msg = count ? POPs : sv_2mortal(newSVpvs("Validation failed for inline type constraint"));
	PUTBACK;

	@{[ $self->_xs_throw_moose_exception(
		ValidationFailedForInlineTypeConstraint =>
		type_constraint_message => 'msg',
		class_name              => 'class_name',
		attribute_name          => \($self->name),
		value                   => $value,
	) ]}
END
}

sub _xs_trigger {
	my ($self, $instance, $value, $old) = @_;

	return unless $self->has_trigger;
	return <<"END"
	PUSHMARK(SP);
	EXTEND(SP, 2);
	PUSHs(instance);
	PUSHs(@{[ $self->_xs_instance_get('instance_slots') ]});
	if ($old) XPUSHs($old);
	PUTBACK;
	call_sv(trigger, G_DISCARD);
	SPAGAIN;
END
}

sub _xs_weaken_value {
	my ($self, $instance_slots, $value) = @_;

	return unless $self->is_weak_ref;

	#<<<
	return (
		"if (SvROK($value)) {",
			$self->get_meta_instance->xs_weaken_slot_value($instance_slots, $self->name) . ';',
		'}',
	);
	#>>>
}

1;
