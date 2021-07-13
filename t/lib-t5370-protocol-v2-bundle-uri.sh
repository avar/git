# Included from t573*-protocol-v2-bundle-uri-*.sh

T5370_PARENT=
T5370_URI=
T5370_BUNDLE_URI=
case "$T5730_PROTOCOL" in
file)
	T5370_PARENT=file_parent
	T5370_URI="file://$PWD/file_parent"
	T5370_BUNDLE_URI="$T5370_URI/fake.bdl"
	;;
git)
	. "$TEST_DIRECTORY"/lib-git-daemon.sh
	start_git_daemon --export-all --enable=receive-pack
	T5370_PARENT="$GIT_DAEMON_DOCUMENT_ROOT_PATH/parent"
	T5370_URI="$GIT_DAEMON_URL/parent"
	T5370_BUNDLE_URI="https://example.com/fake.bdl"
	;;
http)
	. "$TEST_DIRECTORY"/lib-httpd.shp
	start_httpd
	T5370_PARENT="$HTTPD_DOCUMENT_ROOT_PATH/http_parent"
	t5370_URI="$HTTPD_URL/smart/http_parent"
	;;
*)
	BUG "Need to pass valid T5370_PROTOCOL (was $T5370_PROTOCOL)"
	;;
esac

test_expect_success "setup protocol v2 $T5370_PROTOCOL:// tests" '
	git init "$T5370_PARENT" &&
	test_commit -C "$T5370_PARENT" initial
'


case "$T5370_PROTOCOL" in
http)
	test_expect_success "setup config for $T5370_PROTOCOL:// tests" '
		git -C "T5370_PARENT" config http.receivepack true
	'
	;;
*)
	;;
esac
T5370_BUNDLE_URI_ESCAPED=$(echo "$T5370_BUNDLE_URI" | sed 's/ /%20/g')

test_expect_success "connect with $T5730_PROTOCOL:// using protocol v2: no bundle-uri" '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$PWD/log" \
	git \
		-c protocol.version=2 \
		ls-remote --symref "$T5370_URI" \
		>actual 2>err &&

	# Server responded using protocol v2
	grep "ls-remote< version 2" log &&

	! grep bundle-uri log
'

test_expect_success "connect with $T5730_PROTOCOL:// using protocol v2: have bundle-uri" '
	test_when_finished "rm -f log" &&

	test_config -C "$T5370_PARENT" \
		uploadpack.bundleURI "$T5370_BUNDLE_URI_ESCAPED" &&

	GIT_TRACE_PACKET="$PWD/log" \
	git \
		-c protocol.version=2 \
		ls-remote --symref "$T5370_URI" \
		>actual 2>err &&

	# Server responded using protocol v2
	grep "ls-remote< version 2" log &&

	# Server advertised bundle-uri capability
	grep bundle-uri log
'

test_expect_success "bad client with $T5730_PROTOCOL:// using protocol v2" '
	test_when_finished "rm -f log" &&

	test_config -C "$T5370_PARENT" uploadpack.bundleURI \
		"$T5370_BUNDLE_URI_ESCAPED" &&

	cat >err.expect <<-\EOF &&
	Cloning into '"'"'child'"'"'...
	fatal: remote error: bundle-uri: unexpected argument: '"'"'test-bad-client'"'"'
	EOF
	test_must_fail env \
		GIT_TRACE_PACKET="$PWD/log" \
		GIT_TEST_PROTOCOL_BAD_BUNDLE_URI=true \
		git -c protocol.version=2 \
		clone "$T5370_URI" child \
		>out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual &&

	grep "clone> test-bad-client$" log >sent-bad-request &&
	test_file_not_empty sent-bad-request
'
