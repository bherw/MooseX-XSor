package MooseX::XSor::Test::Requires;

use strict;
use warnings;
use Carp;
use Class::Load qw(load_optional_class);
use Sub::Attribute;

sub Requires : ATTR_SUB {
	my ($class, $symbol, undef, undef, $data, undef, $file, $line) = @_;

	if ($symbol eq 'ANON') {
		die "Cannot attach requirements to anonymous sub at $file, line $line";
	}

	my @modules;
	if ($data) {
		@modules = split /\s+/, $data =~ s{^\s+}{}gr;
	}

	my $method = *{$symbol}{NAME};
	if ($method =~ /^test_(?:startup|setup|teardown|shutdown)$/) {
		croak "Test control method '$method' may not have a Test attribute";
	}

	$class->meta->add_before_method_modifier(
		'test_setup',
		sub {
			my ($test) = @_;
			my $current_method = $test->test_report->current_method->name;
			return unless $current_method eq $method;

			for my $module (@modules) {
				load_optional_class $module
					or $test->test_skip("Test requires module '$module' but it's not found");
			}
		});
}

1;
