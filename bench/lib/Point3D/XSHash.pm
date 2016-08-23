package Point3D::XSHash;

use MooseX::XSor;

has 'x', is => 'rw';
has 'y',
	is  => 'rw',
	isa => 'Int';
has 'x',
	is      => 'ro',
	isa     => 'Int',
	lazy    => 1,
	builder => '_build_x';

my $x;

sub _build_x {
	++$x;
}

__PACKAGE__->meta->make_immutable;
