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

test_expect_success "ls-remote-bundle-uri with $T5730_PROTOCOL:// using protocol v2" '
	test_config -C "$T5370_PARENT" uploadpack.bundleURI \
		"$T5370_BUNDLE_URI_ESCAPED" &&

	# All data about bundle URIs
	cat >expect <<-EOF &&
	$T5370_BUNDLE_URI_ESCAPED
	EOF
	git \
		-c protocol.version=2 \
		ls-remote-bundle-uri \
		"$T5370_URI" \
		>actual &&
	test_cmp expect actual &&

	# Only the URIs
	git \
		-c protocol.version=2 \
		ls-remote-bundle-uri --uri \
		"$T5370_URI" \
		>actual2 &&
	test_cmp actual actual2
'

test_expect_success "ls-remote-bundle-uri with $T5730_PROTOCOL:// using protocol v2" '
	ATTR="foo bar=baz" &&
	test_config -C "$T5370_PARENT" uploadpack.bundleURI \
		"$T5370_BUNDLE_URI_ESCAPED $ATTR" &&

	# All data about bundle URIs
	cat >expect <<-EOF &&
	$T5370_BUNDLE_URI_ESCAPED $ATTR
	EOF
	git \
		-c protocol.version=2 \
		ls-remote-bundle-uri \
		"$T5370_URI" \
		>actual &&
	test_cmp expect actual
'

test_expect_success "ls-remote-bundle-uri with $T5730_PROTOCOL:// using protocol v2: --uri" '
	ATTR="foo bar=baz" &&
	test_config -C "$T5370_PARENT" uploadpack.bundleURI \
		"$T5370_BUNDLE_URI_ESCAPED $ATTR" &&

	# All data about bundle URIs
	cat >expect <<-EOF &&
	$T5370_BUNDLE_URI_ESCAPED
	EOF
	git \
		-c protocol.version=2 \
		ls-remote-bundle-uri \
		--uri \
		"$T5370_URI" \
		>actual &&
	test_cmp expect actual
'

test_expect_success "ls-remote-bundle-uri --[no-]quiet with $T5730_PROTOCOL:// using protocol v2" '
	test_config -C "$T5370_PARENT" uploadpack.bundleURI \
		"$T5370_BUNDLE_URI_ESCAPED" &&

	cat >err.expect <<-\EOF &&
	Cloning into '"'"'child'"'"'...
	EOF
	git \
		-c protocol.version=2 \
		 clone "$T5370_URI" child \
		 >out 2>err.actual &&
	test_cmp err.expect err.actual &&
	test_must_be_empty out &&

	# Without --[no-]quiet
	cat >out.expect <<-EOF &&
	$T5370_BUNDLE_URI_ESCAPED
	EOF
	cat >err.expect <<-EOF &&
	From $T5370_URI
	EOF
	git \
		-C child \
		 -c protocol.version=2 \
		ls-remote-bundle-uri \
		>out.actual 2>err.actual &&
	test_cmp err.expect err.actual &&
	test_cmp out.expect out.actual &&

	# --no-quiet is the default
	git \
		-C child \
		-c protocol.version=2 \
		ls-remote-bundle-uri \
		--no-quiet \
		>out.actual 2>err.actual &&
	test_cmp err.expect err.actual &&
	test_cmp out.expect out.actual &&

	# --quiet quiets the "From" line
	git \
		-C child \
		-c protocol.version=2 \
		ls-remote-bundle-uri \
		--quiet \
		>out.actual 2>err &&
	test_must_be_empty err &&
	test_cmp out.expect out.actual &&

	# --quiet is implicit if the remote is not implicit
	git \
		-c protocol.version=2 \
		ls-remote-bundle-uri \
		"$T5370_URI" \
		>out.actual 2>err &&
	test_must_be_empty err &&
	test_cmp out.expect out.actual
'

test_expect_success "ls-remote-bundle-uri with -c transfer.injectBundleURI using with $T5730_PROTOCOL:// using protocol v2" '
	test_when_finished "rm -f log" &&

	test_config -C "$T5370_PARENT" uploadpack.bundleURI \
		"$T5370_BUNDLE_URI_ESCAPED" &&

	cat >expect <<-\EOF &&
	https://injected.example.com/fake-1.bdl
	https://injected.example.com/fake-2.bdl
	EOF
	GIT_TRACE_PACKET="$PWD/log" \
	git \
		-c protocol.version=2 \
		-c transfer.injectBundleURI="https://injected.example.com/fake-1.bdl" \
		-c transfer.injectBundleURI="https://injected.example.com/fake-2.bdl" \
		ls-remote-bundle-uri \
		"$T5370_URI" \
		>actual 2>err &&
	test_cmp expect actual &&
	test_path_is_missing log
'

test_expect_success "ls-remote-bundle-uri with bad -c transfer.injectBundleURI protocol v2 with $T5730_PROTOCOL://" '
	test_when_finished "rm -f log" &&

	test_config -C "$T5370_PARENT" uploadpack.bundleURI \
		"$T5370_BUNDLE_URI_ESCAPED" &&

	cat >err.expect <<-\EOF &&
	error: bad (empty) transfer.injectBundleURI
	error: could not get the bundle-uri list
	EOF

	test_must_fail env \
		GIT_TRACE_PACKET="$PWD/log" \
		git \
		-c protocol.version=2 \
		-c transfer.injectBundleURI \
		ls-remote-bundle-uri \
		"$T5370_URI" \
		>out 2>err.actual &&
	test_must_be_empty out &&
	test_cmp err.expect err.actual &&
	test_path_is_missing log
	
'
