#!/bin/sh

test_description='errors in upload-pack'

. ./test-lib.sh

D=$(pwd)

corrupt_repo () {
	object_sha1=$(git rev-parse "$1") &&
	ob=$(expr "$object_sha1" : "\(..\)") &&
	ject=$(expr "$object_sha1" : "..\(..*\)") &&
	rm -f ".git/objects/$ob/$ject"
}

test_expect_success 'setup and corrupt repository' '
	echo file >file &&
	git add file &&
	git rev-parse :file &&
	git commit -a -m original &&
	test_tick &&
	echo changed >file &&
	git commit -a -m changed &&
	corrupt_repo HEAD:file

'

test_expect_success 'fsck fails' '
	test_must_fail git fsck
'

test_expect_success 'upload-pack fails due to error in pack-objects packing' '
	head=$(git rev-parse HEAD) &&
	hexsz=$(test_oid hexsz) &&
	printf "%04xwant %s\n00000009done\n0000" \
		$(($hexsz + 10)) $head >input &&
	test_must_fail git upload-pack . <input >/dev/null 2>output.err &&
	test_i18ngrep "unable to read" output.err &&
	test_i18ngrep "pack-objects died" output.err
'

test_expect_success 'corrupt repo differently' '

	git hash-object -w file &&
	corrupt_repo HEAD^^{tree}

'

test_expect_success 'fsck fails' '
	test_must_fail git fsck
'
test_expect_success 'upload-pack fails due to error in rev-list' '

	printf "%04xwant %s\n%04xshallow %s00000009done\n0000" \
		$(($hexsz + 10)) $(git rev-parse HEAD) \
		$(($hexsz + 12)) $(git rev-parse HEAD^) >input &&
	test_must_fail git upload-pack . <input >/dev/null 2>output.err &&
	grep "bad tree object" output.err
'

test_expect_success 'upload-pack fails due to bad want (no object)' '
	cat >expect <<-EOF &&
	$(git rev-parse HEAD) HEAD
	$(git rev-parse HEAD) refs/heads/master
	0000
	ERR upload-pack: not our ref $(test_oid deadbeef)
	EOF

	cat >expect.err <<-EOF &&
	fatal: git upload-pack: not our ref $(test_oid deadbeef)
	EOF

	printf "%04xwant %s multi_ack_detailed\n00000009done\n0000" \
		$(($hexsz + 29)) $(test_oid deadbeef) >input &&
	test_must_fail git upload-pack . <input >output 2>output.err &&
	test-tool pkt-line unpack <output >actual &&
	test_cmp expect actual &&
	test_cmp expect.err output.err
'

test_expect_success 'upload-pack fails due to bad want (not tip)' '
	oid=$(echo an object we have | git hash-object -w --stdin) &&

	cat >expect <<-EOF &&
	$(git rev-parse HEAD) HEAD
	$(git rev-parse HEAD) refs/heads/master
	0000
	ERR upload-pack: not our ref $oid
	EOF

	cat >expect.err <<-EOF &&
	fatal: git upload-pack: not our ref $oid
	EOF

	printf "%04xwant %s multi_ack_detailed\n00000009done\n0000" \
		$(($hexsz + 29)) "$oid" >input &&
	test_must_fail git upload-pack . <input >output 2>output.err &&
	test-tool pkt-line unpack <output >actual &&
	test_cmp expect actual &&
	test_cmp expect.err output.err
'

test_expect_success 'upload-pack fails due to error in pack-objects enumeration' '

	printf "%04xwant %s\n00000009done\n0000" \
		$((hexsz + 10)) $(git rev-parse HEAD) >input &&
	test_must_fail git upload-pack . <input >/dev/null 2>output.err &&
	grep "bad tree object" output.err &&
	grep "pack-objects died" output.err
'

test_expect_success 'upload-pack tolerates EOF just after stateless client wants' '
	test_commit initial &&

	head=$(git rev-parse HEAD) &&
	test-tool pkt-line pack >request <<-EOF &&
	want $head
	shallow $head
	deepen 1
	0000
	EOF

	cat >expect <<-\EOF &&
	0000
	EOF
	git upload-pack --stateless-rpc . <request >out &&
	test-tool pkt-line unpack <out >actual &&
	test_cmp expect actual
'

test_expect_success 'create empty repository' '

	mkdir foo &&
	cd foo &&
	git init

'

test_expect_success 'fetch fails' '

	test_must_fail git fetch .. main

'

test_done
