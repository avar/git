#!/bin/sh

test_description='test-tool tee-tap, used by test-lib.sh itself'
TEST_NO_CREATE_REPO=true
. ./test-lib.sh

test_expect_success 'usage' '
	# Just use "tee(1)" instead
	test_expect_code 129 test-tool tee-tap file &&

	# Option incompatibilities
	test_expect_code 129 test-tool tee-tap --out-only-tap a-file &&
	test_expect_code 129 test-tool tee-tap --out-escape a-file &&
	test_expect_code 129 test-tool tee-tap --file-escape a-file &&
	test_expect_code 129 test-tool tee-tap --out-comment-level a-file &&

	# Cannot be asked to escape things that do not need escaping
	test_expect_code 129 test-tool tee-tap a-file &&
	test_expect_code 129 test-tool tee-tap --prefix="PF " --out-only-tap --out-escape a-file

'

test_expect_success 'setup' '
	cat >t.stdout <<-\EOF &&
	PF TAP version 13
	PF pragma +strict
	PF ok 1 - OK

	This is not
	TAP
	 # indented
	 ok not ok

	PF # a diagnostic
	PF not ok 2 - NOK
	PF Bail out!
	PF # failed 1 among remaining 2 test(s)
	PF 1..2
	EOF
	sed "s/^PF //" <t.stdout >t.tap &&
	grep "^PF " t.stdout >t.stdout.tap &&
	sed "s/^PF //" <t.stdout.tap >t.tap-only
'

test_expect_success 'pass through "tee" mode with TAP parsing' '
	test-tool tee-tap --prefix="PF " file <t.stdout >stdout &&
	test_cmp t.tap stdout &&
	test_cmp t.tap file
'

test_expect_success 'prune to only TAP on stdout (for --verbose-log)' '
	test-tool tee-tap --prefix="PF " \
		--out-only-tap file <t.stdout >stdout &&
	test_cmp t.tap-only stdout &&
	test_cmp t.tap file
'

test_expect_success 'escape to make stdout/file valid TAP (for re-parsing)' '
	cat >injection.stdout <<-\EOF &&
	have to
	PF ok 1 escape
	ok
	PF ok 2 on its own
	not ok
	# to have bare comments
	PF 1..2
	EOF

	sed \
		-e "s/^\\(ok\\|not ok\\|#\\)/\\\\\1/" \
		-e "s/^PF //" <injection.stdout >injection.escaped &&
	sed -n -e "s/^PF \\(.*\\)/\\1/p" <injection.stdout >tap &&

	test-tool tee-tap --prefix="PF " \
		--out-escape --file-escape \
		file <injection.stdout >stdout &&
	test_cmp injection.escaped stdout &&
	test_cmp injection.escaped file &&

	test-tool tee-tap --prefix="PF " \
		--out-escape --file-escape \
		file <injection.stdout >stdout &&
	test_cmp injection.escaped stdout &&
	test_cmp injection.escaped file &&

	test-tool tee-tap --prefix="PF " \
		--out-only-tap --file-escape \
		file <injection.stdout >stdout &&
	test_cmp tap stdout &&
	test_cmp injection.escaped file
'

test_expect_success 'setup comment stripping with --out-only-tap' '
	cat >injection.stdout <<-\EOF &&
	PF # one
	# x -- other
	PF ## two
	## y -- other
	PF ### three
	##z -- other
	PF ok 1 other
	PF 1..1 # other
	EOF

	sed \
		-e "s/^\\(ok\\|not ok\\|#\\)/\\\\\1/" \
		-e "s/^PF //" <injection.stdout >injection.escaped
'

test_expect_success '(non-)comment stripping with --out-only-tap' '
	sed -e "/^\\\/d" <injection.escaped >injection.tap &&
	test-tool tee-tap --prefix="PF " \
		--out-only-tap --file-escape \
		file <injection.stdout >stdout &&
	test_cmp injection.escaped file &&
	# We test the specifics after further setup below
	test_file_not_empty stdout
'

test_expect_success 'setup: selective comment stripping with --out-only-tap and N-level comments' '
	cp injection.tap injection.tap-c3 &&
	sed -e "/three/d" <injection.tap >injection.tap-c2 &&
	sed -e "/two/d" <injection.tap-c2 >injection.tap-c1 &&
	sed -e "/one/d" <injection.tap-c1 >injection.tap-c0
'

test_expect_success 'comment stripping --out-comment-level=0' '
	test-tool tee-tap --prefix="PF " \
		--out-only-tap --out-comment-level=0 --file-escape \
		file <injection.stdout >stdout &&
	test_cmp injection.tap-c0 stdout &&
	test_cmp injection.escaped file
'

test_expect_success 'comment stripping --out-comment-level=1' '
	test-tool tee-tap --prefix="PF " \
		--out-only-tap --out-comment-level=1 --file-escape \
		file <injection.stdout >stdout &&
	test_cmp injection.tap-c1 stdout &&
	test_cmp injection.escaped file
'

test_expect_success 'comment stripping --out-comment-level=1 is the default' '
	test-tool tee-tap --prefix="PF " \
		--out-only-tap --file-escape \
		file <injection.stdout >stdout &&
	test_cmp injection.tap-c1 stdout &&
	test_cmp injection.escaped file
'

test_expect_success 'comment stripping --out-comment-level=2' '
	test-tool tee-tap --prefix="PF " \
		--out-only-tap --out-comment-level=2 --file-escape \
		file <injection.stdout >stdout &&
	test_cmp injection.tap-c2 stdout &&
	test_cmp injection.escaped file
'

test_expect_success 'comment stripping --out-comment-level=3' '
	test-tool tee-tap --prefix="PF " \
		--out-only-tap --out-comment-level=3 --file-escape \
		file <injection.stdout >stdout &&
	test_cmp injection.tap-c3 stdout &&
	test_cmp injection.escaped file
'

test_done

