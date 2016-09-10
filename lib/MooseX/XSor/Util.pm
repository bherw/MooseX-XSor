package MooseX::XSor::Util;

use strict;
use warnings;
use Sub::Exporter::Progressive -setup => { exports => [qw(quotecmeta G_DISCARD)], };

sub G_DISCARD() {4}

sub quotecmeta(;$) {
	(@_ ? $_[0] : $_) =~ s{([\\"])}{\\$1}gr;
}

1;
