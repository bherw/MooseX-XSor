package MooseX::XSor::XS::Meta::Method::InlineXS;

use Inline;
use Moose::Role;

my $anon_i;

has 'body_source',
	is      => 'ro',
	lazy    => 1,
	builder => '_build_body_source';

has '_xs_name',
	is      => 'ro',
	lazy    => 1,
	builder => '_build_xs_name';

sub _build_body {
	my ($self)  = @_;
	my $class   = ref($self);
	my $xs_name = $self->_xs_prefix . $self->_xs_name;

	#<<<
	my @source = (
		$self->_build_headers,

		# Inline::C makes XS functions which in turn call these.
		# XSMODE disables all the extra nonsense it adds, but then we have to
		# add a MODULE declaration to the code which includes the md5 Inline
		# gets by hashing the code... meaning XSMODE is completely useless
		# because it can't produce a correctly named boot function, and it dies
		# when Inline tries to load the .so

		# Possible solutions:
		# - Make a custom Inline ILSM that just passes through our code and
		#   adds the MODULE header
		# - Use XS::TCC for development since gcc will get used for immutable
		#   objects when installed anyways.

		# The boot compile option isn't included in the code that gets hashed
		# for uniqueness, so it has to go in its own function since it will
		# change.
		'void',
		"${xs_name}_boot() {",
			'dXSARGS;',
			'int count;',
			$self->_build_body_boot,
		'}',

		# This arglist is bogus and only here because of Inline::C derping around
		'void',
		"$xs_name(SV* foo, ...) {",
			'dXSARGS;',
			'int count;',
			@{ $self->body_source },
		'}'
	);
	#>>>

	if ($self->options->{debug}) {
		@source = _naively_indent(0, @source);
	}

	Inline->bind(C => join("\n", @source), $self->_compile_options);

	{
		no strict 'refs';
		return \&{ __PACKAGE__ . '::' . $self->_xs_name };
	}
}

sub _build_headers {
	my ($self) = @_;
	return (<<'END', $self->_build_body_headers);
	#define SvAROK(val) (SvROK(val) && SvTYPE(SvRV(val)) == SVt_PVAV)
	#define SvHROK(val) (SvROK(val) && SvTYPE(SvRV(val)) == SVt_PVHV)
	#define retST(offset) PL_stack_base[ax + items + (offset)]

	#ifndef sv_ref
	#define sv_ref(a,b,c) my_sv_ref(aTHX_ a,b,c)
	SV *
	my_sv_ref(pTHX_ SV *dst, const SV *const sv, const int ob)
	{
		PERL_ARGS_ASSERT_SV_REF;

		if (!dst)
			dst = sv_newmortal();

		const char * reftype = sv_reftype(sv, 1);
		sv_setpv(dst, reftype);

		return dst;
	}
	#endif
END
}

sub _build_body_boot    { }
sub _build_body_headers { }

sub _build_xs_name {
	my ($self) = @_;
	'__ANON__SERIAL__' . ++$anon_i . '__' . $_[0]->name;
}

sub _compile_options {
	my ($self) = @_;
	return (
		BOOT              => $self->_xs_prefix . $self->_xs_name . '_boot();',
		CLEAN_AFTER_BUILD => !$self->options->{debug},
		PREFIX            => $self->_xs_prefix,
	);
}

sub _xs_prefix {
	my ($self) = @_;
	(__PACKAGE__ =~ s{::}{__}gr) . '__';
}

override _initialize_body => sub {
	$_[0]->{body} = $_[0]->_build_body;
};

sub _naively_indent {
	my ($i, @code) = @_;
	$i //= 0;
	map {
		s/^\s+//;
		s/\s+$//;

		$i-- if $_ eq '}' or $_ eq ');';
		my $tmp = ("\t" x $i) . $_;
		$i++ if /[\{\(]$/;
		$tmp;
	} map { split /\n/, $_ } @code;
}
