use v5.14;
use FindBin;
use lib "$FindBin::RealBin/lib";
use lib "$FindBin::RealBin/../lib";
use Benchmark qw(cmpthese);
use Class::Load 'load_class';

my @impls = qw(PP XSHash);
load_class "Point3D::$_" for @impls;

say "A plain var";
say "===========";
cmpthese(-1, {
	map {
		my $class = "Point3D::$_";
		($class => sub { my $p = $class->new(x => 1) })
	} @impls
});
say;

say "A Int var";
say '=========';
cmpthese(-1, {
	map {
		my $class = "Point3D::$_";
		($class => sub { my $p = $class->new(y => 2) })
	} @impls
});
say;

say "Passing a hashref";
say "=================";
cmpthese(-1, {
	map {
		my $class = "Point3D::$_";
		($class => sub { my $p = $class->new({x => 1}) })
	} @impls
});
say;