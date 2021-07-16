#!/bin/sh

test_description='Test fetch --negotiate-only with protocol v2'

. ./test-lib.sh

setup_negotiate_only_server () {
	test_when_finished "rm -rf \"$1\"" &&
	git init "$1" &&
	test_commit -C "$1" one &&
	test_commit -C "$1" two
}

setup_negotiate_only_client () {
	test_when_finished "rm -rf client" &&
	git clone "$1" client &&
	test_commit -C client three
}

setup_negotiate_only () {
	SERVER="$1"
	URI="$2"

	setup_negotiate_only_server "$SERVER" &&
	setup_negotiate_only_client "$URI"
}

test_expect_success 'usage: --negotiate-only without --negotiation-tip' '
	SERVER="server" &&
	URI="file://$(pwd)/server" &&

	setup_negotiate_only "$SERVER" "$URI" &&

	cat >err.expect <<-\EOF &&
	fatal: --negotiate-only needs one or more --negotiate-tip=*
	EOF

	test_must_fail git -c protocol.version=2 -C client fetch \
		--negotiate-only \
		origin 2>err.actual &&
	test_cmp err.expect err.actual
'

test_expect_success 'file:// --negotiate-only' '
	SERVER="server" &&
	URI="file://$(pwd)/server" &&

	setup_negotiate_only "$SERVER" "$URI" &&

	git -c protocol.version=2 -C client fetch \
		--no-tags \
		--negotiate-only \
		--negotiation-tip=$(git -C client rev-parse HEAD) \
		origin >out &&
	COMMON=$(git -C "$SERVER" rev-parse two) &&
	grep "$COMMON" out
'

test_expect_success 'file:// --negotiate-only with protocol v0' '
	SERVER="server" &&
	URI="file://$(pwd)/server" &&

	setup_negotiate_only "$SERVER" "$URI" &&

	cat >err.expect <<-\EOF &&
	warning: --negotiate-only requires protocol v2
	EOF
	test_must_fail git -c protocol.version=0 -C client fetch \
		--no-tags \
		--negotiate-only \
		--negotiation-tip=$(git -C client rev-parse HEAD) \
		origin >out 2>err.actual &&

	test_must_be_empty out &&
	grep -v "^fatal: the remote end hung up unexpectedly$" err.actual >err.filtered &&
	test_cmp err.expect err.filtered
'

. "$TEST_DIRECTORY"/lib-httpd.sh
start_httpd

test_expect_success 'http:// --negotiate-only' '
	rm -rf server client &&
	SERVER="$HTTPD_DOCUMENT_ROOT_PATH/server" &&
	URI="$HTTPD_URL/smart/server" &&

	setup_negotiate_only "$SERVER" "$URI" &&

	sort >expect <<-EOF &&
	$(git -C client rev-parse one)
	$(git -C "$SERVER" rev-parse two)
	EOF
	git -c protocol.version=2 -C client fetch \
		--no-tags \
		--negotiate-only \
		--negotiation-tip=$(git -C client rev-parse HEAD) \
		origin >actual 2>err &&
	sort actual >actual.sorted &&

	test_must_be_empty err &&
	test_cmp expect actual.sorted
'

test_expect_success 'http:// --negotiate-only without wait-for-done support' '
	OTHER_SERVER="$HTTPD_DOCUMENT_ROOT_PATH/server" &&

	setup_negotiate_only_server "$OTHER_SERVER" &&

	SERVER="server" &&
	URI="$HTTPD_URL/one_time_perl/server" &&

	setup_negotiate_only "$SERVER" "$URI" &&

	echo "s/ wait-for-done/ xxxx-xxx-xxxx/" \
		>"$HTTPD_ROOT_PATH/one-time-perl" &&

	cat >err.expect <<-\EOF &&
	warning: server does not support wait-for-done
	EOF
	test_must_fail git -c protocol.version=2 -C client fetch \
		--no-tags \
		--negotiate-only \
		--negotiation-tip=$(git -C client rev-parse HEAD) \
		origin >out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual
'

test_expect_success 'http:// --negotiate-only with protocol v0' '
	SERVER="$HTTPD_DOCUMENT_ROOT_PATH/server" &&
	URI="$HTTPD_URL/smart/server" &&

	setup_negotiate_only "$SERVER" "$URI" &&

	cat >err.expect <<-EOF &&
	warning: --negotiate-only requires protocol v2
	EOF
	test_must_fail git -c protocol.version=0 -C client fetch \
		--no-tags \
		--negotiate-only \
		--negotiation-tip=$(git -C client rev-parse HEAD) \
		origin >out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual
'

test_done
