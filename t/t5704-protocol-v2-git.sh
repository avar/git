#!/bin/sh

test_description="Test protocol v2 with 'git://' transport"

TEST_NO_CREATE_REPO=1

GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME=main
export GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME

. ./test-lib.sh

# Test protocol v2 with 'git://' transport
#
. "$TEST_DIRECTORY"/lib-git-daemon.sh
start_git_daemon --export-all --enable=receive-pack
daemon_parent=$GIT_DAEMON_DOCUMENT_ROOT_PATH/parent

test_expect_success 'create repo to be served by git-daemon' '
	git init "$daemon_parent" &&
	test_commit -C "$daemon_parent" one
'

test_expect_success 'list refs with git:// using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		ls-remote --symref "$GIT_DAEMON_URL/parent" >actual &&

	# Client requested to use protocol v2
	grep "git> .*\\\0\\\0version=2\\\0$" log &&
	# Server responded using protocol v2
	grep "git< version 2" log &&

	git ls-remote --symref "$GIT_DAEMON_URL/parent" >expect &&
	test_cmp expect actual
'

test_expect_success 'ref advertisement is filtered with ls-remote using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		ls-remote "$GIT_DAEMON_URL/parent" main >actual &&

	cat >expect <<-EOF &&
	$(git -C "$daemon_parent" rev-parse refs/heads/main)$(printf "\t")refs/heads/main
	EOF

	test_cmp expect actual
'

test_expect_success 'ls-remote handling a bad client using protocol v2' '
	test_when_finished "rm -f log" &&

	cat >err.expect <<-EOF &&
	fatal: remote error: ls-refs: unexpected argument: '"'"'test-bad-client'"'"'
	EOF
	test_must_fail env \
		GIT_TRACE_PACKET="$(pwd)/log" \
		GIT_TEST_PROTOCOL_BAD_LS_REFS=true \
		git -c protocol.version=2 \
		ls-remote "$GIT_DAEMON_URL/parent" main >out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual &&
	grep "ERR ls-refs: unexpected argument.*test-bad-client" log
'


test_expect_success 'clone with git:// using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		clone "$GIT_DAEMON_URL/parent" daemon_child &&

	git -C daemon_child log -1 --format=%s >actual &&
	git -C "$daemon_parent" log -1 --format=%s >expect &&
	test_cmp expect actual &&

	# Client requested to use protocol v2
	grep "clone> .*\\\0\\\0version=2\\\0$" log &&
	# Server responded using protocol v2
	grep "clone< version 2" log
'

test_expect_success 'fetch with git:// using protocol v2' '
	test_when_finished "rm -f log" &&

	test_commit -C "$daemon_parent" two &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C daemon_child -c protocol.version=2 \
		fetch &&

	git -C daemon_child log -1 --format=%s origin/main >actual &&
	git -C "$daemon_parent" log -1 --format=%s >expect &&
	test_cmp expect actual &&

	# Client requested to use protocol v2
	grep "fetch> .*\\\0\\\0version=2\\\0$" log &&
	# Server responded using protocol v2
	grep "fetch< version 2" log
'

test_expect_success 'fetch by hash without tag following with protocol v2 does not list refs' '
	test_when_finished "rm -f log" &&

	test_commit -C "$daemon_parent" two_a &&
	git -C "$daemon_parent" rev-parse two_a >two_a_hash &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C daemon_child -c protocol.version=2 \
		fetch --no-tags origin $(cat two_a_hash) &&

	grep "fetch< version 2" log &&
	! grep "fetch> command=ls-refs" log
'

test_expect_success 'pull with git:// using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C daemon_child -c protocol.version=2 \
		pull &&

	git -C daemon_child log -1 --format=%s >actual &&
	git -C "$daemon_parent" log -1 --format=%s >expect &&
	test_cmp expect actual &&

	# Client requested to use protocol v2
	grep "fetch> .*\\\0\\\0version=2\\\0$" log &&
	# Server responded using protocol v2
	grep "fetch< version 2" log
'

test_expect_success 'push with git:// and a config of v2 does not request v2' '
	test_when_finished "rm -f log" &&

	# Till v2 for push is designed, make sure that if a client has
	# protocol.version configured to use v2, that the client instead falls
	# back and uses v0.

	test_commit -C daemon_child three &&

	# Push to another branch, as the target repository has the
	# main branch checked out and we cannot push into it.
	GIT_TRACE_PACKET="$(pwd)/log" git -C daemon_child -c protocol.version=2 \
		push origin HEAD:client_branch &&

	git -C daemon_child log -1 --format=%s >actual &&
	git -C "$daemon_parent" log -1 --format=%s client_branch >expect &&
	test_cmp expect actual &&

	# Client requested to use protocol v2
	! grep "push> .*\\\0\\\0version=2\\\0$" log &&
	# Server responded using protocol v2
	! grep "push< version 2" log
'

test_expect_success 'fetch handling a bad client using git:// protocol v2' '
	test_when_finished "rm -f log" &&

	test_commit -C "$daemon_parent" four &&

	cat >err.expect <<-EOF &&
	fatal: remote error: fetch: unexpected argument: '"'"'test-bad-client'"'"'
	EOF
	test_must_fail env \
		GIT_TRACE_PACKET="$(pwd)/log" \
		GIT_TEST_PROTOCOL_BAD_FETCH=true \
		git -C daemon_child -c protocol.version=2 \
		fetch >out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual &&
	grep "fetch> test-bad-client$" log >sent-bad-request &&
	test_file_not_empty sent-bad-request
'

test_done
