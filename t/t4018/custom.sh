#!/bin/sh
#
# See ../t4018-diff-funcname.sh's test_diff_funcname()
#

test_expect_success 'custom: setup non-trivial custom' '
	git config diff.custom.funcname "!static
!String
[^ 	].*s.*"
'

test_diff_funcname 'custom: non-trivial custom pattern' \
	8<<\EOF_HUNK 9<<\EOF_TEST
int special, RIGHT;
EOF_HUNK
public class Beer
{
	int special, RIGHT;
	public static void main(String args[])
	{
		String s=" ";
		for(int x = 99; x > 0; x--)
		{
			System.out.print(x + " bottles of beer on the wall "
				+ x + " bottles of beer\n" // ChangeMe
				+ "Take one down, pass it around, " + (x - 1)
				+ " bottles of beer on the wall.\n");
		}
		System.out.print("Go to the store, buy some more,\n"
			+ "99 bottles of beer on the wall.\n");
	}
}
EOF_TEST

test_expect_success 'custom: setup match to end of line' '
	git config diff.custom.funcname "Beer\$"
'

test_diff_funcname 'custom: match to end of line' \
	8<<\EOF_HUNK 9<<\EOF_TEST
Beer
EOF_HUNK
public class Beer
{
	int special;
	public static void main(String args[])
	{
		System.out.print("ChangeMe");
	}
}
EOF_TEST

test_expect_success 'custom: setup alternation in pattern' '
	git config diff.custom.funcname "Beer$" &&
	git config diff.custom.xfuncname "^[ 	]*((public|static).*)$"
'

test_diff_funcname 'custom: alternation in pattern' \
	8<<\EOF_HUNK 9<<\EOF_TEST
public static void main(String RIGHT[])
EOF_HUNK
public class Beer
{
	int special;
	public static void main(String RIGHT[])
	{
		String s=" ";
		for(int x = 99; x > 0; x--)
		{
			System.out.print(x + " bottles of beer on the wall "
				+ x + " bottles of beer\n" // ChangeMe
				+ "Take one down, pass it around, " + (x - 1)
				+ " bottles of beer on the wall.\n");
		}
		System.out.print("Go to the store, buy some more,\n"
			+ "99 bottles of beer on the wall.\n");
	}
}
EOF_TEST

test_expect_success 'custom: setup config precedence' '
	git config diff.custom.funcname "foo" &&
	git config diff.custom.xfuncname "bar"
'

test_diff_funcname 'custom: config precedence' \
	8<<\EOF_HUNK 9<<\EOF_TEST
bar
EOF_HUNK
foo
bar

ChangeMe

baz
EOF_TEST

test_expect_success 'custom: setup config precedence' '
	git config diff.custom.xfuncname "bar" &&
	git config diff.custom.funcname "foo"
'

test_diff_funcname 'custom: config precedence' \
	8<<\EOF_HUNK 9<<\EOF_TEST
foo
EOF_HUNK
foo
bar

ChangeMe

baz
EOF_TEST

test_expect_success 'custom: setup negation syntax, ! is magic' '
	git config diff.custom.xfuncname "!negation
line"
'

test_diff_funcname 'custom: negation syntax, ! is magic' \
	8<<\EOF_HUNK 9<<\EOF_TEST
line
EOF_HUNK
line
!negation

ChangeMe

baz
EOF_TEST

test_expect_success 'custom: setup negation syntax, use [!] to override ! magic' '
	git config diff.custom.xfuncname "[!]negation
line"
'

test_diff_funcname 'custom: negation syntax, use [!] to override ! magic' \
	8<<\EOF_HUNK 9<<\EOF_TEST
!negation
EOF_HUNK
line
!negation

ChangeMe

baz
EOF_TEST

test_expect_success 'custom: setup captures in multiple patterns' '
	git config diff.custom.xfuncname "!^=head
^format ([^ ]+)
^sub ([^;]+)"
'

test_diff_funcname 'custom: captures in multiple patterns' \
	8<<\EOF_HUNK 9<<\EOF_TEST
foo
EOF_HUNK
sub foo;

=head1

ChangeMe

EOF_TEST

test_expect_success 'custom: multiple patterns ending with \n' '
	git config diff.custom.xfuncname "!^=head
^sub ([^;]+)
"
'

test_diff_funcname 'custom: multiple patterns ending with \n' \
	8<<\EOF_HUNK 9<<\EOF_TEST

EOF_HUNK
sub foo;

=head1

ChangeMe

EOF_TEST
