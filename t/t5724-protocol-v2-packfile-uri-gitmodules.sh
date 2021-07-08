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

test_expect_success 'packfile-uri with transfer.fsckobjects .gitmodules multiple sections' '
	P="$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	test_when_finished "rm -rf \"$P\" http_clone" &&

	git init "$P" &&
	git -C "$P" config "uploadpack.AllowsSidebandAll" "true" &&

	cat >"$P/.gitmodules" <<-EOF &&
	[submodule ".."]
	path = include/foo
	url = git://example.com/git/one.git

	[submodule "../"]
	path = include/bar
	url = git://example.com/git/two.git

	[submodule ".."]
	path = include/baz
	url = git://example.com/git/three.git
	EOF

	git -C "$P" add .gitmodules &&
	git -C "$P" commit -m x &&

	bad_oid=$(configure_exclusion "$P" .gitmodules) &&

	cat >err.expect <<-EOF &&
	Cloning into '"'"'http_clone'"'"'...
	error: object $bad_oid: gitmodulesName: disallowed submodule name: ..
	error: object $bad_oid: gitmodulesName: disallowed submodule name: ..
	error: object $bad_oid: gitmodulesName: disallowed submodule name: ../
	error: object $bad_oid: gitmodulesName: disallowed submodule name: ../
	error: object $bad_oid: gitmodulesName: disallowed submodule name: ..
	error: object $bad_oid: gitmodulesName: disallowed submodule name: ..
	fatal: fsck error in packed object
	fatal: fetch-pack: invalid index-pack output
	EOF
	sane_unset GIT_TEST_SIDEBAND_ALL &&
	test_must_fail git \
		-c protocol.version=2 \
		-c transfer.fsckobjects=true \
		-c fetch.uriprotocols=http,https \
		clone "$HTTPD_URL/smart/http_parent" http_clone \
		>out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual
'

test_expect_success 'packfile-uri with transfer.fsckobjects .gitmodules in history' '
	P="$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	test_when_finished "rm -rf \"$P\" http_clone" &&

	git init "$P" &&
	git -C "$P" config "uploadpack.AllowsSidebandAll" "true" &&

	cat >"$P/.gitmodules" <<-EOF &&
	[submodule ".."]
	path = include/foo
	url = git://example.com/git/one.git
	EOF

	git -C "$P" add .gitmodules &&
	git -C "$P" commit -m x &&

	bad_oid=$(configure_exclusion "$P" .gitmodules) &&

	git -C "$P" rm .gitmodules &&
	git -C "$P" commit -m y &&

	cat >err.expect <<-EOF &&
	Cloning into '"'"'http_clone'"'"'...
	error: object $bad_oid: gitmodulesName: disallowed submodule name: ..
	error: object $bad_oid: gitmodulesName: disallowed submodule name: ..
	fatal: fsck error in packed object
	fatal: fetch-pack: invalid index-pack output
	EOF
	sane_unset GIT_TEST_SIDEBAND_ALL &&
	test_must_fail git \
		-c protocol.version=2 \
		-c transfer.fsckobjects=true \
		-c fetch.uriprotocols=http,https \
		clone "$HTTPD_URL/smart/http_parent" http_clone \
		>out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual
'

test_expect_success 'packfile-uri with transfer.fsckobjects .gitmodules multiple branches' '
	P="$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	test_when_finished "rm -rf \"$P\" http_clone" &&

	git init "$P" &&
	git -C "$P" config "uploadpack.AllowsSidebandAll" "true" &&

	cat >"$P/.gitmodules" <<-EOF &&
	[submodule ".."]
	path = include/foo
	url = git://example.com/git/lib.git

	[submodule ".."]
	path = include/bar
	url = git://example.com/git/lib.git
	EOF

	git -C "$P" add .gitmodules &&
	git -C "$P" commit -m x &&

	bad_one=$(configure_exclusion "$P" .gitmodules) &&

	cat >"$P/.gitmodules" <<-EOF &&
	[submodule "../"]
	path = include/baz
	url = git://example.com/git/lib.git
	EOF

	git -C "$P" checkout -b topic &&
	git -C "$P" add .gitmodules &&
	git -C "$P" commit -m y &&

	bad_two=$(configure_exclusion "$P" .gitmodules) &&

	# Our fsck should report them all
	sort >err.expect.all <<-EOF &&
	error in blob $bad_two: gitmodulesName: disallowed submodule name: ../
	error in blob $bad_two: gitmodulesName: disallowed submodule name: ../
	error in blob $bad_one: gitmodulesName: disallowed submodule name: ..
	error in blob $bad_one: gitmodulesName: disallowed submodule name: ..
	error in blob $bad_one: gitmodulesName: disallowed submodule name: ..
	error in blob $bad_one: gitmodulesName: disallowed submodule name: ..
	EOF
	test_must_fail git -C "$P" fsck >out 2>err.actual &&
	sort err.actual >err.actual.sorted &&
	test_cmp err.expect.all err.actual.sorted &&

	# Oddities in index-pack walking only fsck_blob() some
	# objects. We only report the branch that is checked out?
	cat >err.expect.two <<-EOF &&
	Cloning into '"'"'http_clone'"'"'...
	error: object $bad_two: gitmodulesName: disallowed submodule name: ../
	error: object $bad_two: gitmodulesName: disallowed submodule name: ../
	fatal: fsck error in packed object
	fatal: fetch-pack: invalid index-pack output
	EOF
	sane_unset GIT_TEST_SIDEBAND_ALL &&
	test_must_fail git \
		-c protocol.version=2 \
		-c transfer.fsckobjects=true \
		-c fetch.uriprotocols=http,https \
		clone "$HTTPD_URL/smart/http_parent" http_clone \
		>out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect.two err.actual &&

	# Try again, but with the "main" branch checked out. Now
	# errors on different commits
	rm -rf http_clone &&
	git -C "$P" checkout - &&

	cat >err.expect.one <<-EOF &&
	Cloning into '"'"'http_clone'"'"'...
	error: object $bad_one: gitmodulesName: disallowed submodule name: ..
	error: object $bad_one: gitmodulesName: disallowed submodule name: ..
	error: object $bad_one: gitmodulesName: disallowed submodule name: ..
	error: object $bad_one: gitmodulesName: disallowed submodule name: ..
	fatal: fsck error in packed object
	fatal: fetch-pack: invalid index-pack output
	EOF
	sane_unset GIT_TEST_SIDEBAND_ALL &&
	test_must_fail git \
		-c protocol.version=2 \
		-c transfer.fsckobjects=true \
		-c fetch.uriprotocols=http,https \
		clone "$HTTPD_URL/smart/http_parent" http_clone \
		>out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect.one err.actual &&

	# Checking out a third branch does not silence the errors
	rm -rf http_clone &&
	git -C "$P" checkout --orphan no-gitmodules &&
	git -C "$P" reset &&
	test_commit -C "$P" file &&

	test_must_fail git \
		-c protocol.version=2 \
		-c transfer.fsckobjects=true \
		-c fetch.uriprotocols=http,https \
		clone "$HTTPD_URL/smart/http_parent" http_clone \
		>out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect.one err.actual &&

	# Cloning with a skipList of "$bad_one" will make us
	# look harder and report errors in "$bad_two" instead...
	cat >err.expect.three <<-EOF &&
	Cloning into '"'"'http_clone'"'"'...
	error: object $bad_two: gitmodulesName: disallowed submodule name: ../
	error: object $bad_two: gitmodulesName: disallowed submodule name: ../
	EOF
	if test_have_prereq SHA1
	then
		cat >>err.expect.three <<-EOF
		fatal: fsck error in packed object
		fatal: fetch-pack: invalid index-pack output
		EOF
	else
		cat >>err.expect.three <<-EOF
		fatal: fsck error in pack objects
		fatal: index-pack failed
		EOF
	fi &&
	echo $bad_one >skipList &&
	sane_unset GIT_TEST_SIDEBAND_ALL &&
	test_must_fail git \
		-c protocol.version=2 \
		-c transfer.fsckobjects=true \
		-c fetch.fsck.skipList=skipList \
		-c fetch.uriprotocols=http,https \
		clone "$HTTPD_URL/smart/http_parent" http_clone \
		>out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect.three err.actual &&

	# ..and "$bad_two" to that skipList will make the clone
	# succeed
	echo $bad_two >>skipList &&
	cat >err.expect.skipList <<-EOF &&
	Cloning into '"'"'http_clone'"'"'...
	EOF
	sane_unset GIT_TEST_SIDEBAND_ALL &&
	git \
		-c protocol.version=2 \
		-c transfer.fsckobjects=true \
		-c fetch.fsck.skipList=skipList \
		-c fetch.uriprotocols=http,https \
		clone "$HTTPD_URL/smart/http_parent" http_clone \
		>out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect.skipList err.actual &&

	# ...and an fsck of that bad cloned repo is the same as the parent
	test_must_fail git -C http_clone fsck >out 2>err.actual &&
	sort err.actual >err.actual.sorted &&
	test_cmp err.expect.all err.actual.sorted
'

test_done
