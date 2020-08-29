package MooseX::XSor::XS::Meta::Attribute;

use Moose::Role;
use MooseX::XSor::Util qw(quotecmeta);
use aliased 'MooseX::XSor::XS::Meta::Method::Accessor';

with 'MooseX::XSor::Role::XSGenerator';

# Unfortunately, Moose doesn't let these get traits applied like other metaclasses
override accessor_metaclass => sub {Accessor};

# XSOnly classes get their superclasses' accessors inlined into them,
# this gets the right metaclass used without passing yet another variable around.
# This solution stinks but it's only here until codegen gets refactored to use a single context.
around install_accessors => sub {
	my ($orig, $self, $inline, %param) = @_;
	local $self->{associated_class} = $param{class} if $param{class};
	$self->$orig($inline);
};

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
	my ($self) = @_;
	$self->can_be_inlined && $self->_instance_is_xs_inlinable;
}

sub _instance_is_xs_inlinable {
	shift->associated_class->_instance_is_xs_inlinable;
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
			mPUSHs(newSVpvs("@{[ quotecmeta $self->name ]}"));
			PUTBACK;
			count = call_method("get_attribute", G_SCALAR);
			if (count != 1) croak("Metaclass failed to return attribute for @{[ quotecmeta $self->name ]}");
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
		count = call_method("_eval_environment", G_SCALAR);
		if (count != 1) croak("Metaattribute _eval_environment returned nothing!");
		SPAGAIN;
		HV* env = MUTABLE_HV(SvRV(POPs));
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
	push @env, 'trigger = SvRV(*hv_fetch(env, "$trigger", 8, 0));'            if $self->has_trigger;
	push @env, 'attr_default = SvRV(*hv_fetch(env, "$attr_default", 13, 0));' if $self->has_default;

	if ($self->has_type_constraint) {
		my $tc = $self->type_constraint;

		push @env, 'type_constraint = SvRV(*hv_fetch(env, "$type_constraint", 16, 0));'
			unless $tc->can('can_be_xs_inlined') && $tc->can_be_xs_inlined;
		push @env, 'type_coercion = SvRV(*hv_fetch(env, "$type_coercion", 14, 0));'
			if $tc->has_coercion;
		push @env, 'type_message = SvRV(*hv_fetch(env, "$type_message", 13, 0));';

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
	if (count != 1) croak("Coercion for ${class_name}::@{[ quotecmeta $attr_name ]} failed to return anything");
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
		croak("Type constraint for ${class_name}::@{[ quotecmeta $attr_name ]} failed to return anything");
	SPAGAIN;
END
}

sub _xs_check_lazy {
	my ($self, $instance, $instance_slots, $tc, $coercion, $message) = @_;

	return unless $self->is_lazy;

	#<<<
	return (
		'if (!' . $self->_xs_instance_has($instance_slots) . ') {',
			$self->_xs_init_from_default(
				$instance, $instance_slots, 'attr_default', $tc, $coercion, $message, 'lazy'),
		'}',
	);
	#>>>
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

sub _xs_clear_value {
	my ($self, $instance_slots) = @_;
	return (
		$self->_xs_instance_clear($instance_slots, 'ST(0)'),
		'XSRETURN(1);',
	);
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
			return $self->$call_default($instance, $$default, $default_value);
		}
		else {
			$$default = $default_value;
			return;
		}
	}
	elsif ($self->has_builder) {
		return (
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
			$self->$call_default($instance, $$default, 'builder', ' | G_METHOD'),
		);
	}
	else {
		$$default = undef;
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

sub _xs_get_value {
	my ($self, $instance, $instance_slots, $tc, $coercion, $message) = @_;

	$tc       ||= 'type_constraint';
	$coercion ||= 'type_coercion';
	$message  ||= 'type_message';

	return (
		$self->_xs_check_lazy($instance, $instance_slots, $tc, $coercion, $message),
		$self->_xs_return_auto_deref($self->_xs_instance_get($instance_slots)),
	);
}

sub _xs_has_value {
	my ($self, $instance_slots) = @_;
	return ('ST(0) = ' . $self->_xs_instance_has($instance_slots) . ' ? &PL_sv_yes : &PL_sv_no;',
		'XSRETURN(1);',);
}

sub _xs_headers {
	my $self = shift;

	my @type_constraint_headers;
	if ($self->has_type_constraint) {
		my $tc = $self->type_constraint;
		if ($tc->can('xs_inline_header')) {
			@type_constraint_headers = $tc->xs_inline_headers;
		}
	}

	my @code = <<"END";
	SV *attr_default, *attr, *trigger, *type_coercion, *type_constraint, *type_message;
	@type_constraint_headers;

	SV *class_name, *attr, *meta;
END
	push @code, $self->associated_class->get_meta_instance->xs_headers;

	@code;
}

sub _xs_init_from_default {
	my ($self, $instance, $instance_slots, $default_value, $tc, $coercion, $message, $purpose) = @_;

	unless ($self->has_default || $self->has_builder) {
		throw_exception('LazyAttributeNeedsADefault', attribute => $self);
	}

	my $default = 'generated_default';
	my $value   = 'value';
	return (
		$self->_xs_generate_default($instance, \$default, $default_value),
		"SV* $value = newSVsv($default);",
		$self->has_type_constraint
		? $self->_xs_tc_code($value, $tc, $coercion, $message, $purpose)
		: (),
		$self->_xs_init_slot($instance, $instance_slots, $value),
		$self->_xs_weaken_value($instance_slots, $value),
	);
}

sub _xs_init_slot {
	my ($self, $instance, $instance_slots, $value) = @_;

	if ($self->has_initializer) {
		return $self->_xs_call_method('attr', \'set_initial_value', [ $instance, $value ],
			'discard');
	}
	else {
		$self->_xs_instance_set($instance_slots, $value) . ';';
	}
}

sub _xs_instance_clear {
	my ($self, $instance_slots, $lvalue) = @_;
	$self->associated_class->_xs_instance_clear($instance_slots, $self->name, $lvalue);
}

sub _xs_instance_define {
	shift->associated_class->_xs_instance_define(@_);
}

sub _xs_instance_get {
	my ($self, $instance_slots) = @_;
	$self->associated_class->_xs_instance_get($instance_slots, $self->name);
}

sub _xs_instance_has {
	my ($self, $instance_slots) = @_;
	$self->associated_class->_xs_instance_has($instance_slots, $self->name);
}

sub _xs_instance_set {
	my ($self, $instance_slots, $value) = @_;
	$self->associated_class->_xs_instance_set($instance_slots, $self->name, $value);
}

sub _xs_instance_weaken {
	my ($self, $instance_slots) = @_;
	$self->associated_class->_xs_instance_weaken($instance_slots, $self->name);
}

sub _xs_prefix {
	shift->associated_class->_xs_prefix;
}

sub _xs_return_auto_deref {
	my ($self, $ref) = @_;

	my $g_scalar = <<"END";
	ST(0) = sv_mortalcopy($ref);
	XSRETURN(1);
END

	if (!$self->should_auto_deref) {
		return $g_scalar;
	}

	#<<<
	my $tc   = $self->type_constraint;
	my @code = (
		'if (GIMME_V != G_ARRAY) {',
			$g_scalar,
		'}',
		"SV* retval = $ref;",
		"if (!SvOK(retval)) XSRETURN(0);",
	);
	#>>>

	if ($tc->is_a_type_of('ArrayRef')) {
		push @code, <<"END";
		AV*     av       = MUTABLE_AV(SvRV(retval));
		SSize_t av_top   = av_top_index(av);
		int     return_i = 0;

		EXTEND(SP, av_top + 1 - items);
		for (int i = 0; i <= av_top; i++) {
			SV** item = av_fetch(av, i, 0);
			if (item) {
				ST(return_i++) = sv_mortalcopy(*item);
			}
		}

		XSRETURN(return_i);
END
	}
	elsif ($tc->is_a_type_of('HashRef')) {
		push @code, <<"END";
		HV* hv       = MUTABLE_HV(SvRV(retval));
		I32 hv_count = hv_iterinit(hv);
		int return_i = 0;
		HE* he;

		EXTEND(SP, hv_count * 2 - items);
		while (he = hv_iternext(hv)) {
			ST(return_i++) = HeSVKEY_force(he);
			ST(return_i++) = sv_mortalcopy(HeVAL(he));
		}

		XSRETURN(return_i);
END
	}
	else {
		confess 'Can not auto de-reference the type constraint \'' . $tc->name . '\'';
	}

	return @code;
}

sub _xs_set_value {
	my ($self, $instance, $instance_slots, $value, $tc, $coercion, $message, $purpose) = @_;

	my $old  = 'old';
	my $copy = 'val';
	$tc       ||= 'type_constraint';
	$coercion ||= 'type_coercion';
	$message  ||= 'type_message';
	$purpose  ||= '';

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

	push @code, $self->_xs_instance_set($instance_slots, $value),
		$self->_xs_weaken_value($instance_slots, $value);

	unless ($purpose eq 'constructor') {
		# Constructors do triggers all at once at the end
		push @code, $self->_xs_trigger($instance, $value, $old);

		push @code, (
			'if (GIMME_V == G_VOID) { XSRETURN(0); }',
			"ST(0) = sv_mortalcopy($value);", 'XSRETURN(1);',);
	}

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
	if (SvOK($old)) XPUSHs($old);
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
			$self->_xs_instance_weaken($instance_slots) . ';',
		'}',
	);
	#>>>
}

1;
