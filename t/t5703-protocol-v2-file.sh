#!/bin/sh

test_description="Test protocol v2 with 'file://' transport"

TEST_NO_CREATE_REPO=1

GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME=main
export GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME

. ./test-lib.sh

# Test protocol v2 with 'file://' transport
#
test_expect_success 'create repo to be served by file:// transport' '
	git init file_parent &&
	test_commit -C file_parent one
'

test_expect_success 'list refs with file:// using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		ls-remote --symref "file://$(pwd)/file_parent" >actual &&

	# Server responded using protocol v2
	grep "ls-remote< version 2" log &&

	git ls-remote --symref "file://$(pwd)/file_parent" >expect &&
	test_cmp expect actual
'

test_expect_success 'ls-remote handling a bad client using file:// protocol v2' '
	test_when_finished "rm -f log" &&

	cat >log.expect <<-\EOF &&
	packet:  upload-pack> ERR ls-refs: unexpected argument: '"'"'test-bad-client'"'"'
	packet:    ls-remote< ERR ls-refs: unexpected argument: '"'"'test-bad-client'"'"'
	EOF
	cat >err.expect <<-\EOF &&
	fatal: remote error: ls-refs: unexpected argument: '"'"'test-bad-client'"'"'
	EOF
	test_must_fail env \
		GIT_TRACE_PACKET="$(pwd)/log" \
		GIT_TEST_PROTOCOL_BAD_LS_REFS=true \
		git -c protocol.version=2 \
		ls-remote "file://$(pwd)/file_parent" main >out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual &&
	grep ERR log >log.actual &&
	test_cmp log.expect log.actual
'

test_expect_success 'ref advertisement is filtered with ls-remote using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		ls-remote "file://$(pwd)/file_parent" main >actual &&

	cat >expect <<-EOF &&
	$(git -C file_parent rev-parse refs/heads/main)$(printf "\t")refs/heads/main
	EOF

	test_cmp expect actual
'

test_expect_success 'server-options are sent when using ls-remote' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		ls-remote -o hello -o world "file://$(pwd)/file_parent" main >actual &&

	cat >expect <<-EOF &&
	$(git -C file_parent rev-parse refs/heads/main)$(printf "\t")refs/heads/main
	EOF

	test_cmp expect actual &&
	grep "server-option=hello" log &&
	grep "server-option=world" log
'

test_expect_success 'warn if using server-option with ls-remote with legacy protocol' '

	cat >err.expect <<-\EOF &&
	hint: see protocol.version in '"'"'git help config'"'"' for more details
	fatal: server options require protocol version 2 or later
	EOF
	test_must_fail env GIT_TEST_PROTOCOL_VERSION=0 git -c protocol.version=0 \
		ls-remote -o hello -o world "file://$(pwd)/file_parent" main >out 2>err.actual &&

	test_must_be_empty out &&
	grep -v "^fatal: the remote end hung up unexpectedly$" err.actual >err.filtered &&
	test_cmp err.expect err.filtered
'

test_expect_success 'clone with file:// using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		clone "file://$(pwd)/file_parent" file_child &&

	git -C file_child log -1 --format=%s >actual &&
	git -C file_parent log -1 --format=%s >expect &&
	test_cmp expect actual &&

	# Server responded using protocol v2
	grep "clone< version 2" log &&

	# Client sent ref-prefixes to filter the ref-advertisement
	grep "ref-prefix HEAD" log &&
	grep "ref-prefix refs/heads/" log &&
	grep "ref-prefix refs/tags/" log
'

test_expect_success 'clone of empty repo propagates name of default branch' '
	test_when_finished "rm -rf file_empty_parent file_empty_child" &&

	GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME= \
	git -c init.defaultBranch=mydefaultbranch init file_empty_parent &&

	GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME= \
	git -c init.defaultBranch=main -c protocol.version=2 \
		clone "file://$(pwd)/file_empty_parent" file_empty_child &&
	grep "refs/heads/mydefaultbranch" file_empty_child/.git/HEAD
'

test_expect_success '...but not if explicitly forbidden by config' '
	test_when_finished "rm -rf file_empty_parent file_empty_child" &&

	GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME= \
	git -c init.defaultBranch=mydefaultbranch init file_empty_parent &&
	test_config -C file_empty_parent lsrefs.unborn ignore &&

	GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME= \
	git -c init.defaultBranch=main -c protocol.version=2 \
		clone "file://$(pwd)/file_empty_parent" file_empty_child &&
	! grep "refs/heads/mydefaultbranch" file_empty_child/.git/HEAD
'

test_expect_success 'fetch with file:// using protocol v2' '
	test_when_finished "rm -f log" &&

	test_commit -C file_parent two &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C file_child -c protocol.version=2 \
		fetch origin &&

	git -C file_child log -1 --format=%s origin/main >actual &&
	git -C file_parent log -1 --format=%s >expect &&
	test_cmp expect actual &&

	# Server responded using protocol v2
	grep "fetch< version 2" log
'

test_expect_success 'ref advertisement is filtered during fetch using protocol v2' '
	test_when_finished "rm -f log" &&

	test_commit -C file_parent three &&
	git -C file_parent branch unwanted-branch three &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C file_child -c protocol.version=2 \
		fetch origin main &&

	git -C file_child log -1 --format=%s origin/main >actual &&
	git -C file_parent log -1 --format=%s >expect &&
	test_cmp expect actual &&

	grep "refs/heads/main" log &&
	! grep "refs/heads/unwanted-branch" log
'

test_expect_success 'server-options are sent when fetching' '
	test_when_finished "rm -f log" &&

	test_commit -C file_parent four &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C file_child -c protocol.version=2 \
		fetch -o hello -o world origin main &&

	git -C file_child log -1 --format=%s origin/main >actual &&
	git -C file_parent log -1 --format=%s >expect &&
	test_cmp expect actual &&

	grep "server-option=hello" log &&
	grep "server-option=world" log
'

test_expect_success 'fetch handling a bad client using file:// protocol v2' '
	test_when_finished "rm -f log" &&

	test_commit -C file_parent five &&

	cat >err.expect <<-\EOF &&
	fatal: remote error: fetch: unexpected argument: '"'"'test-bad-client'"'"'
	EOF
	test_must_fail env \
		GIT_TRACE_PACKET="$(pwd)/log" \
		GIT_TEST_PROTOCOL_BAD_FETCH=true \
		git -C file_child -c protocol.version=2 \
		fetch >out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual &&

	grep "fetch> test-bad-client$" log >sent-bad-request &&
	test_file_not_empty sent-bad-request
'

test_expect_success 'server-options are sent when cloning' '
	test_when_finished "rm -rf log myclone" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		clone --server-option=hello --server-option=world \
		"file://$(pwd)/file_parent" myclone &&

	grep "server-option=hello" log &&
	grep "server-option=world" log
'

test_expect_success 'upload-pack respects config using protocol v2' '
	test_when_finished "rm -rf server client" &&
	git init server &&
	write_script server/.git/hook <<-\EOF &&
		touch hookout
		"$@"
	EOF
	test_commit -C server one &&

	test_config_global uploadpack.packobjectshook ./hook &&
	test_path_is_missing server/.git/hookout &&
	git -c protocol.version=2 clone "file://$(pwd)/server" client &&
	test_path_is_file server/.git/hookout
'

test_done
