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
	run_sub_test_lib_test_err t0150-fake &&

	check_sub_test_lib_test t0150-fake <<-\EOF
	> ok 1 - successful one-line test
	> ok 2 - successful two-line test
	> ok 3 - unexpectedly passing TODO test # TODO known breakage vanished
	> not ok 4 - failing TODO test # TODO known breakage
	> ok 5 # skip we will be skipping this test (GIT_SKIP_TESTS)
	> not ok 6 - an one-line fail (set TEST_LIB_OUTPUT_DEMO=true)
	> #	false
	> not ok 7 - a multi-line failure (set TEST_LIB_OUTPUT_DEMO=true)
	> #	Z
	> #		test_when_finished "rm out" &&
	> #		# will not be empty!
	> #		echo >out &&
	> #		test_must_be_empty out
	> #	Z
	> # 1 known breakage(s) vanished; please update test(s)
	> # still have 1 known breakage(s)
	> # failed 2 among remaining 5 test(s)
	> 1..7
	EOF
'

test_expect_success 'run t0150-fake.sh --verbose' '
	run_sub_test_lib_test_err t0150-fake --verbose &&

	check_sub_test_lib_test t0150-fake <<-\EOF
	> expecting success of 0150.1 '"'"'successful one-line test'"'"': true
	> ok 1 - successful one-line test
	> Z
	> expecting success of 0150.2 '"'"'successful two-line test'"'"': Z
	> 	true &&
	> 	# No newline, attempt to damage test output under -v. See
	> 	# 57e1538ac9b (test-lib: output a newline before "ok" under a TAP
	> 	# harness, 2010-06-24)
	> 	printf "hello"
	> Z
	> hellook 2 - successful two-line test
	> Z
	> checking known breakage of 0150.3 '"'"'unexpectedly passing TODO test'"'"': Z
	> 	echo A >expected &&
	> Z
	> 	# Emit to stdout while we are at it.
	> 	grep A expected
	> Z
	> A
	> ok 3 - unexpectedly passing TODO test # TODO known breakage vanished
	> Z
	> checking known breakage of 0150.4 '"'"'failing TODO test'"'"': Z
	> 	echo B >actual &&
	> 	git diff --no-index --quiet expected actual
	> Z
	> not ok 4 - failing TODO test # TODO known breakage
	> Z
	> ok 5 # skip we will be skipping this test (GIT_SKIP_TESTS)
	> Z
	> expecting success of 0150.6 '"'"'an one-line fail (set TEST_LIB_OUTPUT_DEMO=true)'"'"': false
	> not ok 6 - an one-line fail (set TEST_LIB_OUTPUT_DEMO=true)
	> #	false
	> Z
	> expecting success of 0150.7 '"'"'a multi-line failure (set TEST_LIB_OUTPUT_DEMO=true)'"'"': Z
	> 	test_when_finished "rm out" &&
	> 	# will not be empty!
	> 	echo >out &&
	> 	test_must_be_empty out
	> Z
	> '"'"'out'"'"' is not empty, it contains:
	> Z
	> not ok 7 - a multi-line failure (set TEST_LIB_OUTPUT_DEMO=true)
	> #	Z
	> #		test_when_finished "rm out" &&
	> #		# will not be empty!
	> #		echo >out &&
	> #		test_must_be_empty out
	> #	Z
	> Z
	> # 1 known breakage(s) vanished; please update test(s)
	> # still have 1 known breakage(s)
	> # failed 2 among remaining 5 test(s)
	> 1..7
	EOF
'

test_done

