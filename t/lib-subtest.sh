_assert_unique_sub_test () {
	name=$1 &&

	# Alert about the copy/paste programming
	hash=$(git hash-object -w "$name") &&
	tag=$(git mktag <<-EOF) &&
	object $hash
	type blob
	tag $hash
	tagger . <> 0 +0000

	duplicate script detected!

	This test script was already written as:

	$name

	You can just re-use its test code with your own
	run_sub_test_lib_test*()
	EOF

	if ! git update-ref refs/tags/blob-$hash $tag $(test_oid zero) 2>/dev/null
	then
		msg=$(git for-each-ref refs/tags/blob-$hash \
			--format='%(contents)' refs/tags/blob-$hash)
		error "on write of $name: $msg"
		return 1
	fi
}

write_sub_test_lib_test () {
	name="$1" # stdin is the body of the test code
	mkdir "$name" &&
	write_script "$name/$name.sh" "$TEST_SHELL_PATH" <<-EOF &&
	test_description='A test of test-lib.sh itself'

	# Point to the t/test-lib.sh, which isn't in ../ as usual
	. "\$TEST_DIRECTORY"/test-lib.sh
	EOF
	cat >>"$name/$name.sh" &&
	_assert_unique_sub_test "$name/$name.sh"
}

_run_sub_test_lib_test_common () {
	neg="$1" name="$2" # stdin is the body of the test code
	shift 2
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
