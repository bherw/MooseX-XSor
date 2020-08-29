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
	my $xs_name = $self->_xs_name;

	#<<<
	my @source = (
		$self->_build_headers,

		# Inline::C generates XS functions which in turn call these.
		# By manually using the XS macros we eliminate the extra functions.
		'// ' . $self->package_name . '::' . $self->name,
		"XS($xs_name) {",
			'dXSARGS;',
			'int count;',
			@{ $self->body_source },
		'}',

		# The boot compile option isn't included in the code that gets hashed
		# for uniqueness, so it has to go in its own function since it will
		# change. Adding PERL_STATIC_INLINE hides it from Inline::C.
		'PERL_STATIC_INLINE void',
		"${xs_name}_boot(pTHX) {",
			'dXSARGS;',
			'int count;',
			$self->_build_body_boot,
			qq{newXS("${class}::$xs_name", $xs_name, __FILE__);},
		'}',
	);
	#>>>

	if ($self->options->{debug} // $ENV{MOOSEX_XSOR_DEBUG}) {
		@source = _naively_indent(0, @source);
	}

	Inline->bind(C => join("\n", @source), $self->_compile_options);

	{
		no strict 'refs';
		return \&{ $class . '::' . $self->_xs_name };
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

my %names;
sub _build_xs_name {
	my ($self) = @_;
	my $name = $self->package_name . '__' . $_[0]->name;
	$name =~ s/:/_/g;
	$names{$name}++;
	$name .= '_' . $names{$name} if $names{$name} > 1;
	$name;
}

sub _compile_options {
	my ($self) = @_;
	return (
		BOOT              => $self->_xs_name . '_boot(aTHX);',
		CLEAN_AFTER_BUILD => !($self->options->{debug} // $ENV{MOOSEX_XSOR_DEBUG}),
		pre_head          => '#define PERL_NO_GET_CONTEXT',
	);
}

sub _initialize_body {
	$_[0]->{body} = $_[0]->_build_body;
}

sub _naively_indent {
	my ($i, @code) = @_;
	$i //= 0;
	map {
		s/^\s+//;
		s/\s+$//;

		$i-- if $_ =~ /^}/ or $_ eq ');';
		my $tmp = ("\t" x $i) . $_;
		$i++ if /[\{\(]$/;
		$tmp;
	} map { split /\n/, $_ } @code;
}

1;
