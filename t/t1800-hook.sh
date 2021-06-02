#!/bin/bash

test_description='git-hook command'

. ./test-lib.sh

test_expect_success 'git hook run -- nonexistent hook' '
	cat >stderr.expect <<-\EOF &&
	error: cannot find a hook named test-hook
	EOF
	test_expect_code 1 git hook run test-hook 2>stderr.actual &&
	test_cmp stderr.expect stderr.actual
'

test_expect_success 'git hook run -- nonexistent hook with --ignore-missing' '
	git hook run --ignore-missing test-hook 2>stderr.actual &&
	test_must_be_empty stderr.actual
'

test_expect_success 'git hook run -- nonexistent hook with --ignore-missing' '
	cat >stderr.expect <<-\EOF &&
	fatal: the hook '"'"'unknown-hook'"'"' is not known to git, should be in hook-list.h via githooks(5)
	EOF
	test_expect_code 128 git hook run unknown-hook 2>stderr.actual &&
	test_cmp stderr.expect stderr.actual
'

test_expect_success 'git hook run -- basic' '
	write_script .git/hooks/test-hook <<-EOF &&
	echo Test hook
	EOF

	cat >expect <<-\EOF &&
	Test hook
	EOF
	git hook run test-hook 2>actual &&
	test_cmp expect actual
'

test_expect_success 'git hook run -- stdout and stderr handling' '
	write_script .git/hooks/test-hook <<-EOF &&
	echo >&1 Will end up on stderr
	echo >&2 Will end up on stderr
	EOF

	cat >stderr.expect <<-\EOF &&
	Will end up on stderr
	Will end up on stderr
	EOF
	git hook run test-hook >stdout.actual 2>stderr.actual &&
	test_cmp stderr.expect stderr.actual &&
	test_must_be_empty stdout.actual
'

test_expect_success 'git hook run -- exit codes are passed along' '
	write_script .git/hooks/test-hook <<-EOF &&
	exit 1
	EOF

	test_expect_code 1 git hook run test-hook &&

	write_script .git/hooks/test-hook <<-EOF &&
	exit 2
	EOF

	test_expect_code 2 git hook run test-hook &&

	write_script .git/hooks/test-hook <<-EOF &&
	exit 128
	EOF

	test_expect_code 128 git hook run test-hook &&

	write_script .git/hooks/test-hook <<-EOF &&
	exit 129
	EOF

	test_expect_code 129 git hook run test-hook
'

test_expect_success 'git hook run arg u ments without -- is not allowed' '
	test_expect_code 129 git hook run test-hook arg u ments
'

test_expect_success 'git hook run -- pass arguments' '
	write_script .git/hooks/test-hook <<-\EOF &&
	echo $1
	echo $2
	EOF

	cat >expect <<-EOF &&
	arg
	u ments
	EOF

	git hook run test-hook -- arg "u ments" 2>actual &&
	test_cmp expect actual
'

test_expect_success 'git hook run -- out-of-repo runs excluded' '
	write_script .git/hooks/test-hook <<-EOF &&
	echo Test hook
	EOF

	nongit test_must_fail git hook run test-hook
'

test_expect_success 'git -c core.hooksPath=<PATH> hook run' '
	mkdir my-hooks &&
	write_script my-hooks/test-hook <<-EOF &&
	echo Hook ran >>actual
	EOF

	cat >expect <<-\EOF &&
	Test hook
	Hook ran
	Hook ran
	Hook ran
	Hook ran
	EOF

	# Test various ways of specifying the path. See also
	# t1350-config-hooks-path.sh
	>actual &&
	git hook run test-hook 2>>actual &&
	git -c core.hooksPath=my-hooks hook run test-hook 2>>actual &&
	git -c core.hooksPath=my-hooks/ hook run test-hook 2>>actual &&
	git -c core.hooksPath="$PWD/my-hooks" hook run test-hook 2>>actual &&
	git -c core.hooksPath="$PWD/my-hooks/" hook run test-hook 2>>actual &&
	test_cmp expect actual
'

test_expect_success 'set up a pre-commit hook in core.hooksPath' '
	>actual &&
	mkdir -p .git/custom-hooks .git/hooks &&
	write_script .git/custom-hooks/pre-commit <<-\EOF &&
	echo CUSTOM >>actual
	EOF
	write_script .git/hooks/pre-commit <<-\EOF
	echo NORMAL >>actual
	EOF
'

test_expect_success 'stdin to hooks' '
	write_script .git/hooks/test-hook <<-\EOF &&
	echo BEGIN stdin
	cat
	echo END stdin
	EOF

	cat >expect <<-EOF &&
	BEGIN stdin
	hello
	END stdin
	EOF

	echo hello >input &&
	git hook run --to-stdin=input test-hook 2>actual &&
	test_cmp expect actual
'

test_done
