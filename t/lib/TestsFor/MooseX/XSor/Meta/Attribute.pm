package TestsFor::MooseX::XSor::Meta::Attribute;

use v5.14;
use Test::Class::Moose;
use Test::Moose;
use Test::Fatal;

use parent qw(MooseX::XSor::Test::Requires);
with 'MooseX::XSor::Role::MooseVariantTester';

has 'accessor_class',
	is      => 'ro',
	lazy    => 1,
	default => sub {
	my ($self) = @_;
	my $class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Class' => $class);
	package #Class {
		use #Moose;
		use Moose::Util::TypeConstraints;

		subtype '#Class::Int', as 'Int';
		coerce '#Class::Int', from 'Str', via { 42 };
		
		has 'foo', accessor => 'foo';

		has 'lazy',
			accessor  => 'lazy',
			lazy      => 1,
			default   => sub { 10 },
			predicate => 'has_lazy';

		has 'required',
			accessor => 'required',
			required => 1;

		has 'int',
			accessor => 'int',
			isa      => 'Int';

		has 'weak',
			accessor  => 'weak',
			weak_ref  => 1,
			predicate => 'has_weak';

		has 'builder',
			accessor => 'builder',
			lazy     => 1,
			builder  => '_build_builder';

		has 'coercer',
			accessor => 'coercer',
			isa      => '#Class::Int',
			coerce   => 1,
			lazy     => 1,
			default  => sub { 'hi' };

		has 'trigger',
			accessor => 'trigger',
			trigger  => sub {
				my ($self, $val, $old) = @_;
			};

		sub _build_builder { 2 }

		#Class->meta->make_immutable;
	}
END
	$class;
	};

has 'autoderef_class',
	is      => 'ro',
	lazy    => 1,
	default => sub {
	my ($self) = @_;
	my $class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Class' => $class);
	package #Class {
		use #Moose;

		has s_rw => (is => 'rw');
		has s_ro => (is => 'ro');
		has a_rw => (is => 'rw', isa => 'ArrayRef[Ref]', auto_deref => 1);
		has a_ro => (is => 'ro', isa => 'ArrayRef', auto_deref => 1);
		has h_rw => (is => 'rw', isa => 'HashRef',  auto_deref => 1);
		has h_ro => (is => 'ro', isa => 'HashRef',  auto_deref => 1);

		#Class->meta->make_immutable;
	}
END
	$class;
	};

sub test_accessor_generation {
	my ($self) = @_;
	my $class = $self->accessor_class;

	my $obj = $class->new(required => 'required');
	my $mi = $class->meta->get_meta_instance;

	is $obj->foo, undef, 'got an unset value';
	$obj->foo(100);
	is $obj->foo, 100, 'got the correct set value';
	ok !$mi->slot_value_is_weak($obj, 'foo'), 'it is not a weak reference';

	isnt exception { $class->new }, undef, 'cannot create without the required attr';
	is $obj->required, 'required', 'got the right value';
	$obj->required(100);
	is $obj->required, 100, 'got the correct set value';
	ok !$mi->slot_value_is_weak($obj, 'required'), 'not a weak ref';

	ok !$obj->has_lazy, 'no value in lazy slot';
	is $obj->lazy, 10, 'got the lazy value';

	is $obj->int, undef, 'got an unset value';
	$obj->int(100);
	is $obj->int, 100, 'got the correct set value';
	isa_ok exception { $obj->int("Hello world") },
		'Moose::Exception::ValidationFailedForInlineTypeConstraint',
		'int died due to type constraint';
	ok !$mi->slot_value_is_weak($obj, 'int'), 'not a weak ref';

	my $weak = [];
	ok !$obj->has_weak, 'weak is not set';
	is $obj->weak, undef, 'got an unset value';
	$obj->weak($weak);
	is $obj->weak, $weak, 'got the correct set value';
	ok $mi->slot_value_is_weak($obj, 'weak'), 'weak reference';

	undef $weak;
	ok $obj->has_weak, 'weak still set';
	is $obj->weak, undef, 'weak reference undefined';
}

sub test_accessor_leaks : Requires(Test::LeakTrace) {
	my ($self)      = @_;
	my $class       = $self->accessor_class;
	my $no_leaks_ok = \&Test::LeakTrace::no_leaks_ok;

	&$no_leaks_ok(
		sub {
			my $obj = $class->new(required => 'required');
			$obj->foo(100);
		},
		'basic accessor - set'
	);
	&$no_leaks_ok(
		sub {
			my $obj = $class->new(foo => 100, required => 'required');
			my $foo = $obj->foo;
		},
		'basic accessor - get'
	);

	&$no_leaks_ok(
		sub {
			my $obj = $class->new(required => 'required');
			my $lazy = $obj->lazy;
		},
		'lazy - get'
	);

	&$no_leaks_ok(
		sub {
			my $obj = $class->new(required => 'required');
			$obj->int(100);
		},
		'tc - set'
	);

	&$no_leaks_ok(
		sub {
			my $obj = $class->new(required => 'required');
			my $built = $obj->builder;
		},
		'builder - get'
	);

	&$no_leaks_ok(
		sub {
			my $obj = $class->new(required => 'required');
			my $coerce = $obj->coercer;
		},
		'coerce - coerced lazy default'
	);

	&$no_leaks_ok(
		sub {
			my $obj = $class->new(required => 'required');
			$obj->coercer('hi');
		},
		'coerce - coerced set value'
	);

	&$no_leaks_ok(
		sub {
			my $obj = $class->new(required => 'required');
			$obj->trigger(2);
		},
		'trigger - set'
	);

	my $autoderef_class = $self->autoderef_class;

	&$no_leaks_ok(
		sub {
			my $obj = $autoderef_class->new(a_rw => [ \1, \2, \3 ]);
			my @a = $obj->a_rw;
		},
		'autoderef array - get'
	);

	&$no_leaks_ok(
		sub {
			my $obj = $autoderef_class->new(h_rw => { a => \1, b => \2 });
			my %h = $obj->h_rw;
		},
		'autoderef hash - get'
	);
}

sub test_autoderef {
	my ($self) = @_;
	my $class  = $self->autoderef_class;
	my $o      = $class->new;

	is_deeply [ scalar $o->s_rw ], [undef], 'uninitialized scalar attribute/rw in scalar context';
	is_deeply [ $o->s_rw ],        [undef], 'uninitialized scalar attribute/rw in list context';
	is_deeply [ scalar $o->s_ro ], [undef], 'uninitialized scalar attribute/ro in scalar context';
	is_deeply [ $o->s_ro ],        [undef], 'uninitialized scalar attribute/ro in list context';

	is_deeply [ scalar $o->a_rw ], [undef], 'uninitialized ArrayRef attribute/rw in scalar context';
	is_deeply [ $o->a_rw ], [], 'uninitialized ArrayRef attribute/rw in list context';
	is_deeply [ scalar $o->a_ro ], [undef], 'uninitialized ArrayRef attribute/ro in scalar context';
	is_deeply [ $o->a_ro ], [], 'uninitialized ArrayRef attribute/ro in list context';

	is_deeply [ scalar $o->h_rw ], [undef], 'uninitialized HashRef attribute/rw in scalar context';
	is_deeply [ $o->h_rw ], [], 'uninitialized HashRef attribute/rw in list context';
	is_deeply [ scalar $o->h_ro ], [undef], 'uninitialized HashRef attribute/ro in scalar context';
	is_deeply [ $o->h_ro ], [], 'uninitialized HashRef attribute/ro in list context';

	my ($a, $b, $c) = (1, 2, 3);
	my @array = (\$a, \$b, \$c);
	my %hash = (a => \$a, b => \$b, c => \$c);

	isnt exception { $o->a_rw(@array) }, undef, 'its auto-de-ref-ing, not auto-en-ref-ing';

	$o->a_rw([@array]);
	$o->h_rw({%hash});

	is_deeply [ $o->a_rw ], [@array], 'array in list context';
	is_deeply { $o->h_rw }, {%hash}, 'hash in list context';

	$o = $class->new(a_ro => [undef, undef]);
	is_deeply [ $o->a_ro], [undef, undef], 'array of undef';
}

sub test_coerce_lazy {
	my ($self)        = @_;
	my $header_class  = $self->_get_anon_package;
	my $request_class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Header' => $header_class, '#Request' => $request_class);
	package #Header {
		use #Moose;

		has 'array' => (is => 'ro');
		has 'hash'  => (is => 'ro');

		__PACKAGE__->meta->make_immutable;
	}

	package #Request {
		use #Moose;
		use Moose::Util::TypeConstraints;

		coerce '#Header'
			=> from ArrayRef
				=> via { #Header->new(array => $_[0]) }
			=> from HashRef
				=> via { #Header->new(hash => $_[0]) };

		has 'headers',
			is      => 'rw',
			isa     => '#Header',
			coerce  => 1,
			lazy    => 1,
			default => sub { [ 'content-type', 'text/html' ] };

		__PACKAGE__->meta->make_immutable;
	}
END

	my $r = $request_class->new;

	is exception { $r->headers }, undef,
		'this coerces and passes the type constraint even with lazy';
	is_deeply $r->headers->array, [ 'content-type', 'text/html' ];
}

sub test_lazy_initializers {
	my ($self) = @_;
	my $class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Class' => $class);
	package #Class {
		use #Moose;
		use Test::More;

		has 'normal',
			reader => 'get_normal',
			writer => 'set_normal',
			initializer => sub {
				my ($self, $value, $callback, $attr) = @_;

				isa_ok $attr, 'Moose::Meta::Attribute';
				is $attr->name, 'normal', '... got the right name';

				$callback->($value * 2);
			};

		has 'lazy',
			reader      => 'get_lazy',
			lazy        => 1,
			default     => 10,
			initializer => sub {
				my ($self, $value, $callback, $attr) = @_;

				isa_ok $attr, 'Moose::Meta::Attribute';
				is $attr->name, 'lazy', '... got the right name';

				$callback->($value * 2);
			};

		has 'lazy_w_type',
			reader      => 'get_lazy_w_type',
			isa         => 'Int',
			lazy        => 1,
			default     => 20,
			initializer => sub {
				my ($self, $value, $callback, $attr) = @_;

				isa_ok $attr, 'Moose::Meta::Attribute';
				is $attr->name, 'lazy_w_type', '... got the right name';

				$callback->($value * 2);
			};

		has 'lazy_builder',
			reader      => 'get_lazy_builder',
			builder     => 'get_builder',
			initializer => sub {
				my ($self, $value, $callback, $attr) = @_;

				isa_ok $attr, 'Moose::Meta::Attribute';
				is $attr->name, 'lazy_builder', '... got the right name';

				$callback->($value * 2);
			};

		has 'lazy_builder_w_type',
			reader      => 'get_lazy_builder_w_type',
			isa         => 'Int',
			builder     => 'get_builder_w_type',
			initializer => sub {
				my ($self, $value, $callback, $attr) = @_;

				isa_ok $attr, 'Moose::Meta::Attribute';
				is $attr->name, 'lazy_builder_w_type', '... got the right name';

				$callback->($value * 2);
			};

		has 'fail',
			reader => 'get_fail',
			writer => 'set_fail',
			isa    => 'Int',
			initializer => sub {
				my ($self, $value, $callback, $attr) = @_;

				isa_ok $attr, 'Moose::Meta::Attribute';
				is $attr->name, 'fail', '... got the right name';

				$callback->("Hello $value World");
			};

		sub get_builder        { 100  }
		sub get_builder_w_type { 1000 }

		__PACKAGE__->meta->make_immutable;
	}
END

	my $obj = $class->new(normal => 10);
	is $obj->get_normal,              20;
	is $obj->get_lazy,                20;
	is $obj->get_lazy_w_type,         40;
	is $obj->get_lazy_builder,        200;
	is $obj->get_lazy_builder_w_type, 2000;

	like exception { $class->new(fail => 10) }, qr/Validation failed for 'Int'/;
}

sub test_names {
	my ($self) = @_;

	# Moose's own inlining fails this: '
	for my $attr ('', 0, '"', '', '@type', 'with spaces', '!req') {
		my $class = $self->_get_anon_package;
		$self->_eval_class(<<'END', '#Class' => $class, '#attr' => $attr);
		package #Class {
			use #Moose;

			has '#attr',
				accessor  => 'it',
				clearer   => 'clear_it',
				predicate => 'has_it',
				default   => 1;

			__PACKAGE__->meta->make_immutable;
		}
END

		ok $class->meta->has_attribute($attr), "class has '$attr' attribute";

		my $obj = $class->new;
		ok $obj->has_it, 'predicate';
		is $obj->it,       1, 'accessor - get';
		is $obj->clear_it, 1, 'clearer return value';
		ok !$obj->has_it, 'clearer cleared';
		$obj->it(99);
		is $obj->it, 99, 'accessor set';

		$class = $self->_get_anon_package;
		$self->_eval_class(<<'END', '#Class' => $class, '#attr' => $attr);
		package #Class {
			use #Moose;

			has '#attr',
				reader   => 'get_it',
				writer   => 'set_it',
				isa      => 'Str',
				required => 1;

			__PACKAGE__->meta->make_immutable;
		}
END

		$obj = $class->new($attr => 'Hello world');
		is $obj->get_it, 'Hello world';
		$obj->set_it('bye');
		is $obj->get_it, 'bye';

		like exception { $class->new }, qr/is required/;
	}
}

sub test_octal_defaults {
	my ($self) = @_;
	my $class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Class' => $class);
	package #Class {
		use #Moose;

		has 'a', is => 'ro', isa => 'Str', default => '019600';
		has 'b', is => 'ro', isa => 'Str', default => 017600;
		has 'c', is => 'ro', isa => 'Str', default => 0xFF;
		has 'd', is => 'ro', isa => 'Str', default => '0xFF';
		has 'e', is => 'ro', isa => 'Str', default => '0 but true';

		__PACKAGE__->meta->make_immutable;
	}
END

	my $obj = $class->new;
	is $obj->a, '019600',     'octal in a string';
	is $obj->b, 8064,         'real octal number';
	is $obj->c, 0xFF,         'hexadecimal number';
	is $obj->d, '0xFF',       'hexadecimal in a string';
	is $obj->e, '0 but true', '0 but true';
}

sub test_numeric_defaults {
	my ($self) = @_;
	my $class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Class' => $class);
	package #Class {
		use #Moose;
		has 'a', is => 'ro', default => 100;
		has 'b', is => 'ro', lazy => 1, default => 100;
		has 'c', is => 'ro', isa => 'Int', lazy => 1, default => 100;
		has 'd', is => 'ro', default => 10.5;
		has 'e', is => 'ro', lazy => 1, default => 10.5;
		has 'f', is => 'ro', isa => 'Num', lazy => 1, default => 10.5;
		sub g { 100 }
		sub h { 10.5 }
		__PACKAGE__->meta->make_immutable;
	}
END

	require B;

	my $obj = $class->new;
	for my $meth (qw(a b c g)) {
		my $val   = $obj->$meth;
		my $b     = B::svref_2object(\$val);
		my $flags = $b->FLAGS;
		ok($flags & B::SVf_IOK || $flags & B::SVp_IOK, "it's an int");
		ok(!($flags & B::SVf_POK), "not a string");
	}

	for my $meth (qw(d e f h)) {
		my $val   = $obj->$meth;
		my $b     = B::svref_2object(\$val);
		my $flags = $b->FLAGS;
		ok($flags & B::SVf_NOK || $flags & B::SVp_NOK, "it's a num");
		ok(!($flags & B::SVf_POK), "not a string");
	}
}

sub test_reader_generation {
	my ($self) = @_;
	my $class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Class' => $class);
	package #Class {
		use #Moose;

		has 'foo', reader => 'get_foo';

		has 'lazy',
			reader  => 'get_lazy',
			lazy    => 1,
			default => sub { 10 };

		has 'lazy_weak',
			reader   => 'get_lazy_weak',
			lazy     => 1,
			default  => sub { shift },
			weak_ref => 1;

		__PACKAGE__->meta->make_immutable;
	}
END

	my $mi   = $class->meta->get_meta_instance;
	my $obj  = $class->new;
	my $aref = do {
		no strict 'refs';
		${ $class . '::AREF' };
	};
	my $read_only_e = 'Moose::Exception::CannotAssignValueToReadOnlyAccessor';

	is $obj->get_foo, undef, 'got an undefined value';
	isa_ok exception { $obj->get_foo(100) }, $read_only_e, 'get_foo is a read-only';

	ok !$mi->is_slot_initialized($obj, 'lazy'), 'no value in lazy slot';
	is $obj->get_lazy, 10, 'got lazy value';
	isa_ok exception { $obj->get_lazy(100) }, $read_only_e, 'get_lazy is a read-only';
	is $mi->get_slot_value($obj, 'lazy'), 10, 'lazy value got saved';

	is $obj->get_lazy_weak, $obj, 'got the right value';
	ok $mi->slot_value_is_weak($obj, 'lazy_weak'), 'lazy_weak is weakening references';
}

sub test_requires {
	my ($self) = @_;
	my $class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Class' => $class);
	package #Class {
		use #Moose;

		has 'bar' => (is => 'ro', required => 1);
		has 'baz' => (is => 'rw', required => 1, default => 100);
		has 'boo' => (is => 'rw', required => 1, lazy => 1, default => 50);

		__PACKAGE__->meta->make_immutable;
	}
END

	my $obj = $class->new(bar => 10, baz => 20, boo => 100);

	is($obj->bar, 10,  '... got the right bar');
	is($obj->baz, 20,  '... got the right baz');
	is($obj->boo, 100, '... got the right boo');


	$obj = $class->new(bar => 10, boo => 5);

	is($obj->bar, 10,  '... got the right bar');
	is($obj->baz, 100, '... got the right baz');
	is($obj->boo, 5,   '... got the right boo');

	$obj = $class->new(bar => 10);

	is($obj->bar, 10,  '... got the right bar');
	is($obj->baz, 100, '... got the right baz');
	is($obj->boo, 50,  '... got the right boo');

	is(
		exception {
			$class->new(bar => 10, baz => undef);
		},
		undef,
		'... undef is a valid attribute value'
	);

	is(
		exception {
			$class->new(bar => 10, boo => undef);
		},
		undef,
		'... undef is a valid attribute value'
	);

	like(
		exception {
			$class->new;
		},
		qr/^Attribute \(bar\) is required/,
		'... must supply all the required attribute'
	);
}

sub test_trigger_and_coerce {
	my ($self)   = @_;
	my $dt_class = $self->_get_anon_package;
	my $class    = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Class' => $class, '#FakeDateTime' => $dt_class);
	package #FakeDateTime {
		use Moose;
		has 'string', is => 'ro';
		__PACKAGE__->meta->make_immutable;
	}

	package #Class {
		use #Moose;
		use Moose::Util::TypeConstraints;
		use Test::More;

		coerce '#FakeDateTime',
			from 'Str',
			via { #FakeDateTime->new(string => $_) };

		has 'date',
			is => 'rw',
			isa => '#FakeDateTime',
			coerce => 1,
			trigger => sub {
				my ($self, $val) = @_;
				pass 'trigger called';
				isa_ok $self->date, '#FakeDateTime';
				isa_ok $val,        '#FakeDateTime';
			};

		__PACKAGE__->meta->make_immutable;
	}
END

	my $obj = $class->new(date => 'today');
	isa_ok $obj->date, $dt_class;
	is $obj->date->string, 'today';
}

sub test_triggers {
	my ($self) = @_;

	my $foo_class = $self->_get_anon_package;
	my $bar_class = $self->_get_anon_package;
	my $baz_class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Foo' => $foo_class, '#Bar' => $bar_class, '#Baz' => $baz_class);
	package #Foo {
		use #Moose;

		has 'bar',
			is      => 'rw',
			isa     => 'Maybe[#Bar]',
			trigger => sub {
				my ($self, $bar) = @_;
				$bar->foo($self) if defined $bar;
			};

		has 'baz',
			writer  => 'set_baz',
			reader  => 'get_baz',
			isa     => '#Baz',
			trigger => sub {
				my ($self, $baz) = @_;
				$baz->foo($self);
			};

		__PACKAGE__->meta->make_immutable;
	}

	package #Bar {
		use #Moose;

		has 'foo', is => 'rw', isa => '#Foo', weak_ref => 1;

		__PACKAGE__->meta->make_immutable;
	}

	package #Baz {
		use #Moose;

		has 'foo', is => 'rw', isa => '#Foo', weak_ref => 1;

		__PACKAGE__->meta->make_immutable;
	}
END
	my $bar_mi = $bar_class->meta->get_meta_instance;
	my $baz_mi = $baz_class->meta->get_meta_instance;

	{
		my $foo = $foo_class->new;
		my $bar = $bar_class->new;
		my $baz = $baz_class->new;

		$foo->bar($bar);
		is $foo->bar, $bar, 'set the value foo.bar correctly';
		is $bar->foo, $foo, 'which in turn set the value bar.foo correctly';

		ok $bar_mi->slot_value_is_weak($bar, 'foo'), 'bar.foo is a weak reference';

		$foo->bar(undef);
		is $foo->bar, undef, 'set the value foo.bar correctly';
		is $bar->foo, $foo, 'which in turn set the value bar.foo correctly';

		# test the writer
		$foo->set_baz($baz);
		is $foo->get_baz, $baz, 'set the value foo.baz correctly';
		is $baz->foo,     $foo, 'which in turn set the value baz.foo correctly';

		ok $baz_mi->slot_value_is_weak($baz, 'foo'), 'baz.foo is a weak reference';
	}

	{
		my $bar = $bar_class->new;
		my $baz = $baz_class->new;
		my $foo = $foo_class->new(bar => $bar, baz => $baz);

		is $foo->bar, $bar, 'set the value foo.bar correctly';
		is $bar->foo, $foo, 'which in turn set the value bar.foo correctly';

		ok $bar_mi->slot_value_is_weak($bar, 'foo'), 'bar.foo is a weak reference';

		is $foo->get_baz, $baz, 'set the value foo.baz correctly';
		is $baz->foo,     $foo, 'which in turn set the value baz.foo correctly';

		ok $baz_mi->slot_value_is_weak($baz, 'foo'), 'baz.foo is a weak reference';
	}

	# Triggers do not fire on built values
	my $blarg_class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Blarg' => $blarg_class);
	package #Blarg {
		use #Moose;

		our %trigger_calls;
		our %trigger_vals;

		has 'foo',
			is      => 'rw',
			default => sub { 'default foo value' },
			trigger => sub {
				my ($self, $val, $attr) = @_;
				$trigger_calls{foo}++;
				$trigger_vals{foo} = $val;
			};

		has 'bar',
			is         => 'rw',
			lazy_build => 1,
			trigger    => sub {
				my ($self, $val, $attr) = @_;
				$trigger_calls{bar}++;
				$trigger_vals{bar} = $val;
			};

		has 'baz',
			is      => 'rw',
			builder => '_build_baz',
			trigger => sub {
				my ($self, $val, $attr) = @_;
				$trigger_calls{baz}++;
				$trigger_vals{baz} = $val;
			};

		sub _build_bar { 'default bar value' }
		sub _build_baz { 'default baz value' }

		__PACKAGE__->meta->make_immutable;
	}
END

	my ($calls, $vals);
	{
		no strict 'refs';
		$calls = \%{ $blarg_class . '::trigger_calls' };
		$vals  = \%{ $blarg_class . '::trigger_vals' };
	}

	my $blarg = $blarg_class->new;
	foreach my $attr (qw(foo bar baz)) {
		is $blarg->$attr, "default $attr value", "$attr has default value";
	}
	is_deeply $calls, {}, 'No triggers fired';
	foreach my $attr (qw(foo bar baz)) {
		$blarg->$attr("Different $attr value");
	}
	is_deeply $calls, { map { $_ => 1 } qw(foo bar baz) }, 'All triggers fired once on assign';
	is_deeply $vals, { map { $_ => "Different $_ value" } qw(foo bar baz) },
		'All triggers given assigned values';

	$blarg = $blarg_class->new(map { $_ => "Yet another $_ value" } qw(foo bar baz));
	is_deeply $calls, { map { $_ => 2 } qw/foo bar baz/ }, 'All triggers fired once on construct';
	is_deeply $vals, { map { $_ => "Yet another $_ value" } qw/foo bar baz/ },
		'All triggers given assigned values';


	# Triggers do not receive the meta-attribute as an argument, but do
	# receive the old value

	my $boo_class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Boo' => $boo_class);
	package #Boo {
		use #Moose;
		our @calls;
		has 'foo', is => 'rw', trigger => sub { push @calls, [@_] };
		__PACKAGE__->meta->make_immutable;
	}
END

	{
		no strict 'refs';
		$calls = \@{ $boo_class . '::calls' };
	}

	my $attr = $boo_class->meta->get_attribute('foo');
	my $boo  = $boo_class->new;

	$attr->set_value($boo, 2);

	is_deeply $calls, [ [ $boo, 2 ] ], 'trigger called correctly on initial set via meta-API';
	shift @$calls;

	$attr->set_value($boo, 3);

	is_deeply $calls, [ [ $boo, 3, 2 ] ], 'trigger called correctly on second set via meta-API';
	shift @$calls;

	$attr->set_raw_value($boo, 4);

	is_deeply $calls, [], 'trigger not called using set_raw_value method';

	$boo = $boo_class->new(foo => 2);
	is_deeply $calls, [ [ $boo, 2 ] ], 'trigger called correctly on construction';
	shift @$calls;

	$boo->foo(3);
	is_deeply $calls, [ [ $boo, 3, 2 ] ], 'trigger called correctly on set (with old value)';
	shift @$calls;
}

sub test_writer_generation {
	my ($self) = @_;
	my $class = $self->_get_anon_package;
	$self->_eval_class(<<'END', '#Class' => $class);
	package #Class {
		use #Moose;

		has 'foo',
			reader => 'get_foo',
			writer => 'set_foo';

		has 'required',
			reader   => 'get_required',
			writer   => 'set_required',
			required => 1;

		has 'int',
			reader => 'get_int',
			writer => 'set_int',
			isa    => 'Int';

		has 'weak',
			reader    => 'get_weak',
			writer    => 'set_weak',
			weak_ref  => 1,
			predicate => 'has_weak';

		__PACKAGE__->meta->make_immutable;
	}
END

	my $foo = $class->new(required => 'required');
	my $mi = $class->meta->get_meta_instance;

	# regular writer
	is $foo->get_foo, undef, 'got an unset value';
	$foo->set_foo(100);
	is $foo->get_foo, 100, 'got the correct set value';
	ok !$mi->slot_value_is_weak($foo, 'foo'), 'it is not a weak reference';

	# required writer
	isa_ok exception { $class->new }, 'Moose::Exception::AttributeIsRequired',
		'cannot create without the required attribute';

	is $foo->get_required, 'required', 'got a value';
	$foo->set_required(100);
	is $foo->get_required, 100, 'got the correct set value';

	isa_ok exception { $foo->set_required }, 'Moose::Exception::AttributeIsRequired',
		'set_required died successfully with no value';

	is exception { $foo->set_required(undef) }, undef, '... set_foo_required did accept undef';

	ok !$mi->slot_value_is_weak($foo, 'required'), 'it is not a weak reference';

	# with type constraint
	is $foo->get_int, undef, 'got an unset value';
	$foo->set_int(100);
	is $foo->get_int, 100, 'got the correct set value';

	isa_ok exception { $foo->set_int("Foo") },
		'Moose::Exception::ValidationFailedForInlineTypeConstraint',
		'set_foo_int died successfully';

	ok !$mi->slot_value_is_weak($foo, 'int'), 'it is not a weak reference';

	# with weak_ref
	my $weak = [];
	ok !$foo->has_weak, 'weak is not set';
	is $foo->get_weak, undef, 'got an unset value';
	$foo->set_weak($weak);
	is $foo->get_weak, $weak, 'got the correct set value';
	ok $mi->slot_value_is_weak($foo, 'weak'), 'weak reference';

	undef $weak;
	ok $foo->has_weak, 'weak still set';
	is $foo->get_weak, undef, 'weak reference undefined';
}

1;
