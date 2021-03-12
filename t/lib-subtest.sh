write_sub_test_lib_test () {
	name="$1" descr="$2" # stdin is the body of the test code
	mkdir "$name" &&
	(
		cd "$name" &&
		write_script "$name.sh" "$TEST_SHELL_PATH" <<-EOF &&
		test_description='$descr (run in sub test-lib)

		This is run in a sub test-lib so that we do not get incorrect
		passing metrics
		'

		# Point to the t/test-lib.sh, which isn't in ../ as usual
		. "\$TEST_DIRECTORY"/test-lib.sh
		EOF
		cat >>"$name.sh"
	)
}

_run_sub_test_lib_test_common () {
	neg="$1" name="$2" descr="$3" # stdin is the body of the test code
	shift 3
	(
		cd "$name" &&

		# Pretend we're not running under a test harness, whether we
		# are or not. The test-lib output depends on the setting of
		# this variable, so we need a stable setting under which to run
		# the sub-test.
		sane_unset HARNESS_ACTIVE &&

		export TEST_DIRECTORY &&
		TEST_OUTPUT_DIRECTORY=$(pwd) &&
		export TEST_OUTPUT_DIRECTORY &&
		sane_unset GIT_TEST_FAIL_PREREQS &&
		if test -z "$neg"
		then
			./"$name.sh" "$@" >out 2>err
		else
			! ./"$name.sh" "$@" >out 2>err
		fi
	)
}

write_and_run_sub_test_lib_test () {
	name="$1" descr="$2" # stdin is the body of the test code
	write_sub_test_lib_test "$@" || return 1
	_run_sub_test_lib_test_common '' "$@"
}

write_and_run_sub_test_lib_test_err () {
	name="$1" descr="$2" # stdin is the body of the test code
	write_sub_test_lib_test "$@" || return 1
	_run_sub_test_lib_test_common '!' "$@"
}

run_sub_test_lib_test () {
	_run_sub_test_lib_test_common '' "$@"
}

run_sub_test_lib_test_err () {
	_run_sub_test_lib_test_common '!' "$@"
}

check_sub_test_lib_test () {
	name="$1" # stdin is the expected output from the test
	(
		cd "$name" &&
		test_must_be_empty err &&
		sed -e 's/^> //' -e 's/Z$//' >expect &&
		test_cmp expect out
	)
}

check_sub_test_lib_test_err () {
	name="$1" # stdin is the expected output from the test
	# expected error output is in descriptor 3
	(
		cd "$name" &&
		sed -e 's/^> //' -e 's/Z$//' >expect.out &&
		test_cmp expect.out out &&
		sed -e 's/^> //' -e 's/Z$//' <&3 >expect.err &&
		test_cmp expect.err err
	)
}
