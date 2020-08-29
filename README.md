# MooseX::XSor

A Moose extension producing fast XS accessors (and constructors)

## Usage

Precompilation is not yet supported, but dynamic generation works. Simply replace `use Moose` imports with `use MooseX::XSor` and use `__PACKAGE__->meta->make_immutable;` to get the C methods

## Why?!

Moose is notoriously slow to start. It needs to initialize all of the Class::MOP meta-object protocol, then use the MOP to construct itself, then any extensions, and finally it's ready to start compiling and installing generated Perl methods for your classes. This is fine for long-running processes, but painful for CLI apps like Dist::Zilla.

One way to fix this is to introspect your Moose classes when your library/application gets installed, generate the methods then, and at runtime load the precompiled methods. [MooseX::Compile](https://metacpan.org/pod/MooseX::Compile) was one attempt to do this.

The goal of MooseX::XSor is to, rather than precompile Perl, instead precompile a Perl XS C extension and load that at runtime, transparently falling back to real Moose in the unusual event that it is needed. MooseX::XSor can also leverage Inline::C to dynamically generate, compile, and load the generated C methods, allowing it to be used in development as well as at compile time.

This approach has a number of advantages:

- compiling Perl is difficult and not common like compiling python bytecode
- XS modules with runtime pure-perl fallbacks are a common pattern
- XS accessors are roughly 2-3 times as fast as pure-perl accessors
- an XS instance is not limited to HashRef-based instances, but can inherit from any Ref-based class using Perl magic

## Status

- hash-based instances: complete
- all built-in Moose attribute features are supported
- all relevant Moose tests passed (though the test harness is currently not working #2)
- full compatibility with Moose and other HashRef-based OO modules achieved
- struct-based instances: in-progress (#1)
- module build plugin for precompilation: pending (#13)

## Implementation

Much of the XS generation mirrors the perl-generation methods in Moose's Meta(Class|Instance|Accessor) class. Inline::C is used to dynamically compile and load the generated C.
