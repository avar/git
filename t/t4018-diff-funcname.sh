#!/bin/sh
#
# Copyright (c) 2007 Johannes E. Schindelin
#

test_description='Test custom diff function name patterns'

. ./test-lib.sh

test_expect_success 'setup' '
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
	test_cmp builtin-drivers.sorted builtin-drivers
'

test_expect_success 'test-tool userdiff: custom patterns' '
	# a non-trivial custom pattern
	test_config diff.custom1.funcname "!static
!String
[^     ].*s.*" &&

	# Ditto, but "custom" requires the .git directory and config
	# to be setup and read.
	test_when_finished "rm custom-drivers.sorted" &&
	test-tool userdiff list-custom-drivers >custom-drivers &&
	test_file_not_empty custom-drivers &&
	sort <custom-drivers >custom-drivers.sorted &&
	test_cmp custom-drivers.sorted custom-drivers
'

test_expect_success 'list drivers without tests' '
	# Do not add anything to this list. New built-in drivers should have
	# tests
	cat >drivers-no-tests <<-\EOF
	bibtex
	csharp
	html
	objc
	pascal
	tex
	EOF
'

for p in $(cat builtin-drivers)
do
	P=$(echo $p | tr 'a-z' 'A-Z')
	if grep -q $p drivers-no-tests
	then
		test_set_prereq NO_TEST_FOR_DRIVER_$P
	fi
	test_expect_success NO_TEST_FOR_DRIVER_$P "builtin $p pattern compiles" '
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
	for i in $(cat builtin-drivers)
	do
		echo "$i* diff=$i"
	done > .gitattributes &&

	cp -R "$TEST_DIRECTORY"/t4018 . &&
	git init t4018 &&
	git -C t4018 add .
'

do_change_me () {
	file=$1
	sed -e "s/ChangeMe/IWasChanged/" <"$file" >tmp &&
	mv tmp "$file"
}

last_diff_context_line () {
	file=$1
	sed -n -e "s/^.*@@$//p" -e "s/^.*@@ //p" <$file
}

# check each individual file
for i in $(git -C t4018 ls-files -- ':!*.sh')
do
	test_expect_success "setup hunk header: $i" "
		grep -v '^t4018' \"t4018/$i\" >\"t4018/$i.content\" &&
		sed -n -e 's/^t4018 header: //p' <\"t4018/$i\" >\"t4018/$i.header\" &&
		cp \"t4018/$i.content\" \"$i\" &&

		# add test file to the index
		git add \"$i\" &&
		do_change_me \"$i\"
	"

	test_expect_success "hunk header: $i" "
		git diff -U0 $i >diff &&
		last_diff_context_line diff >ctx &&
		test_cmp t4018/$i.header ctx
	"
done

test_diff_funcname () {
	desc=$1
	diff_opts=${2:--U0} &&
	cat <&8 >arg.header &&
	cat <&9 >arg.test &&
	what=$(cat arg.what) &&

	test_expect_success "setup: $desc" '
		cp arg.test "$what" &&
		cp arg.header expected &&
		git add "$what" &&
		do_change_me "$what"
	'

	test_expect_success "$desc" '
		git diff $diff_opts "$what" >diff &&
		last_diff_context_line diff >actual &&
		test_cmp expected actual
	'

	test_expect_success "$desc -U9001" '
		git diff -U9001 "$what" >diff &&
		last_diff_context_line diff >actual &&
		echo >blank &&
		test_cmp blank actual
	'

	test_expect_success "teardown: $desc" '
		# In case any custom config was set immediately before
		# the test itself in the test file
		test_unconfig "diff.$what.funcname" &&
		test_unconfig "diff.$what.xfuncname"
	'
}

>drivers-had-no-tests
for what in $(cat builtin-drivers) custom
do
	test="$TEST_DIRECTORY/t4018/$what.sh"
	if ! test -e "$test"
	then
		git -C t4018 ls-files ':!*.sh' "$what*" >other-tests &&
		if ! test -s other-tests
		then
			echo $what >>drivers-had-no-tests
		fi
		continue
	fi &&

	test_expect_success "setup: hunk header for $what" '
		echo "$what diff=$what" >.gitattributes &&
		echo "$what" >arg.what
	'

	. "$test"
done

test_expect_success 'we should not have new built-in drivers without tests' '
	test_cmp drivers-no-tests drivers-had-no-tests
'

test_done
