#!/bin/sh

test_description='Test the packfile-uri protocol v2 extension'

. ./test-lib.sh
. "$TEST_DIRECTORY"/lib-httpd.sh
start_httpd

configure_exclusion () {
	git -C "$1" hash-object "$2" >objh &&
	git -C "$1" pack-objects "$HTTPD_DOCUMENT_ROOT_PATH/mypack" <objh >packh &&
	git -C "$1" config --add \
		"uploadpack.blobpackfileuri" \
		"$(cat objh) $(cat packh) $HTTPD_URL/dumb/mypack-$(cat packh).pack" &&
	cat objh
}

test_expect_success 'packfile-uri with transfer.fsckobjects succeeds when .gitmodules is separate from tree' '
	P="$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	rm -rf "$P" http_child &&

	git init "$P" &&
	git -C "$P" config "uploadpack.allowsidebandall" "true" &&

	echo "[submodule libfoo]" >"$P/.gitmodules" &&
	echo "path = include/foo" >>"$P/.gitmodules" &&
	echo "url = git://example.com/git/lib.git" >>"$P/.gitmodules" &&
	git -C "$P" add .gitmodules &&
	git -C "$P" commit -m x &&

	configure_exclusion "$P" .gitmodules >h &&

	sane_unset GIT_TEST_SIDEBAND_ALL &&
	git -c protocol.version=2 -c transfer.fsckobjects=1 \
		-c fetch.uriprotocols=http,https \
		clone "$HTTPD_URL/smart/http_parent" http_child &&

	# Ensure that there are exactly 2 packfiles with associated .idx
	ls http_child/.git/objects/pack/*.pack \
	    http_child/.git/objects/pack/*.idx >filelist &&
	test_line_count = 4 filelist
'

test_expect_success 'packfile-uri with transfer.fsckobjects fails when .gitmodules separate from tree is invalid' '
	P="$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	rm -rf "$P" http_child err &&

	test_when_finished "rm -rf \"$P\"" &&
	git init "$P" &&
	git -C "$P" config "uploadpack.allowsidebandall" "true" &&

	echo "[submodule \"..\"]" >"$P/.gitmodules" &&
	echo "path = include/foo" >>"$P/.gitmodules" &&
	echo "url = git://example.com/git/lib.git" >>"$P/.gitmodules" &&
	git -C "$P" add .gitmodules &&
	git -C "$P" commit -m x &&

	bad_oid=$(configure_exclusion "$P" .gitmodules) &&

	cat >err.expect <<-EOF &&
	Cloning into '"'"'http_child'"'"'...
	error: object $bad_oid: gitmodulesName: disallowed submodule name: ..
	error: object $bad_oid: gitmodulesName: disallowed submodule name: ..
	fatal: fsck failed
	EOF
	sane_unset GIT_TEST_SIDEBAND_ALL &&
	test_must_fail git -c protocol.version=2 -c transfer.fsckobjects=1 \
		-c fetch.uriprotocols=http,https \
		clone "$HTTPD_URL/smart/http_parent" http_child >out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual
'

test_done
