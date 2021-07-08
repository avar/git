#!/bin/sh

test_description='test git wire-protocol version 2'

TEST_NO_CREATE_REPO=1

. ./test-lib.sh

test_expect_success 'setup file_parent' '
	git init file_parent &&
	test_commit -C file_parent one
'

test_expect_success 'warn if using server-option with fetch with legacy protocol' '
	test_when_finished "rm -rf temp_child" &&

	git init temp_child &&

	cat >err.expect <<-\EOF &&
	hint: see protocol.version in '"'"'git help config'"'"' for more details
	fatal: server options require protocol version 2 or later
	EOF
	test_must_fail env GIT_TEST_PROTOCOL_VERSION=0 git -C temp_child -c protocol.version=0 \
		fetch -o hello -o world "file://$(pwd)/file_parent" main >out 2>err.actual &&

	test_must_be_empty out &&
	grep -v "^fatal: the remote end hung up unexpectedly$" err.actual >err.filtered &&
	test_cmp err.expect err.filtered
'

test_expect_success 'warn if using server-option with clone with legacy protocol' '
	test_when_finished "rm -rf myclone" &&

	cat >err.expect <<-\EOF &&
	Cloning into '"'"'myclone'"'"'...
	hint: see protocol.version in '"'"'git help config'"'"' for more details
	fatal: server options require protocol version 2 or later
	EOF
	test_must_fail env GIT_TEST_PROTOCOL_VERSION=0 git -c protocol.version=0 \
		clone --server-option=hello --server-option=world \
		"file://$(pwd)/file_parent" myclone >out 2>err.actual &&

	test_must_be_empty out &&
	grep -v "^fatal: the remote end hung up unexpectedly$" err.actual >err.filtered &&
	test_cmp err.expect err.filtered
'

test_expect_success 'fetch supports various ways of have lines' '
	test_when_finished "rm -rf server client trace" &&
	git init server &&
	test_commit -C server dwim &&
	TREE=$(git -C server rev-parse HEAD^{tree}) &&
	git -C server tag exact \
		$(git -C server commit-tree -m a "$TREE") &&
	git -C server tag dwim-unwanted \
		$(git -C server commit-tree -m b "$TREE") &&
	git -C server tag exact-unwanted \
		$(git -C server commit-tree -m c "$TREE") &&
	git -C server tag prefix1 \
		$(git -C server commit-tree -m d "$TREE") &&
	git -C server tag prefix2 \
		$(git -C server commit-tree -m e "$TREE") &&
	git -C server tag fetch-by-sha1 \
		$(git -C server commit-tree -m f "$TREE") &&
	git -C server tag completely-unrelated \
		$(git -C server commit-tree -m g "$TREE") &&

	git init client &&
	GIT_TRACE_PACKET="$(pwd)/trace" git -C client -c protocol.version=2 \
		fetch "file://$(pwd)/server" \
		dwim \
		refs/tags/exact \
		refs/tags/prefix*:refs/tags/prefix* \
		"$(git -C server rev-parse fetch-by-sha1)" &&

	# Ensure that the appropriate prefixes are sent (using a sample)
	grep "fetch> ref-prefix dwim" trace &&
	grep "fetch> ref-prefix refs/heads/dwim" trace &&
	grep "fetch> ref-prefix refs/tags/prefix" trace &&

	# Ensure that the correct objects are returned
	git -C client cat-file -e $(git -C server rev-parse dwim) &&
	git -C client cat-file -e $(git -C server rev-parse exact) &&
	git -C client cat-file -e $(git -C server rev-parse prefix1) &&
	git -C client cat-file -e $(git -C server rev-parse prefix2) &&
	git -C client cat-file -e $(git -C server rev-parse fetch-by-sha1) &&
	test_must_fail git -C client cat-file -e \
		$(git -C server rev-parse dwim-unwanted) &&
	test_must_fail git -C client cat-file -e \
		$(git -C server rev-parse exact-unwanted) &&
	test_must_fail git -C client cat-file -e \
		$(git -C server rev-parse completely-unrelated)
'

test_expect_success 'fetch supports include-tag and tag following' '
	test_when_finished "rm -rf server client trace" &&

	git init server &&
	test_commit -C server to_fetch &&
	git -C server tag -a annotated_tag -m message &&

	git init client &&
	GIT_TRACE_PACKET="$(pwd)/trace" git -C client -c protocol.version=2 \
		fetch "$(pwd)/server" to_fetch:to_fetch &&

	grep "fetch> ref-prefix to_fetch" trace &&
	grep "fetch> ref-prefix refs/tags/" trace &&
	grep "fetch> include-tag" trace &&

	git -C client cat-file -e $(git -C client rev-parse annotated_tag)
'


test_done
