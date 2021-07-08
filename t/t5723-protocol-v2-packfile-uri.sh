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

test_expect_success 'part of packfile response provided as URI' '
	P="$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	rm -rf "$P" http_child log &&

	git init "$P" &&
	git -C "$P" config "uploadpack.allowsidebandall" "true" &&

	echo my-blob >"$P/my-blob" &&
	git -C "$P" add my-blob &&
	echo other-blob >"$P/other-blob" &&
	git -C "$P" add other-blob &&
	git -C "$P" commit -m x &&

	configure_exclusion "$P" my-blob >h &&
	configure_exclusion "$P" other-blob >h2 &&

	GIT_TRACE=1 GIT_TRACE_PACKET="$(pwd)/log" GIT_TEST_SIDEBAND_ALL=1 \
	git -c protocol.version=2 \
		-c fetch.uriprotocols=http,https \
		clone "$HTTPD_URL/smart/http_parent" http_child &&

	# Ensure that my-blob and other-blob are in separate packfiles.
	for idx in http_child/.git/objects/pack/*.idx
	do
		git verify-pack --object-format=$(test_oid algo) --verbose $idx >out &&
		{
			grep "^[0-9a-f]\{16,\} " out || :
		} >out.objectlist &&
		if test_line_count = 1 out.objectlist
		then
			if grep $(cat h) out
			then
				>hfound
			fi &&
			if grep $(cat h2) out
			then
				>h2found
			fi
		fi
	done &&
	test -f hfound &&
	test -f h2found &&

	# Ensure that there are exactly 3 packfiles with associated .idx
	ls http_child/.git/objects/pack/*.pack \
	    http_child/.git/objects/pack/*.idx >filelist &&
	test_line_count = 6 filelist
'

test_expect_success 'packfile URIs with fetch instead of clone' '
	P="$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	rm -rf "$P" http_child log &&

	git init "$P" &&
	git -C "$P" config "uploadpack.allowsidebandall" "true" &&

	echo my-blob >"$P/my-blob" &&
	git -C "$P" add my-blob &&
	git -C "$P" commit -m x &&

	configure_exclusion "$P" my-blob >h &&

	git init http_child &&

	GIT_TEST_SIDEBAND_ALL=1 \
	git -C http_child -c protocol.version=2 \
		-c fetch.uriprotocols=http,https \
		fetch "$HTTPD_URL/smart/http_parent"
'

test_expect_success 'fetching with valid packfile URI but invalid hash fails' '
	P="$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	rm -rf "$P" http_child log &&

	git init "$P" &&
	git -C "$P" config "uploadpack.allowsidebandall" "true" &&

	echo my-blob >"$P/my-blob" &&
	git -C "$P" add my-blob &&
	echo other-blob >"$P/other-blob" &&
	git -C "$P" add other-blob &&
	git -C "$P" commit -m x &&

	configure_exclusion "$P" my-blob >h &&
	# Configure a URL for other-blob. Just reuse the hash of the object as
	# the hash of the packfile, since the hash does not matter for this
	# test as long as it is not the hash of the pack, and it is of the
	# expected length.
	git -C "$P" hash-object other-blob >objh &&
	git -C "$P" pack-objects "$HTTPD_DOCUMENT_ROOT_PATH/mypack" <objh >packh &&
	pack_uri="$HTTPD_URL/dumb/mypack-$(cat packh).pack" &&
	exp_hash="$(cat objh)" &&
	git -C "$P" config --add \
		"uploadpack.blobpackfileuri" \
		"$exp_hash $exp_hash $pack_uri" &&

	cat >err.expect <<-EOF &&
	Cloning into '"'"'http_child'"'"'...
	fatal: fetch-pack: pack downloaded from $pack_uri does not match expected hash $exp_hash
	EOF
	test_must_fail env GIT_TEST_SIDEBAND_ALL=1 \
		git -c protocol.version=2 \
		-c fetch.uriprotocols=http,https \
		clone "$HTTPD_URL/smart/http_parent" http_child >out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual
'

test_expect_success 'packfile-uri with transfer.fsckobjects' '
	P="$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	rm -rf "$P" http_child log &&

	git init "$P" &&
	git -C "$P" config "uploadpack.allowsidebandall" "true" &&

	echo my-blob >"$P/my-blob" &&
	git -C "$P" add my-blob &&
	git -C "$P" commit -m x &&

	configure_exclusion "$P" my-blob >h &&

	sane_unset GIT_TEST_SIDEBAND_ALL &&
	git -c protocol.version=2 -c transfer.fsckobjects=1 \
		-c fetch.uriprotocols=http,https \
		clone "$HTTPD_URL/smart/http_parent" http_child &&

	# Ensure that there are exactly 2 packfiles with associated .idx
	ls http_child/.git/objects/pack/*.pack \
	    http_child/.git/objects/pack/*.idx >filelist &&
	test_line_count = 4 filelist
'

test_expect_success 'packfile-uri with transfer.fsckobjects fails on bad object' '
	P="$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	rm -rf "$P" http_child log &&

	git init "$P" &&
	git -C "$P" config "uploadpack.allowsidebandall" "true" &&

	cat >bogus-commit <<-EOF &&
	tree $EMPTY_TREE
	author Bugs Bunny 1234567890 +0000
	committer Bugs Bunny <bugs@bun.ni> 1234567890 +0000

	This commit object intentionally broken
	EOF
	BOGUS=$(git -C "$P" hash-object -t commit -w --stdin <bogus-commit) &&
	git -C "$P" branch bogus-branch "$BOGUS" &&

	echo my-blob >"$P/my-blob" &&
	git -C "$P" add my-blob &&
	git -C "$P" commit -m x &&

	configure_exclusion "$P" my-blob >h &&

	sane_unset GIT_TEST_SIDEBAND_ALL &&

	cat >err.expect <<-EOF &&
	Cloning into '"'"'http_child'"'"'...
	error: object $BOGUS: missingEmail: invalid author/committer line - missing email
	fatal: fsck error in packed object
	fatal: fetch-pack: invalid index-pack output
	EOF
	test_must_fail git -c protocol.version=2 -c transfer.fsckobjects=1 \
		-c fetch.uriprotocols=http,https \
		clone "$HTTPD_URL/smart/http_parent" http_child >out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual
'

test_done
