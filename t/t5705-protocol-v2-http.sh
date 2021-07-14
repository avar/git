#!/bin/sh

test_description="Test protocol v2 with 'http://' transport"

GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME=main
export GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME

. ./test-lib.sh

# Test protocol v2 with 'http://' transport
#
. "$TEST_DIRECTORY"/lib-httpd.sh
start_httpd

test_expect_success 'create repo to be served by http:// transport' '
	git init "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	git -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" config http.receivepack true &&
	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" one
'

test_expect_success 'clone with http:// using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" GIT_TRACE_CURL="$(pwd)/log" git -c protocol.version=2 \
		clone "$HTTPD_URL/smart/http_parent" http_child &&

	git -C http_child log -1 --format=%s >actual &&
	git -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" log -1 --format=%s >expect &&
	test_cmp expect actual &&

	# Client requested to use protocol v2
	grep "Git-Protocol: version=2" log &&
	# Server responded using protocol v2
	grep "git< version 2" log &&
	# Verify that the chunked encoding sending codepath is NOT exercised
	! grep "Send header: Transfer-Encoding: chunked" log
'

test_expect_success 'clone repository with http:// using protocol v2 with incomplete pktline length' '
	test_when_finished "rm -f log" &&

	git init "$HTTPD_DOCUMENT_ROOT_PATH/incomplete_length" &&
	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/incomplete_length" file &&

	cat >err.expect <<-\EOF &&
	Cloning into '"'"'incomplete_length_child'"'"'...
	error: 2 bytes of length header were received
	fatal: expected response end packet after ref listing
	EOF
	test_must_fail env GIT_TRACE_PACKET="$(pwd)/log" GIT_TRACE_CURL="$(pwd)/log" git -c protocol.version=2 \
		clone "$HTTPD_URL/smart/incomplete_length" incomplete_length_child >out 2>err.actual &&

	# Client requested to use protocol v2
	grep "Git-Protocol: version=2" log &&
	# Server responded using protocol v2
	grep "git< version 2" log &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual
'

test_expect_success 'clone repository with http:// using protocol v2 with incomplete pktline body' '
	test_when_finished "rm -f log" &&

	git init "$HTTPD_DOCUMENT_ROOT_PATH/incomplete_body" &&
	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/incomplete_body" file &&

	test_must_fail env GIT_TRACE_PACKET="$(pwd)/log" GIT_TRACE_CURL="$(pwd)/log" git -c protocol.version=2 \
		clone "$HTTPD_URL/smart/incomplete_body" incomplete_body_child 2>err &&

	# Client requested to use protocol v2
	grep "Git-Protocol: version=2" log &&
	# Server responded using protocol v2
	grep "git< version 2" log &&
	# Client reported appropriate failure
	test_i18ngrep "bytes of body are still expected" err
'

test_expect_success 'clone with http:// using protocol v2 and invalid parameters' '
	test_when_finished "rm -f log" &&

	test_must_fail env GIT_TRACE_PACKET="$(pwd)/log" GIT_TRACE_CURL="$(pwd)/log" \
		git -c protocol.version=2 \
		clone --shallow-since=20151012 "$HTTPD_URL/smart/http_parent" http_child_invalid &&

	# Client requested to use protocol v2
	grep "Git-Protocol: version=2" log &&
	# Server responded using protocol v2
	grep "git< version 2" log
'

test_expect_success 'clone big repository with http:// using protocol v2' '
	test_when_finished "rm -f log" &&

	git init "$HTTPD_DOCUMENT_ROOT_PATH/big" &&
	# Ensure that the list of wants is greater than http.postbuffer below
	for i in $(test_seq 1 1500)
	do
		# do not use here-doc, because it requires a process
		# per loop iteration
		echo "commit refs/heads/too-many-refs-$i" &&
		echo "committer git <git@example.com> $i +0000" &&
		echo "data 0" &&
		echo "M 644 inline bla.txt" &&
		echo "data 4" &&
		echo "bla"
	done | git -C "$HTTPD_DOCUMENT_ROOT_PATH/big" fast-import &&

	GIT_TRACE_PACKET="$(pwd)/log" GIT_TRACE_CURL="$(pwd)/log" git \
		-c protocol.version=2 -c http.postbuffer=65536 \
		clone "$HTTPD_URL/smart/big" big_child &&

	# Client requested to use protocol v2
	grep "Git-Protocol: version=2" log &&
	# Server responded using protocol v2
	grep "git< version 2" log &&
	# Verify that the chunked encoding sending codepath is exercised
	grep "Send header: Transfer-Encoding: chunked" log
'

test_expect_success 'fetch with http:// using protocol v2' '
	test_when_finished "rm -f log" &&

	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" two &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C http_child -c protocol.version=2 \
		fetch &&

	git -C http_child log -1 --format=%s origin/main >actual &&
	git -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" log -1 --format=%s >expect &&
	test_cmp expect actual &&

	# Server responded using protocol v2
	grep "git< version 2" log
'

test_expect_success 'fetch with http:// by hash without tag following with protocol v2 does not list refs' '
	test_when_finished "rm -f log" &&

	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" two_a &&
	git -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" rev-parse two_a >two_a_hash &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C http_child -c protocol.version=2 \
		fetch --no-tags origin $(cat two_a_hash) &&

	grep "fetch< version 2" log &&
	! grep "fetch> command=ls-refs" log
'

test_expect_success 'fetch handling a bad client using http:// protocol v2' '
	test_when_finished "rm -f log" &&

	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" three &&

	cat >err.expect <<-\EOF &&
	fatal: remote error: fetch: unexpected argument: '"'"'test-bad-client'"'"'
	EOF

	test_must_fail env \
		GIT_TRACE_PACKET="$(pwd)/log" \
		GIT_TEST_PROTOCOL_BAD_FETCH=true \
		git -C http_child -c protocol.version=2 \
		fetch >out 2>err.actual &&

	test_must_be_empty out &&
	grep -v "^fatal: the remote end hung up unexpectedly$" err.actual >err.filtered &&
	test_cmp err.expect err.filtered &&
	grep "fetch> test-bad-client$" log >sent-bad-request
'

test_expect_success 'fetch from namespaced repo respects namespaces' '
	test_when_finished "rm -f log" &&

	git init "$HTTPD_DOCUMENT_ROOT_PATH/nsrepo" &&
	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/nsrepo" one &&
	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/nsrepo" two &&
	git -C "$HTTPD_DOCUMENT_ROOT_PATH/nsrepo" \
		update-ref refs/namespaces/ns/refs/heads/main one &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C http_child -c protocol.version=2 \
		fetch "$HTTPD_URL/smart_namespace/nsrepo" \
		refs/heads/main:refs/heads/theirs &&

	# Server responded using protocol v2
	grep "fetch< version 2" log &&

	git -C "$HTTPD_DOCUMENT_ROOT_PATH/nsrepo" rev-parse one >expect &&
	git -C http_child rev-parse theirs >actual &&
	test_cmp expect actual
'

test_expect_success 'ls-remote handling a bad client using http:// protocol v2' '
	test_when_finished "rm -f log" &&

	cat >log.expect <<-\EOF &&
	packet:  upload-pack> ERR ls-refs: unexpected argument: '"'"'test-bad-client'"'"'
	packet:          git< ERR ls-refs: unexpected argument: '"'"'test-bad-client'"'"'
	EOF

	cat >err.expect <<-\EOF &&
	fatal: ls-refs: unexpected argument: '"'"'test-bad-client'"'"'
	fatal: remote error: ls-refs: unexpected argument: '"'"'test-bad-client'"'"'
	EOF
	test_must_fail env \
		GIT_TRACE_PACKET="$(pwd)/log" \
		GIT_TEST_PROTOCOL_BAD_LS_REFS=true \
		git -c protocol.version=2 \
		ls-remote "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" >out 2>err.actual &&

	grep "unexpected argument.*test-bad-client" err.actual &&
	test_must_be_empty out &&
	grep ERR log >log.actual &&
	test_cmp log.expect log.actual
'

test_expect_failure  'ls-remote ERR and die() is racy under http:// protocol v2' '
	test_cmp err.expect err.actual
'

test_expect_success 'ls-remote with v2 http sends only one POST' '
	test_when_finished "rm -f log" &&

	git ls-remote "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" >expect &&
	GIT_TRACE_CURL="$(pwd)/log" git -c protocol.version=2 \
		ls-remote "$HTTPD_URL/smart/http_parent" >actual &&
	test_cmp expect actual &&

	grep "Send header: POST" log >posts &&
	test_line_count = 1 posts
'

test_expect_success 'push with http:// and a config of v2 does not request v2' '
	test_when_finished "rm -f log" &&
	# Till v2 for push is designed, make sure that if a client has
	# protocol.version configured to use v2, that the client instead falls
	# back and uses v0.

	test_commit -C http_child three &&

	# Push to another branch, as the target repository has the
	# main branch checked out and we cannot push into it.
	GIT_TRACE_PACKET="$(pwd)/log" git -C http_child -c protocol.version=2 \
		push origin HEAD:client_branch &&

	git -C http_child log -1 --format=%s >actual &&
	git -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" log -1 --format=%s client_branch >expect &&
	test_cmp expect actual &&

	# Client did not request to use protocol v2
	! grep "Git-Protocol: version=2" log &&
	# Server did not respond using protocol v2
	! grep "git< version 2" log
'

test_expect_success 'when server sends "ready", expect DELIM' '
	rm -rf "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" http_child &&

	git init "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" one &&

	git clone "$HTTPD_URL/smart/http_parent" http_child &&

	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" two &&

	# After "ready" in the acknowledgments section, pretend that a FLUSH
	# (0000) was sent instead of a DELIM (0001).
	printf "\$ready = 1 if /ready/; \$ready && s/0001/0000/" \
		>"$HTTPD_ROOT_PATH/one-time-perl" &&

	cat >err.expect <<-\EOF &&
	fatal: expected packfile to be sent after '"'"'ready'"'"'
	EOF
	test_must_fail git -C http_child -c protocol.version=2 \
		fetch "$HTTPD_URL/one_time_perl/http_parent" >out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual
'

test_expect_success 'when server does not send "ready", expect FLUSH' '
	rm -rf "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" http_child log &&

	git init "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" one &&

	git clone "$HTTPD_URL/smart/http_parent" http_child &&

	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" two &&

	# Create many commits to extend the negotiation phase across multiple
	# requests, so that the server does not send "ready" in the first
	# request.
	test_commit_bulk -C http_child --id=c 32 &&

	# After the acknowledgments section, pretend that a DELIM
	# (0001) was sent instead of a FLUSH (0000).
	printf "\$ack = 1 if /acknowledgments/; \$ack && s/0000/0001/" \
		>"$HTTPD_ROOT_PATH/one-time-perl" &&

	test_must_fail env GIT_TRACE_PACKET="$(pwd)/log" git -C http_child \
		-c protocol.version=2 \
		fetch "$HTTPD_URL/one_time_perl/http_parent" 2> err &&
	grep "fetch< .*acknowledgments" log &&
	! grep "fetch< .*ready" log &&
	test_i18ngrep "expected no other sections to be sent after no .ready." err
'

test_done
