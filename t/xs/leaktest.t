
use common::sense;
use Moose::Util::TypeConstraints;
use Test::More;
use Test::Requires 'Test::LeakTrace';

{
	coerce 'Int' => from 'Str' => via { length $_ ? $_ : 69 };

	package Foo;
	use MooseX::XSor;
	has 'a', is => 'rw';
	has 'tc', is => 'rw', isa => 'Int';
	has 'default',
		is      => 'rw',
		isa     => 'Int',
		lazy    => 1,
		coerce  => 1,
		default => '';
	has 'builder',
		is      => 'rw',
		isa     => 'Int',
		lazy    => 1,
		coerce  => 1,
		builder => '_build_builder';

	sub _build_builder {''}

	__PACKAGE__->meta->make_immutable(debug => 0);
}

{

	package Bar;
	use MooseX::XSor;

	has 'default', is => 'rw', default => 1;
	has 'builder', is => 'rw', builder => '_build_builder';
	sub _build_builder {18}

	__PACKAGE__->meta->make_immutable(debug => 0);
}

{

	package Baz;
	use MooseX::XSor;

	has 'a', is => 'rw';

	sub BUILDARGS {
		shift;
		+{@_};
	}

	__PACKAGE__->meta->make_immutable(debug => 0);
}

no_leaks_ok {
	my $foo  = Foo->new;
	my $foo2 = $foo->new;
}
'calling new on a instance';

no_leaks_ok {
	my $foo = Foo->new(a => 18);
}
'inlined BUILDARGS - hash';

no_leaks_ok {
	my $foo = Foo->new({ a => 18 });
}
'inlined BUILDARGS - hashref';

no_leaks_ok {
	my $baz = Baz->new(a => 18);
}
'call to BUILDARGS';

no_leaks_ok {
	my $foo = Foo->new(tc => 18);
}
'type constraint';

no_leaks_ok {
	my $bar = Bar->new;
}
'default and builder in constructor';

no_leaks_ok {
	my $foo = Foo->new;
	$foo = $foo->default;
}
'lazy default w/ coercion';

no_leaks_ok {
	my $foo = Foo->new;
	$foo = $foo->default;
}
'lazy builder w/ coercion';

done_testing;
