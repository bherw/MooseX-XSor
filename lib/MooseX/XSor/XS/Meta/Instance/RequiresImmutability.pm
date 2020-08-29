package MooseX::XSor::XS::Meta::Instance::RequiresImmutability;

use Moose::Role;

sub requires_immutability {1}

1;

=head2 C<requires_immutability>

A boolean indicating whether the metainstance is able to operate while its
metaclass is mutable. By default it is true, but subclasses can override this.
If true, calling one of the methods that generate XS while not in the process
of inlining will throw an error.

The default metainstances selected by L<MooseX::XSor> both require immutablity,
while the hashref based instance does not. Extensions that generate inline XS
should do their inlining along with the standard Moose inlined methods during
C<make_immutable>.
