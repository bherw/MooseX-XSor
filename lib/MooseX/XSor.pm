package MooseX::XSor;

use strict;
use warnings;
use Module::Implementation;

Module::Implementation::build_loader_sub(
	implementations => [ 'XS', 'PP' ],
	symbols         => [qw(import unimport init_meta)],
)->();

1;
