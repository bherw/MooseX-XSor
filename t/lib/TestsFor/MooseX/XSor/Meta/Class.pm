package TestsFor::MooseX::XSor::Meta::Class;

use v5.14;
use Carp 'confess';
use Class::Load qw(load_optional_class);
use Moose::Util::TypeConstraints;
use Test::Class::Moose;
use Test::Moose;
use Test::Fatal;

use parent qw(MooseX::XSor::Test::Requires);
with 'MooseX::XSor::Role::MooseVariantTester';

subtype 'Death', as 'Int', where { $_ == 1 };
coerce 'Death', from 'Any', via {confess};

has '_class_with_varied_attrs',
	is      => 'ro',
	lazy    => 1,
	default => sub {
	my ($self) = @_;
	my $class = $self->_get_anon_package;

	$self->_eval_class(<<'END', '#Foo' => $class);
		package #Foo {
			use #Moose;
			use Moose::Util::TypeConstraints;

			subtype '#Foo::Int', as 'Int';
			coerce '#Foo::Int' => from 'Str' => via { length $_ ? $_ : 69 };

			has 'foo' => (is => 'rw', isa => '#Foo::Int');
			has 'baz' => (is => 'rw', isa => '#Foo::Int');
			has 'zot' => (is => 'rw', isa => '#Foo::Int', init_arg => undef);
			has 'moo' => (is => 'rw', isa => '#Foo::Int', coerce => 1, default => '', required => 1);
			has 'boo' => (
				is       => 'rw',
				isa      => '#Foo::Int',
				coerce   => 1,
				builder  => '_build_boo',
				required => 1,
			);
			has 'moo_cv' => (is => 'rw', isa => '#Foo::Int', coerce => 1, default => sub { '' });

			sub _build_boo {''}

			#Foo->meta->add_attribute(Class::MOP::Attribute->new('bar' => (accessor => 'bar')));
			#Foo->meta->make_immutable;
		}
END
	$class;
	};

sub test_buildargs {
	my ($self)    = @_;
	my $foo_class = $self->_get_anon_package;
	my $bar_class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Foo' => $foo_class, '#Bar' => $bar_class);
	package #Foo;
	use #Moose;

	has bar => (is => "rw");
	has baz => (is => "rw");

	sub BUILDARGS {
		my ($self, @args) = @_;
		unshift @args, "bar" if @args % 2 == 1;
		return {@args};
	}

	__PACKAGE__->meta->make_immutable;

	package #Bar;
	use #Moose;

	extends qw(#Foo);

	__PACKAGE__->meta->make_immutable;
END

	foreach my $class ($foo_class, $bar_class) {
		is($class->new->bar, undef, "no args");
		is($class->new(bar => 42)->bar, 42, "normal args");
		is($class->new(37)->bar, 37, "single arg");
		{
			my $o = $class->new(bar => 42, baz => 47);
			is($o->bar, 42, '... got the right bar');
			is($o->baz, 47, '... got the right bar');
		}
		{
			my $o = $class->new(42, baz => 47);
			is($o->bar, 42, '... got the right bar');
			is($o->baz, 47, '... got the right bar');
		}
	}
}

sub test_buildargs_warnings : Requires(Test::Output) {
	my ($self) = @_;
	my $class = $self->_no_attr_class;
	is(
		exception {
			Test::Output::stderr_like(
				sub { $class->new(x => 42, 'y') },
				qr{The new\(\) method for $class expects a hash reference or a key/value list. You passed an odd number of arguments at},
				'warning when passing an odd number of args to new()'
			);

			Test::Output::stderr_unlike(
				sub { $class->new(x => 42, 'y') },
				qr{\QOdd number of elements in anonymous hash},
				'we suppress the standard warning from Perl for an odd number of elements in a hash'
			);

			Test::Output::stderr_is(sub { $class->new({ x => 42 }) },
				q{}, 'we handle a single hashref to new without errors');
		},
		undef
	);
}

sub test_constructor_errors {
	my ($self) = @_;
	my $foo_class = $self->_no_attr_class;

	like(
		exception { $foo_class->new(1) },
		qr/\QSingle parameters to new() must be a HASH ref/,
		'Non-ref provided to immutable constructor gives useful error message'
	);
	like(
		exception { $foo_class->new(\1) },
		qr/\QSingle parameters to new() must be a HASH ref/,
		'Scalar ref provided to immutable constructor gives useful error message'
	);
	like(
		exception { $foo_class->new(undef) },
		qr/\QSingle parameters to new() must be a HASH ref/,
		'undef provided to immutable constructor gives useful error message'
	);
}

sub test_constructor_fallback {
	my ($self)    = @_;
	my $foo_class = $self->_get_anon_package;
	my $bar_class = $self->_get_anon_package;
	my $baz_class = $self->_get_anon_package;

	my $classes = <<'END';
	package #Foo {
		use #Moose;
		has foo => (is => 'ro');
	}

	package #Bar {
		use #Moose;
		extends '#Foo';
		has bar => (is => 'ro');
	}

	package #Baz {
		use #Moose;
		extends '#Foo';
		has baz => (is => 'ro');
		# not making immutable, inheriting Foo's inlined constructor
	}
END
	$self->_eval_class($classes, '#Foo' => $foo_class, '#Bar' => $bar_class, '#Baz' => $baz_class,);

	my $bar = $bar_class->new(foo => 12, bar => 25);
	is($bar->foo, 12, 'got right value for foo');
	is($bar->bar, 25, 'got right value for bar');

	$foo_class->meta->make_immutable;

	my $baz = $baz_class->new(foo => 42, baz => 27);
	is($baz->foo, 42, 'got right value for foo');
	is($baz->baz, 27, 'got right value for baz');
}

sub test_constructor_is_not_moose : Requires(Test::Output) {
	my ($self)               = @_;
	my $not_moose_class      = $self->_get_anon_package;
	my $foo_class            = $self->_get_anon_package;
	my $baz_class            = $self->_no_attr_class;
	my $quux_class           = $self->_get_anon_package;
	my $my_constructor_class = $self->_get_anon_package;
	my $custom_cons_class    = $self->_get_anon_package;
	my $subclass_class       = $self->_get_anon_package;

	my $code = <<'END';
	package #NotMoose {
		sub new {
			my $class = shift;
			return bless { not_moose => 1 }, $class;
		}
	}

	package #Foo {
		use #Moose;
		extends '#NotMoose';
	}

	package #Quux {
		use #Moose;
		extends '#Baz';
	}

	package #MyConstructor {
		use parent 'Moose::Meta::Method::Constructor';
	}

	package #CustomCons {
		use #Moose;

		__PACKAGE__->meta->make_immutable(constructor_class => '#MyConstructor');
	}

	package #Subclass {
		use #Moose;
		extends '#CustomCons';
	}
END
	$self->_eval_class(
		$code,
		'#NotMoose'      => $not_moose_class,
		'#Foo'           => $foo_class,
		'#Baz'           => $baz_class,
		'#Quux'          => $quux_class,
		'#MyConstructor' => $my_constructor_class,
		'#CustomCons'    => $custom_cons_class,
		'#Subclass'      => $subclass_class,
	);

	Test::Output::stderr_like(
		sub { $foo_class->meta->make_immutable },
		qr/Not inlining 'new' for $foo_class since it is not inheriting the default Moose::Object::new\s+If you are certain you don't need to inline your constructor, specify inline_constructor => 0 in your call to $foo_class->meta->make_immutable/,
		'got a warning that Foo may not have an inlined constructor'
	);

	is(
		$foo_class->meta->find_method_by_name('new')->body,
		$not_moose_class->can('new'),
		'Foo->new is inherited from NotMoose'
	);

	$foo_class->meta->make_mutable;

	Test::Output::stderr_is(sub { $foo_class->meta->make_immutable(replace_constructor => 1) },
		q{}, 'no warning when replace_constructor is true');

	is($foo_class->meta->find_method_by_name('new')->package_name,
		$foo_class, 'Bar->new is inlined, and not inherited from NotMoose');

	Test::Output::stderr_is(sub { $quux_class->meta->make_immutable },
		q{}, 'no warning when inheriting from a class that has already made itself immutable');

	Test::Output::stderr_is(sub { $subclass_class->meta->make_immutable },
		q{}, 'no warning when inheriting from a class that has already made itself immutable');
}

sub test_constructor_is_wrapped : Requires(Test::Output) {
	my ($self)           = @_;
	my $modded_new_class = $self->_get_anon_package;
	my $foo_class        = $self->_get_anon_package;

	$self->_eval_class(<<'END', '#ModdedNew' => $modded_new_class, '#Foo' => $foo_class);
	package #ModdedNew {
		use #Moose;
		before 'new' => sub { };
	}

	package #Foo {
		use #Moose;
		extends '#ModdedNew';
	}
END

	Test::Output::stderr_like(
		sub { $foo_class->meta->make_immutable },
		qr/Not inlining 'new' for $foo_class since it has method modifiers which would be lost if it were inlined/,
		'got a warning that Foo may not have an inlined constructor'
	);
}

=pod

This tests to make sure that the inlined constructor
has all the type constraints in order, even in the
cases when there is no type constraint available, such
as with a Class::MOP::Attribute object.

=cut

sub test_constructor_type_checking {
	my ($self) = @_;
	my $foo_class = $self->_class_with_varied_attrs;

	is(
		exception {
			my $f = $foo_class->new(foo => 10, bar => "Hello World", baz => 10, zot => 4);
			is($f->moo, 69, "Type coercion works as expected on default");
			is($f->boo, 69, "Type coercion works as expected on builder");
		},
		undef,
		"... this passes the constuctor correctly"
	);

	is(
		exception {
			$foo_class->new(foo => 10, bar => "Hello World", baz => 10, zot => "not an int");
		},
		undef,
		"... the constructor doesn't care about 'zot'"
	);

	isnt(
		exception {
			$foo_class->new(foo => "Hello World", bar => 100, baz => "Hello World");
		},
		undef,
		"... this fails the constuctor correctly"
	);
}

sub test_default_values {
	my ($self) = @_;
	my $foo_class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Moose' => $self->moose, '#Foo' => $foo_class);
	package #Foo {
		use #Moose;

		has 'foo' => (is => 'rw', default => q{'});
		has 'bar' => (is => 'rw', default => q{\\});
		has 'baz' => (is => 'rw', default => q{"});
		has 'buz' => (is => 'rw', default => q{"'\\});
		has 'faz' => (is => 'rw', default => qq{\0});
		has 'foo_l' => (is => 'rw', default => q{'},    lazy => 1);
		has 'bar_l' => (is => 'rw', default => q{\\},   lazy => 1);
		has 'baz_l' => (is => 'rw', default => q{"},    lazy => 1);
		has 'buz_l' => (is => 'rw', default => q{"'\\}, lazy => 1);
		has 'faz_l' => (is => 'rw', default => qq{\0},  lazy => 1);

		has 'default_cv' => (is => 'rw', default => sub { 2 });
		has 'default_tc_cv' => (is => 'rw', isa => 'Int', default => sub { 2 });
		has 'default_lazy_cv' => (is => 'rw', lazy => 1, default => sub { 2 });
		has 'default_lazy_tc_cv' => (is => 'rw', isa => 'Int', lazy => 1, default => sub { 2 });
		has 'builder' => (is => 'rw', builder => '_build_builder');
		has 'builder_tc' => (is => 'rw', isa => 'Int', builder => '_build_builder');
		has 'builder_lazy' => (is => 'rw', lazy => 1, builder => '_build_builder');
		has 'builder_lazy_tc' => (is => 'rw', isa => 'Int', lazy => 1, builder => '_build_builder');
		sub _build_builder { 2 }
	}
END

	is exception { __PACKAGE__->meta->make_immutable }, undef,
		'no errors making a package immutable when it has default values that could break quoting';

	my $foo = $foo_class->new;

	ok(!$foo->meta->get_attribute($_)->has_value($foo), "Attribute $_ has no value (immutable)")
		for qw(foo_l bar_l baz_l buz_l faz_l
		default_lazy_cv default_lazy_tc_cv builder_lazy builder_lazy_tc);

	is($foo->foo,   q{'},    'default value for foo attr');
	is($foo->bar,   q{\\},   'default value for bar attr');
	is($foo->baz,   q{"},    'default value for baz attr');
	is($foo->buz,   q{"'\\}, 'default value for buz attr');
	is($foo->faz,   qq{\0},  'default value for faz attr');
	is($foo->foo_l, q{'},    'default value for foo attr');
	is($foo->bar_l, q{\\},   'default value for bar attr');
	is($foo->baz_l, q{"},    'default value for baz attr');
	is($foo->buz_l, q{"'\\}, 'default value for buz attr');
	is($foo->faz_l, qq{\0},  'default value for faz attr');

	is($foo->$_, 2, "default value for $_ attr")
		for qw(default_cv default_lazy_cv default_lazy_cv default_lazy_tc_cv
		builder builder_lazy builder_tc builder_lazy_tc);
}

sub test_definition_context {
	my ($self) = @_;
	$self->_eval_class(<<'END', '#Moose' => $self->moose, '#Foo' => $self->_get_anon_package);

	my ($attr_foo_line, $attr_bar_line, $ctor_line);
	package #Foo {
		use #Moose;

		has foo => (is => 'rw', isa => 'Death', coerce => 1);
		$attr_foo_line = __LINE__ - 1;

		has bar => (accessor => 'baz', isa => 'Death', coerce => 1);
		$attr_bar_line = __LINE__ - 1;

		__PACKAGE__->meta->make_immutable;
		$ctor_line = __LINE__ - 1;
	}

	{
		local $TODO = "XSUBs not added to stack trace";
		like(
			exception { #Foo->new(foo => 2) },
			qr/called at constructor #Foo::new \(defined at \(eval \d+\) line $ctor_line\)/,
			"got definition context for the constructor"
		);
	}

	like(
		exception { my $f = #Foo->new(foo => 1); $f->foo(2) },
		qr/called at accessor #Foo::foo \(defined at \(eval \d+\) line $attr_foo_line\)/,
		"got definition context for the accessor"
	);

	like(
		exception { my $f = #Foo->new(foo => 1); $f->baz(2) },
		qr/called at accessor #Foo::baz of attribute bar \(defined at \(eval \d+\) line $attr_bar_line\)/,
		"got definition context for the accessor"
	);
END
}

sub test_leaks_in_constructor : Requires(Test::LeakTrace) {
	my ($self)    = @_;
	my $foo_class = $self->_class_with_varied_attrs;
	my $bar_class = $self->_get_anon_package;

	$self->_eval_class(<<'END', '#Bar' => $bar_class);
	package #Bar {
		use #Moose;

		has 'a', is => 'rw';

		sub BUILDARGS {
			shift;
			+{@_};
		}
		__PACKAGE__->meta->make_immutable(debug => 0);
	}
END
	my $no_leaks_ok = \&Test::LeakTrace::no_leaks_ok;

	&$no_leaks_ok(
		sub {
			my $foo  = $foo_class->new;
			my $foo2 = $foo->new;
		},
		'calling new on a instance'
	);

	&$no_leaks_ok(
		sub {
			my $foo = $foo_class->new(a => 18);
		},
		'inlined BUILDARGS - hash'
	);

	&$no_leaks_ok(
		sub {
			my $foo = $foo_class->new({ a => 18 });
		},
		'inlined BUILDARGS - hashref'
	);

	&$no_leaks_ok(
		sub {
			my $bar = $bar_class->new(a => 18);
		},
		'call to BUILDARGS'
	);

	&$no_leaks_ok(
		sub {
			my $foo = $foo_class->new(tc => 18);
		},
		'type constraint'
	);
}

sub test_rebless {
	my ($self)       = @_;
	my $parent_class = $self->_get_anon_package;
	my $child_class  = $self->_get_anon_package;

	$self->_eval_class(<<'END', '#Parent' => $parent_class, '#Child' => $child_class);
	subtype '#Parent::Positive' => as 'Num' => where { $_ > 0 };

	package #Parent {
		use #Moose;

		has name => (is => 'rw', isa => 'Str');
		has lazy_classname => (is => 'ro', lazy => 1, default => sub {"Parent"});
		has type_constrained => (is => 'rw', isa => 'Num', default => 5.5);
	}

	package #Child {
		use #Moose;
		extends '#Parent';

		has '+name' => (default => 'Junior');
		has '+lazy_classname' => (default => sub {"Child"});
		has '+type_constrained' => (isa => 'Int', default => 100);

		our %trigger_calls;
		our %initializer_calls;

		has new_attr => (
			is      => 'rw',
			isa     => 'Str',
			trigger => sub {
				my ($self, $val, $attr) = @_;
				$trigger_calls{new_attr}++;
			},
			initializer => sub {
				my ($self, $value, $set, $attr) = @_;
				$initializer_calls{new_attr}++;
				$set->($value);
			},
		);
	}
END

	my @classes = ($parent_class, $child_class);
	with_immutable {
		my $foo = $parent_class->new;
		my $bar = $parent_class->new;

		is(blessed($foo),        $parent_class, 'Parent->new gives a Parent object');
		is($foo->name,           undef,         'No name yet');
		is($foo->lazy_classname, 'Parent',      "lazy attribute initialized");
		is(exception { $foo->type_constrained(10.5) }, undef, "Num type constraint for now..");

		# try to rebless, except it will fail due to Child's stricter type constraint
		like(
			exception { $child_class->meta->rebless_instance($foo) },
			qr/^Attribute \(type_constrained\) does not pass the type constraint because\: Validation failed for 'Int' with value 10\.5/,
			'... this failed because of type check'
		);
		like(
			exception { $child_class->meta->rebless_instance($bar) },
			qr/^Attribute \(type_constrained\) does not pass the type constraint because\: Validation failed for 'Int' with value 5\.5/,
			'... this failed because of type check'
		);

		$foo->type_constrained(10);
		$bar->type_constrained(5);

		$child_class->meta->rebless_instance($foo);
		$child_class->meta->rebless_instance($bar, new_attr => 'blah');

		is(blessed($foo), $child_class, 'successfully reblessed into Child');
		is($foo->name,    'Junior',     "Child->name's default came through");

		is($foo->lazy_classname, 'Parent', "lazy attribute was already initialized");
		is($bar->lazy_classname, 'Child',  "lazy attribute just now initialized");

		like(
			exception { $foo->type_constrained(10.5) },
			qr/^Attribute \(type_constrained\) does not pass the type constraint because\: Validation failed for 'Int' with value 10\.5/,
			'... this failed because of type check'
		);

		{
			no strict 'refs';
			is_deeply(
				\%{"${child_class}::trigger_calls"},
				{ new_attr => 1 },
				'Trigger fired on rebless_instance'
			);
			is_deeply(
				\%{"${child_class}::initializer_calls"},
				{ new_attr => 1 },
				'Initializer fired on rebless_instance'
			);

			undef %{"${child_class}::trigger_calls"};
			undef %{"${child_class}::initializer_calls"};
		}

	}
	@classes;
}

sub test_triggers {
	my ($self) = @_;
	my $foo_class = $self->_get_anon_package;

	$self->_eval_class(<<'END', '#Moose' => $self->moose, '#Foo' => $foo_class);
	package #Foo {
		use #Moose;

		has 'foo' => (
			is      => 'rw',
			isa     => 'Maybe[Str]',
			trigger => sub {
				die "Pulling the Foo trigger\n";
			});

		has 'bar' => (is => 'rw', isa => 'Maybe[Str]');

		has 'baz' => (
			is      => 'rw',
			isa     => 'Maybe[Str]',
			trigger => sub {
				die "Pulling the Baz trigger\n";
			});

		__PACKAGE__->meta->make_immutable;
	}
END

	like(
		exception { $foo_class->new(foo => 'bar') },
		qr/^Pulling the Foo trigger/,
		"trigger from immutable constructor"
	);

	like(
		exception { $foo_class->new(baz => 'bar') },
		qr/^Pulling the Baz trigger/,
		"trigger from immutable constructor"
	);

	is(exception { $foo_class->new(bar => 'bar') }, undef, '... no triggers called');

}

1;
