#!/bin/sh
#
# Copyright (c) 2007 Johannes E. Schindelin
#

test_description='Test custom diff function name patterns'

. ./test-lib.sh

test_expect_success 'setup' '
	# a non-trivial custom pattern
	git config diff.custom1.funcname "!static
!String
[^ 	].*s.*" &&

	# a custom pattern which matches to end of line
	git config diff.custom2.funcname "......Beer\$" &&

	# alternation in pattern
	git config diff.custom3.funcname "Beer$" &&
	git config diff.custom3.xfuncname "^[ 	]*((public|static).*)$" &&

	# for regexp compilation tests
	echo A >A.java &&
	echo B >B.java
'

test_expect_success 'setup: test-tool userdiff' '
	# Make sure additions to builtin_drivers are sorted
	test_when_finished "rm builtin-drivers.sorted" &&
	test-tool userdiff list-builtin-drivers >builtin-drivers &&
	test_file_not_empty builtin-drivers &&
	sort <builtin-drivers >builtin-drivers.sorted &&
	test_cmp builtin-drivers.sorted builtin-drivers &&

	# Ditto, but "custom" requires the .git directory and config
	# to be setup and read.
	test_when_finished "rm custom-drivers.sorted" &&
	test-tool userdiff list-custom-drivers >custom-drivers &&
	test_file_not_empty custom-drivers &&
	sort <custom-drivers >custom-drivers.sorted &&
	test_cmp custom-drivers.sorted custom-drivers
'

diffpatterns="
	$(cat builtin-drivers)
	$(cat custom-drivers)
"

for p in $diffpatterns
do
	test_expect_success "builtin $p pattern compiles" '
		echo "*.java diff=$p" >.gitattributes &&
		test_expect_code 1 git diff --no-index \
			A.java B.java 2>msg &&
		test_i18ngrep ! fatal msg &&
		test_i18ngrep ! error msg
	'
	test_expect_success "builtin $p wordRegex pattern compiles" '
		echo "*.java diff=$p" >.gitattributes &&
		test_expect_code 1 git diff --no-index --word-diff \
			A.java B.java 2>msg &&
		test_i18ngrep ! fatal msg &&
		test_i18ngrep ! error msg
	'
done

test_expect_success 'last regexp must not be negated' '
	echo "*.java diff=java" >.gitattributes &&
	test_config diff.java.funcname "!static" &&
	test_expect_code 128 git diff --no-index A.java B.java 2>msg &&
	test_i18ngrep ": Last expression must not be negated:" msg
'

test_expect_success 'setup hunk header tests' '
	for i in $diffpatterns
	do
		echo "$i-* diff=$i"
	done > .gitattributes &&

	cp -R "$TEST_DIRECTORY"/t4018 . &&
	git init t4018 &&
	git -C t4018 add .
'

# check each individual file
for i in $(git -C t4018 ls-files)
do
	test_expect_success "setup hunk header: $i" "
		grep -v '^t4018' \"t4018/$i\" >\"t4018/$i.content\" &&
		sed -n -e 's/^t4018 header: //p' <\"t4018/$i\" >\"t4018/$i.header\" &&
		cp \"t4018/$i.content\" \"$i\" &&

		# add test file to the index
		git add \"$i\" &&
		# place modified file in the worktree
		sed -e 's/ChangeMe/IWasChanged/' <\"t4018/$i.content\" >\"$i\"
	"

	test_expect_success "hunk header: $i" "
		git diff -U1 $i >diff &&
		sed -n -e 's/^.*@@$//p' -e 's/^.*@@ //p' <diff >ctx &&
		test_cmp t4018/$i.header ctx
	"
done

test_done
