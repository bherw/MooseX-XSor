package MooseX::XSor;

use strict;
use warnings;
use Module::Implementation;

Module::Implementation::build_loader_sub(
	implementations => [ 'XS', 'PP' ],
	symbols         => [qw(import unimport init_meta)],
)->();


1;

=head1 TODO

Instance::Struct: An instance using a RV to an IV pointer to a Struct
Instance::MagicStruct: An instance that attaches a struct to a blessed object with magic (non-Moose compat)
XS inlining for type constraints
XS versions of the Native accessor traits
Instance implementations using native numbers to complement the native accessors
PP noop fallback so we can be required on systems with no C compiler
test unicode classnames(?) and slot names

=cut
