package MooseX::XSor::Util;

use strict;
use warnings;
use Sub::Exporter::Progressive -setup => { exports => [qw(escesc G_DISCARD)], };

sub G_DISCARD() {4}

sub escesc(;$) {
	(@_ ? $_[0] : $_) =~ s{\\}{\\\\}gr;
}

1;
