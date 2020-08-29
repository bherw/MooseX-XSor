#!/usr/bin/env perl

package MooseImmutable {
	use Moose;
	has foo => (is => 'rw');
	has bar =>
		(reader => 'get_bar', writer => 'set_bar', predicate => 'has_bar', clearer => 'clear_bar');
	__PACKAGE__->meta->make_immutable(inline_destructor => 1);
}

package ClassAccessorFast {
	use warnings;
	use strict;
	use base 'Class::Accessor::Fast::XS';
	__PACKAGE__->mk_accessors(qw(foo bar));
}

package ClassXSAccessor {
	use warnings;
	use strict;
	use Class::XSAccessor
		constructor       => 'new',
		accessors         => ['foo'],
		getters           => { get_bar => 'bar' },
		setters           => { set_bar => 'bar' },
		exists_predicates => { has_bar => 'bar' };
}

package XSor::Hash {
	use MooseX::XSor::XS;
	has foo => (is => 'rw');
	has bar =>
		(reader => 'get_bar', writer => 'set_bar', predicate => 'has_bar', clearer => 'clear_bar');
	__PACKAGE__->meta->make_immutable;
}

package XSor::Struct {
	#use MooseX::XSor::XS::Struct;
	use Moose;
	has foo => (is => 'rw');
	has bar =>
		(reader => 'get_bar', writer => 'set_bar', predicate => 'has_bar', clearer => 'clear_bar');
	__PACKAGE__->meta->make_immutable;
}

use strict;
use warnings;
use Benchmark qw(cmpthese);
use Benchmark ':hireswallclock';

my $moose_immut = MooseImmutable->new;
my $caf         = ClassAccessorFast->new;
my $xs_acc      = ClassXSAccessor->new;
my $xsor_hash   = XSor::Hash->new;
my $xsor_struct = XSor::Struct->new;
my $unencap     = bless {}, 'Unencapsulated';

my $acc_rounds = 5_000_000 * 3;
my $ins_rounds = 1_000_000 * 3;

print "\nSETTING\n";
cmpthese(
	$acc_rounds,
	{
		MooseImmutable    => sub { $moose_immut->foo(23); () },
		ClassAccessorFast => sub { $caf->foo(23); () },
		ClassXSAccessor   => sub { $xs_acc->foo(23); () },
		XSorHash          => sub { $xsor_hash->foo(23); () },
		XSorStruct        => sub { $xsor_struct->foo(23); () },
		Unencapsulated    => sub { $unencap->{bar} = 23; () },
	},
	'noc'
);

print "\nGETTING\n";
cmpthese(
	$acc_rounds,
	{
		MooseImmutable    => sub { my $foo = $moose_immut->foo },
		ClassAccessorFast => sub { my $foo = $caf->foo },
		ClassXSAccessor   => sub { my $foo = $xs_acc->foo },
		XSorHash          => sub { my $foo = $xsor_hash->foo },
		XSorStruct        => sub { my $foo = $xsor_struct->foo },
		Unencapsulated    => sub { my $bar = $unencap->{bar} },
	},
	'noc'
);

print "\nPREDICATES\n";
cmpthese(
	$acc_rounds,
	{
		MooseImmutable    => sub { my $bar = $moose_immut->has_bar },
		ClassAccessorFast => sub { my $bar = defined $caf->bar },
		ClassXSAccessor   => sub { my $bar = $xs_acc->has_bar },
		XSorHash          => sub { my $bar = $xsor_hash->has_bar },
		XSorStruct        => sub { my $bar = $xsor_struct->has_bar },
		Unencapsulated    => sub { my $bar = exists $unencap->{bar} },
	},
	'noc'
);
print "\nCLEARERS\n";
cmpthese(
	$acc_rounds,
	{
		MooseImmutable    => sub { my $bar = $moose_immut->clear_bar },
		ClassAccessorFast => sub { my $bar = $caf->bar; $caf->bar(undef); },
		ClassXSAccessor   => sub { my $bar = $xs_acc->get_bar; $xs_acc->set_bar(undef); },
		XSorHash          => sub { my $bar = $xsor_hash->clear_bar },
		XSorStruct        => sub { my $bar = $xsor_struct->clear_bar },
		Unencapsulated    => sub { my $bar = delete $unencap->{bar} },
	},
	'noc'
);

my (@moose_immut, @caf_stall, @xs_acc, @xsor_hash, @xsor_struct, @unencap);
print "\nCREATION\n";
cmpthese(
	$ins_rounds,
	{
		MooseImmutable    => sub { push @moose_immut, MooseImmutable->new(foo => 23) },
		ClassAccessorFast => sub { push @caf_stall,   ClassAccessorFast->new({ foo => 23 }) },
		ClassXSAccessor   => sub { push @xs_acc,      ClassXSAccessor->new(foo => 23) },
		XSorHash          => sub { push @xsor_hash,   XSor::Hash->new(foo => 23) },
		XSorStruct        => sub { push @xsor_struct, XSor::Struct->new(foo => 23) },
		Unencapsulated    => sub { push @unencap,     bless { foo => 23 }, 'Unencapsulated' },
	},
	'noc'
);

my ($moose_immut_i, $caf_i, $xs_acc_i, $xsor_hash_i, $xsor_struct_i, $unencap_i)
	= (0, 0, 0, 0, 0, 0);
print "\nDESTRUCTION\n";
cmpthese(
	$ins_rounds,
	{
		MooseImmutable => sub {
			$moose_immut[ $moose_immut_i++ ] = undef;
		},
		ClassAccessorFast => sub {
			$caf_stall[ $caf_i++ ] = undef;
		},
		ClassXSAccessor => sub {
			$xs_acc[ $xs_acc_i++ ] = undef;
		},
		XSorHash => sub {
			$xsor_hash[ $xsor_hash_i++ ] = undef;
		},
		XSorStruct => sub {
			$xsor_struct[ $xsor_struct_i++ ] = undef;
		},
		Unencapsulated => sub {
			$unencap[ $unencap_i++ ] = undef;
		},
	},
	'noc'
);
