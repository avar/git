#!/bin/sh
#
# See ../t4018-diff-funcname.sh's test_diff_funcname()
#

test_diff_funcname 'perl: skip end of heredoc' \
	8<<\EOF_HUNK 9<<\EOF_TEST
sub withheredocument {
EOF_HUNK
sub withheredocument {
	print <<"EOF"
decoy here-doc
EOF
	# some lines of context
	# to pad it out
	print "ChangeMe\n";
}
EOF_TEST

test_diff_funcname 'perl: skip forward decl' \
	8<<\EOF_HUNK 9<<\EOF_TEST
package Some::Package;
EOF_HUNK
package Some::Package;

use strict;
use warnings;
use parent qw(Exporter);
our @EXPORT_OK = qw(round finalround);

sub other; # forward declaration

# ChangeMe
EOF_TEST

test_diff_funcname 'perl: skip sub in pod' \
	8<<\EOF_HUNK 9<<\EOF_TEST
=head1 SYNOPSIS
EOF_HUNK
=head1 NAME

Beer - subroutine to output fragment of a drinking song

=head1 SYNOPSIS

	use Beer qw(round finalround);

	sub song {
		for (my $i = 99; $i > 0; $i--) {
			round $i;
		}
		finalround;
	}

	ChangeMe;

=cut
EOF_TEST

test_diff_funcname 'perl: sub definition' \
	8<<\EOF_HUNK 9<<\EOF_TEST
sub asub {
EOF_HUNK
sub asub {
	my ($n) = @_;
	print "ChangeMe";
}
EOF_TEST

test_diff_funcname 'perl: sub definition kr brace' \
	8<<\EOF_HUNK 9<<\EOF_TEST
sub asub
EOF_HUNK
sub asub
{
	print "ChangeMe\n";
}
EOF_TEST
