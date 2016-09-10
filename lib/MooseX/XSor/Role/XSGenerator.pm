package MooseX::XSor::Role::XSGenerator;

use Moose::Role;
use MooseX::XSor::Util qw(quotecmeta);

# XXX: This may as well be Util::XSGeneration

sub _xs_boot    { wantarray ? () : '' }
sub _xs_headers { wantarray ? () : '' }

sub _xs_call {
	my ($self, $type, $what, $args, $expect) = @_;
	my ($flags, @count_check);
	my $call_what  = ref $what ? '"' . $$what . '"' : $what;
	my $error_what = ref $what ? $$what             : $what;
	my @args
		= map { ref $_ ? 'sv_2mortal(newSVpv("' . quotecmeta($$_) . '", ' . length($$_) . '))' : $_ }
		@$args;

	if ($expect eq 'discard') {
		$flags = 'G_DISCARD|G_VOID';
	}
	elsif ($expect eq 'zero_or_one') {
		$flags = 'G_SCALAR';
	}
	elsif ($expect eq 'one') {
		$flags = 'G_SCALAR';
		@count_check
			= qq{if (count != 1) croak("Expected $error_what to return 1 value, got none.");};
	}
	elsif ($expect eq 'array') {
		$flags = 'G_ARRAY';
	}
	else {
		die "Unknown expect type: $expect";
	}

	my @code;
	if (@args) {
		#<<<
		push @code, (
			'PUSHMARK(SP);',
			'EXTEND(SP, ' . scalar(@args) . ');',
			(map {"PUSHs($_);"} @args),
			'PUTBACK;',
			);
		#>>>
	}
	else {
		$flags .= '|G_NOARGS';
	}

	#<<<
	push @code,
		(
		($expect eq 'discard' ? '' : 'count = ')
		. qq{call_$type($call_what, $flags);},
		@count_check,
		'SPAGAIN;'
		);
	#>>>

	return @code;
}

sub _xs_call_method {
	my ($self, $obj, $method, $args, $expect) = @_;
	return $self->_xs_call('method', $method, [ $obj, @$args ], $expect);
}

sub _xs_throw_moose_exception {
	my ($self, $type, %args) = @_;
	my @args;
	for (keys %args) {
		push @args, \$_, $args{$_};
	}

	return (
		$self->_xs_call(
			'pv',
			\'Module::Runtime::use_module',
			[ \"Moose::Exception::$type" ], 'discard'
		),
		$self->_xs_call_method(\"Moose::Exception::$type", \'new', \@args, 'one'),
		'croak_sv(POPs);',
	);
}

1;
