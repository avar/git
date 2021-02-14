#!/bin/sh
#
# See ../t4018-diff-funcname.sh's test_diff_funcname()
#

test_diff_funcname 'custom2: match to end of line' \
	8<<\EOF_HUNK 9<<\EOF_TEST
RIGHT_Beer
EOF_HUNK
public class RIGHT_Beer
{
	int special;
	public static void main(String args[])
	{
		System.out.print("ChangeMe");
	}
}
EOF_TEST
