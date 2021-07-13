#!/bin/sh

test_description="Test protocol v2 with 'git://' transport"

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

test_expect_success 'connect with file:// using protocol v2: no bundle-uri' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" \
	git \
		-c protocol.version=2 \
		ls-remote --symref "file://$(pwd)/file_parent" \
		>actual 2>err &&

	# Server responded using protocol v2
	grep "ls-remote< version 2" log &&

	! grep bundle-uri log
'

test_expect_success 'connect with file:// using protocol v2: no bundle-uri' '
	test_when_finished "rm -f log" &&

	test_config -C file_parent uploadpack.bundleURI "file://$(pwd)/file_parent/one.bdl" &&

	GIT_TRACE_PACKET="$(pwd)/log" \
	git \
		-c protocol.version=2 \
		ls-remote --symref "file://$(pwd)/file_parent" \
		>actual 2>err &&

	# Server responded using protocol v2
	grep "ls-remote< version 2" log &&

	# Server advertised bundle-uri capability
	grep bundle-uri log
'

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

	GIT_TRACE_PACKET="$(pwd)/log" \
	git \
		-c protocol.version=2 \
		ls-remote "$GIT_DAEMON_URL/parent" >actual 2>err
'

test_done
