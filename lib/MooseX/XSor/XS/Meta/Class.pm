package MooseX::XSor::XS::Meta::Class;

use List::Util qw(any);
use Moose::Role;
use MooseX::XSor::Util qw(quotecmeta);
use Try::Tiny;

with 'MooseX::XSor::Role::XSGenerator';

has 'xs_sanity_checking',
	is      => 'rw',
	default => 'paranoid';

# From Class::MOP::Class
# Modified to support instances that can only generate accessors once immutable
override _post_add_attribute => sub {
	my ($self, $attribute) = @_;

	$self->invalidate_meta_instances;

	my $mi = $self->get_meta_instance;
	return if $mi->can('requires_immutability') && $mi->requires_immutability;

	# invalidate package flag here
	try {
		local $SIG{__DIE__};
		$attribute->install_accessors;
	}
	catch {
		$self->remove_attribute($attribute->name);
		die $_;
	};
};

sub _xs_boot {
	my ($self) = @_;

	# FIXME: Just using _eval_environment to get the values for now
	# This will segfault or something equally bad if moose changes anything
	my @code = (<<"END");
	class_name = newSVpvs("@{[ $self->name ]}");
	@{[ $self->_xs_class_of('class_name', 'meta') ]}
	SvREFCNT_inc_simple_NN(meta);

	PUSHMARK(SP);
	XPUSHs(meta);
	PUTBACK;
	count = call_method("_eval_environment", G_SCALAR);
	if (count != 1) croak("Metaclass _eval_environment returned nothing!");
	SPAGAIN;
	HV* env = MUTABLE_HV(SvRV(POPs));
	SvREFCNT_inc_simple_NN(env); // Lazily keeping a ref to its contents
	PUTBACK;

	// From Class::MOP::Class
	defaults = AvARRAY(MUTABLE_AV(SvRV(SvRV(*hv_fetch(env, "\$defaults", 9, 0)))));

	// From Moose::Meta::Class
	triggers = AvARRAY(MUTABLE_AV(SvRV(SvRV(*hv_fetch(env, "\$triggers", 9, 0)))));
	type_coercions = AvARRAY(MUTABLE_AV(SvRV(*hv_fetch(env, "\@type_coercions", 15, 0))));
	type_constraint_bodies = AvARRAY(MUTABLE_AV(SvRV(*hv_fetch(env, "\@type_constraint_bodies", 23, 0))));
	type_constraint_messages = AvARRAY(MUTABLE_AV(SvRV(*hv_fetch(env, "\@type_constraint_messages", 25, 0))));
END

	my @attrs = $self->get_all_attributes;

	push @code, map { defined && $_->can('xs_inline_boot') ? $_->xs_inline_boot : () } @attrs;

	if (any { defined && $_->has_initializer } @attrs) {
		push @code, 'attrs = AvARRAY(MUTABLE_AV(SvRV(SvRV(*hv_fetch(env, "$attrs", 6, 0)))));';
	}

	push @code, $self->get_meta_instance->xs_boot;

	return @code;
}

sub _xs_BUILDALL {
	my ($self, $instance) = @_;

	my @code;
	for my $method (reverse $self->find_all_methods_by_name('BUILD')) {
		push @code,
			$self->_xs_call_method($instance, \'BUILD', ['sv_2mortal(newRV_inc(params))'],
			'discard');
	}

	return @code;
}

sub _xs_class_of {
	my ($self, $class, $meta) = @_;

	#<<<
	return (
		$self->_xs_call('pv', \'Class::MOP::class_of', [$class], 'one'),
		"SV* $meta = POPs;",
		"SPAGAIN;",
	);
	#>>>
}

sub _xs_delegate_scalar {
	my ($self, $class, $method, $return, $SToff) = @_;
	$return //= 1;
	$SToff  //= 1;

	my @code = <<"END";
	PUSHMARK(SP);
	EXTEND(SP, items - $SToff + 1);
	PUSHs($class);
	for (I32 i = $SToff; i < items; i++) {
		PUSHs(ST(i));
	}
	PUTBACK;
	count = call_method("$method", G_SCALAR);
	SPAGAIN;

	if (count != 1) {
		const char* classname = (sv_isobject($class) ? sv_reftype(SvRV($class), 1) : SvPV_nolen($class));
		croak("Expected call to %s::$method to return one value, got %d", classname, count);
	}
END

	if ($return) {
		#<<<
		push @code, (
			'ST(0) = retST(0);',
			'XSRETURN(1);',
		);
		#>>>
	}

	@code;
}

sub _xs_extra_init {
	my ($self, $instance) = @_;

	return ($self->_xs_triggers($instance), $self->_xs_BUILDALL($instance),);
}

sub _xs_fallback_constructor {
	my ($self, $class) = @_;


	return ("if (!sv_eq($class, class_name)) {",
		$self->_xs_delegate_scalar($class, 'Moose::Object::new'), '}',);
}

sub _xs_generate_instance {
	my ($self, $instance, $instance_slots, $class) = @_;
	my $mi = $self->get_meta_instance;
	$mi->xs_create_instance($instance, $instance_slots, $class);
}

sub _xs_headers {
	my ($self) = @_;
	my @attrs = $self->get_all_attributes;

	my @code = (<<"END");
	SV *class_name, *meta;
	SV **defaults, **attrs, **triggers, **type_coercions,
		**type_constraint_bodies, **type_constraint_messages;
END

	for my $attr (@attrs) {
		next unless $attr->can('type_constraint') and my $tc = $attr->type_constraint;
		next unless $tc->can('xs_inline_headers') and my $h  = $tc->xs_inline_headers;
		push @code, $h;
	}

	push @code, $self->get_meta_instance->xs_headers;

	return @code;
}

sub _xs_init_attr {
	my ($self, $instance, $instance_slots, $attr, $idx) = @_;

	if (defined(my $init_arg = $attr->init_arg)) {
		my @code = (
			'SV** param = hv_fetch(params, "'
				. quotecmeta($init_arg) . '", '
				. length($init_arg) . ', 0);',
			'if (param) {',
			$self->_xs_init_attr_from_constructor($instance, $instance_slots, $attr, $idx),
			'}',
		);

		if (my @default
			= $self->_xs_init_attr_from_default($instance, $instance_slots, $attr, $idx))
		{
			push @code, 'else {', @default, '}';
		}
		elsif ($attr->can('is_required') && $attr->is_required && !$attr->is_lazy) {
			push @code,
				(
				'else {',
				$self->_xs_throw_moose_exception(
					'AttributeIsRequired',
					params         => 'sv_2mortal(newRV_inc(params))',
					class_name     => 'class_name',
					attribute_name => \($attr->name),
				),
				'}'
				);
		}

		return @code;
	}
	elsif (my @default = $self->_xs_init_attr_from_default($instance, $instance_slots, $attr, $idx))
	{
		return @default;
	}
	else {
		return ();
	}
}

sub _xs_init_attr_from_constructor {
	my ($self, $instance, $instance_slots, $attr, $idx) = @_;

	return $self->_xs_init_attr_using('*param', $instance, $instance_slots, $attr, $idx);
}

sub _xs_init_attr_from_default {
	my ($self, $instance, $instance_slots, $attr, $idx) = @_;

	return if $attr->can('is_lazy') && $attr->is_lazy;

	# Some of the tests use plain old CMOP attributes, so support them.
	# Otherwise we complain.
	my $generate_default
		= ref $attr eq 'Class::MOP::Attribute'
		? MooseX::XSor::XS::Meta::Attribute->can('_xs_generate_default')
		: $attr->can('_xs_generate_default')
		or die "Attr metaclass for @{[ $attr->name ]} doesn't support _xs_generate_default!";

	my ($default, @code) = $attr->$generate_default($instance, "default_$idx", "defaults[$idx]");
	return unless $default;

	return (@code, $self->_xs_init_attr_using($default, $instance, $instance_slots, $attr, $idx));
}

sub _xs_init_attr_using {
	my ($self, $value, $instance, $instance_slots, $attr, $idx) = @_;

	my @code;
	if ($attr->can('_xs_set_value')) {
		@code = $attr->_xs_set_value(
			$instance, $instance_slots, $value, "type_constraint_bodies[$idx]",
			"type_coercions[$idx]", "type_constraint_messages[$idx]",
			'constructor',
		);
	}
	elsif (ref $attr eq 'Class::MOP::Attribute') {
		# Some of the tests use these.
		# PP inlined accessors will of course fail if they try to access
		# anything but a hash
		my $mi = $self->get_meta_instance;
		@code = $mi->xs_set_slot_value($instance_slots, $attr->name, $value) . ';';
	}
	else {
		die "Attr @{[ $attr->name ]} doesn't implement _xs_set_value!";
	}

	if ($attr->has_initializer) {
		push @code,
			(
			$self->_xs_call_method(
				"attrs[$idx]",                                \'set_initial_value',
				[ $attr->_xs_instance_get($instance_slots) ], 'discard'
			));
	}

	return @code;
}

sub _xs_new_object {
	my ($self) = @_;
	return (
		$self->_xs_shift_self('class'),
		'if (sv_isobject(class)) class = sv_ref(0, SvRV(class), 1);',
		$self->_xs_fallback_constructor('class'),
		$self->_xs_params('params', 'class'),
		$self->_xs_generate_instance('instance', 'instance_slots', 'class'),
		$self->_xs_slot_initalizers('instance', 'instance_slots'),
		$self->_xs_preserve_weak_metaclasses,
		$self->_xs_extra_init('instance'),
		'ST(0) = instance;',
		'XSRETURN(1);',
	);
}

sub _xs_params {
	my ($self, $params, $args) = @_;
	my $buildargs = $self->find_method_by_name('BUILDARGS');

	if (!$buildargs or $buildargs->body == \&Moose::Object::BUILDARGS) {
		my $class = $self->name;
		# XXX: Do we need to conditionally copy params in case they get modified in BUILDALL later?
		return <<"END"
			HV* $params;
			if (items == 2) {
				if (SvHROK(ST(1))) {
					$params = MUTABLE_HV(SvRV(ST(1)));
				}
				else {
					@{[ $self->_xs_throw_moose_exception('SingleParamsToNewMustBeHashRef') ]}
				}
			}
			else {
				if (items % 2 == 0) {
					warn("The new() method for $class expects a hash reference or a key/value list. You passed an odd number of arguments");
					PUSHs(&PL_sv_undef);
					PUTBACK;
				}
				$params = newHV();
				sv_2mortal($params);

				for (I32 i = 1; i < items; i += 2) {
					SV* val = ST(i + 1);
					SvREFCNT_inc_simple_NN(val);
					hv_store_ent($params, ST(i), val, 0);
				}

			}
END
	}
	else {
		my @code = $self->_xs_delegate_scalar('class', 'BUILDARGS', !'return');
		if ($self->xs_sanity_checking eq 'paranoid') {
			my $class  = $buildargs->associated_metaclass->name;
			my $method = $buildargs->name;

			# XXX: Make some exception classes. Tell them what got returned instead
			push @code,
				(
				'if (!SvHROK(retST(0))) {',
				qq{croak("Call to $class->$method must return a hashref.");}, '}',
				);
		}

		push @code, "HV* $params = MUTABLE_HV(SvRV(POPs));", "PUTBACK;";

		return @code;
	}
}

sub _xs_prefix {
	shift->name =~ s{::}{__}gr . '__';
}

sub _xs_preserve_weak_metaclasses {
	my ($self) = @_;

	return unless Class::MOP::metaclass_is_weak($self->name);

	return (
		$self->_xs_class_of('class', 'weak_metaclass'),
		$self->get_meta_instance->_xs_set_mop_slot('instance_slots', 'weak_metaclass'),
	);
}

sub _xs_shift_self {
	my ($self, $self_or_class) = @_;
	$self_or_class //= 'self';
	my @code;

	if ($self->xs_sanity_checking eq 'paranoid') {
		push @code, 'if (items == 0)',
			'croak("Call to class or instance method as a function not allowed");';

		if ($self_or_class eq 'self') {
			push @code, 'if (!sv_isobject(ST(0)))', 'croak("Expected $self to be an object");';

			push @code, $self->get_meta_instance->xs_check_self('ST(0)')
				if $self->get_meta_instance->can('xs_check_self');
		}
	}

	push @code, "SV* $self_or_class = ST(0);";

	@code;
}

sub _xs_slot_initalizers {
	my ($self, $instance, $instance_slots) = @_;
	my $i = 0;
	map { $self->_xs_slot_initializer($instance, $instance_slots, $_, $i++) }
		sort { $a->name cmp $b->name } $self->get_all_attributes;
}

sub _xs_slot_initializer {
	my ($self, $instance, $instance_slots, $attr, $idx) = @_;
	#<<<
	(
		'// ' . $attr->name,
		'{',
			$self->get_meta_instance->xs_initialize_slot($instance_slots, $attr),
			$self->_xs_init_attr($instance, $instance_slots, $attr, $idx),
		'}',
	);
	#>>>
}

sub _xs_triggers {
	my ($self, $instance) = @_;
	my @code;

	my @attrs = sort { $a->name cmp $b->name } $self->get_all_attributes;
	for my $i (0 .. $#attrs) {
		my $attr = $attrs[$i];

		next unless $attr->can('has_trigger') && $attr->has_trigger;
		next unless defined(my $init_arg = $attr->init_arg);

		#<<<
		push @code, (
			qq#if (hv_exists(params, "$init_arg", @{[ length $init_arg ]})) {#,
				$self->_xs_call(
					'sv', "triggers[$i]",
					[ $instance, $attr->_xs_instance_get('instance_slots') ], 'discard',
				),
			'}'
		);
		#>>>
	}

	@code;
}

1;
