_assert_unique_sub_test () {
	name=$1 &&

	# Alert about the copy/paste programming
	hash=$(git hash-object -w "$name") &&
	cat >tag.sig <<-EOF &&
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

	tag=$(git mktag <tag.sig) &&
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
	cmp_op="$1" want_code="$2" name="$3" # stdin is the body of the test code
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
		./"$name.sh" "$@" >out 2>err;
		ret=$? &&
		grep -v \
		     -e "^Initialized empty.* Git repository" \
		     -e "^Reinitialized existing.* Git repository" \
		     out >out+ &&
		mv out+ out &&
		test "$ret" "$cmp_op" "$want_code"
	)
}

write_and_run_sub_test_lib_test () {
	name="$1" descr="$2" # stdin is the body of the test code
	write_sub_test_lib_test "$@" || return 1
	_run_sub_test_lib_test_common -eq 0 "$@"
}

write_and_run_sub_test_lib_test_err () {
	name="$1" descr="$2" # stdin is the body of the test code
	write_sub_test_lib_test "$@" || return 1
	_run_sub_test_lib_test_common -eq 1 "$@"
}

run_sub_test_lib_test () {
	_run_sub_test_lib_test_common -eq 0 "$@"
}

run_sub_test_lib_test_err () {
	_run_sub_test_lib_test_common -eq 1 "$@"
}

_check_sub_test_lib_test_common () {
	name="$1" &&
	sed -e 's/^> //' -e 's/Z$//' >"$name"/expect.out &&
	test_cmp "$name"/expect.out "$name"/out
}

check_sub_test_lib_test () {
	name="$1" # stdin is the expected output from the test
	_check_sub_test_lib_test_common "$name" &&
	test_must_be_empty "$name"/err
}

check_sub_test_lib_test_out () {
	name="$1" # stdin is the expected output from the test
	_check_sub_test_lib_test_common "$name"
}

check_sub_test_lib_test_err () {
	name="$1" # stdin is the expected output from the test
	_check_sub_test_lib_test_common "$name" &&
	# expected error output is in descriptor 3
	sed -e 's/^> //' -e 's/Z$//' <&3 >"$name"/expect.err &&
	test_cmp "$name"/expect.err "$name"/err
}
