#!/bin/sh

test_description='stess the various output test-lib.sh can emit'
. ./test-lib.sh
. "$TEST_DIRECTORY"/lib-subtest.sh

# BEGIN EXTRACTED TESTS

# We can't use a prereq here so we won't fail with
# GIT_TEST_FAIL_PREREQS=true
if test -z "$TEST_LIB_OUTPUT_DEMO"
then
	say "Set TEST_LIB_OUTPUT_DEMO=true to see a test-lib.sh output demo"
else
	TEST_LIB_OUTPUT_DEMO_OK=success
	TEST_LIB_OUTPUT_DEMO_NOK=failure
fi
test_expect_success 'successful one-line test' 'true'
test_expect_success 'successful two-line test' '
	true &&
	# No newline, attempt to damage test output under -v. See
	# 57e1538ac9b (test-lib: output a newline before "ok" under a TAP
	# harness, 2010-06-24)
	printf "hello"
'

test_expect_${TEST_LIB_OUTPUT_DEMO_NOK:-success} 'unexpectedly passing TODO test' '
	echo A >expected &&

	# Emit to stdout while we are at it.
	grep A expected
'

test_expect_failure 'failing TODO test' '
	echo B >actual &&
	git diff --no-index --quiet expected actual
'

GIT_SKIP_TESTS="$GIT_SKIP_TESTS t0150.5"
test_expect_success 'we will be skipping this test' '
	echo skip &&
	echo this
'

test_expect_${TEST_LIB_OUTPUT_DEMO_OK:-failure} 'an one-line fail (set TEST_LIB_OUTPUT_DEMO=true)' 'false'

test_expect_${TEST_LIB_OUTPUT_DEMO_OK:-failure} 'a multi-line failure (set TEST_LIB_OUTPUT_DEMO=true)' '
	test_when_finished "rm out" &&
	# will not be empty!
	echo >out &&
	test_must_be_empty out
'

# END EXTRACTED TESTS

if test "$TEST_LIB_OUTPUT_DEMO" = "success"
then
	skip_rest="not running t0150-fake.sh under TEST_LIB_OUTPUT_DEMO="
fi

test_expect_success 'setup t0150-fake.sh' '
	# This is the tests in these files between the above #
	# "BEGIN/END EXTRACTED TESTS" tokens

	# Prefix for that code (run_sub_test_lib_test_err adds some of
	# its own)
	cat >my.sh <<-\EOF &&
	# Will cause failures!
	TEST_LIB_OUTPUT_DEMO=success
	EOF

	sed -n "/^# BEGIN EXTRACTED TESTS/,/^# END EXTRACTED TESTS/p" \
		<"$TEST_DIRECTORY"/t0150-test-lib-output-demo.sh >>my.sh &&

	# Suffix
	cat >>my.sh <<-\EOF &&
	test_done
	EOF

	write_sub_test_lib_test t0150-fake <my.sh
'

test_expect_success 'run t0150-fake.sh' '
	run_sub_test_lib_test_err t0150-fake --color &&

	check_sub_test_lib_test t0150-fake <<-\EOF
	> ok 1 - successful one-line test
	> ok 2 - successful two-line test
	> <YELLOW;BOLD>ok 3 - unexpectedly passing TODO test # TODO known breakage vanished<RESET>
	> not ok 4 - failing TODO test <YELLOW;BOLD># TODO known breakage<RESET>
	> <BLUE>ok 5 # SKIP we will be skipping this test (GIT_SKIP_TESTS)<RESET>
	> <RED;BOLD>not ok 6 - an one-line fail (set TEST_LIB_OUTPUT_DEMO=true)<RESET>
	> <RED>#false<RESET>
	> <RED;BOLD>not ok 7 - a multi-line failure (set TEST_LIB_OUTPUT_DEMO=true)<RESET>
	> <RED>#<RESET>
	> <RED>#	test_when_finished "rm out" &&<RESET>
	> <RED>#	# will not be empty!<RESET>
	> <RED>#	echo >out &&<RESET>
	> <RED>#	test_must_be_empty out<RESET>
	> <RED>#<RESET>
	> <BLUE># 1 test(s) skipped<RESET>
	> <YELLOW># 1 known breakage(s) vanished; please update test(s)<RESET>
	> <GREEN># still have 1 known breakage(s)<RESET>
	> <RED;BOLD># failed 2 among remaining 5 test(s)<RESET>
	> <CYAN>1..7<RESET>
	EOF
'

test_expect_success 'run t0150-fake.sh --verbose' '
	run_sub_test_lib_test_err t0150-fake --verbose &&

	check_sub_test_lib_test t0150-fake <<-\EOF
	> ok 1 - successful one-line test
	> ###true
	> Z
	> hellook 2 - successful two-line test
	> ###
	> ###	true &&
	> ###	# No newline, attempt to damage test output under -v. See
	> ###	# 57e1538ac9b (test-lib: output a newline before "ok" under a TAP
	> ###	# harness, 2010-06-24)
	> ###	printf "hello"
	> ###
	> Z
	> A
	> ok 3 - unexpectedly passing TODO test # TODO known breakage vanished
	> ##
	> ##	echo A >expected &&
	> ##
	> ##	# Emit to stdout while we are at it.
	> ##	grep A expected
	> ##
	> Z
	> not ok 4 - failing TODO test # TODO known breakage
	> ###
	> ###	echo B >actual &&
	> ###	git diff --no-index --quiet expected actual
	> ###
	> Z
	> ok 5 # SKIP we will be skipping this test (GIT_SKIP_TESTS)
	> ###
	> ###	echo skip &&
	> ###	echo this
	> ###
	> Z
	> not ok 6 - an one-line fail (set TEST_LIB_OUTPUT_DEMO=true)
	> #false
	> Z
	> '"'"'out'"'"' is not empty, it contains:
	> Z
	> not ok 7 - a multi-line failure (set TEST_LIB_OUTPUT_DEMO=true)
	> #
	> #	test_when_finished "rm out" &&
	> #	# will not be empty!
	> #	echo >out &&
	> #	test_must_be_empty out
	> #
	> Z
	> # 1 test(s) skipped
	> # 1 known breakage(s) vanished; please update test(s)
	> # still have 1 known breakage(s)
	> # failed 2 among remaining 5 test(s)
	> 1..7
	EOF
'

test_expect_success 'run t0150-fake.sh --verbose -color' '
	run_sub_test_lib_test_err t0150-fake --verbose --color &&

	check_sub_test_lib_test t0150-fake <<-\EOF
	> <GREEN;BOLD>ok 1 - successful one-line test<RESET>
	> <GREEN>###true<RESET>
	> Z
	> hello<GREEN;BOLD>ok 2 - successful two-line test<RESET>
	> <GREEN>###<RESET>
	> <GREEN>###	true &&<RESET>
	> <GREEN>###	# No newline, attempt to damage test output under -v. See<RESET>
	> <GREEN>###	# 57e1538ac9b (test-lib: output a newline before "ok" under a TAP<RESET>
	> <GREEN>###	# harness, 2010-06-24)<RESET>
	> <GREEN>###	printf "hello"<RESET>
	> <GREEN>###<RESET>
	> Z
	> A
	> <YELLOW;BOLD>ok 3 - unexpectedly passing TODO test # TODO known breakage vanished<RESET>
	> <YELLOW>##<RESET>
	> <YELLOW>##	echo A >expected &&<RESET>
	> <YELLOW>##<RESET>
	> <YELLOW>##	# Emit to stdout while we are at it.<RESET>
	> <YELLOW>##	grep A expected<RESET>
	> <YELLOW>##<RESET>
	> Z
	> <GREEN;BOLD>not ok 4 - failing TODO test<RESET> <YELLOW;BOLD># TODO known breakage<RESET>
	> <GREEN>###<RESET>
	> <GREEN>###	echo B >actual &&<RESET>
	> <GREEN>###	git diff --no-index --quiet expected actual<RESET>
	> <GREEN>###<RESET>
	> Z
	> <BLUE>ok 5 # SKIP we will be skipping this test (GIT_SKIP_TESTS)<RESET>
	> <BLUE>###<RESET>
	> <BLUE>###	echo skip &&<RESET>
	> <BLUE>###	echo this<RESET>
	> <BLUE>###<RESET>
	> Z
	> <RED;BOLD>not ok 6 - an one-line fail (set TEST_LIB_OUTPUT_DEMO=true)<RESET>
	> <RED>#false<RESET>
	> Z
	> '"'"'out'"'"' is not empty, it contains:
	> Z
	> <RED;BOLD>not ok 7 - a multi-line failure (set TEST_LIB_OUTPUT_DEMO=true)<RESET>
	> <RED>#<RESET>
	> <RED>#	test_when_finished "rm out" &&<RESET>
	> <RED>#	# will not be empty!<RESET>
	> <RED>#	echo >out &&<RESET>
	> <RED>#	test_must_be_empty out<RESET>
	> <RED>#<RESET>
	> Z
	> <BLUE># 1 test(s) skipped<RESET>
	> <YELLOW># 1 known breakage(s) vanished; please update test(s)<RESET>
	> <GREEN># still have 1 known breakage(s)<RESET>
	> <RED;BOLD># failed 2 among remaining 5 test(s)<RESET>
	> <CYAN>1..7<RESET>
	EOF
'

test_done

