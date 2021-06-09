#!/bin/sh

test_description='some bundle related tests'
GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME=main
export GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME

. ./test-lib.sh

test_expect_success 'setup' '
	test_oid_cache <<-EOF &&
	version sha1:2
	version sha256:3
	EOF
	test_commit initial &&
	test_tick &&
	git tag -m tag tag &&
	test_commit second &&
	test_commit third &&
	git tag -d initial &&
	git tag -d second &&
	git tag -d third
'

test_expect_success '"verify" needs a worktree' '
	git bundle create tip.bundle -1 main &&
	nongit test_must_fail git bundle verify ../tip.bundle 2>err &&
	test_i18ngrep "need a repository" err
'

test_expect_success 'annotated tags can be excluded by rev-list options' '
	git bundle create bundle --all --since=7.Apr.2005.15:14:00.-0700 &&
	cat >expect <<-EOF &&
	$(git rev-parse HEAD)	HEAD
	$(git rev-parse tag)	refs/tags/tag
	$(git rev-parse main)	refs/heads/main
	EOF
	git ls-remote bundle >actual &&
	test_cmp expect actual &&

	git bundle create bundle --all --since=7.Apr.2005.15:16:00.-0700 &&
	cat >expect <<-EOF &&
	$(git rev-parse HEAD)	HEAD
	$(git rev-parse main)	refs/heads/main
	EOF
	git ls-remote bundle >actual &&
	test_cmp expect actual
'

test_expect_success 'die if bundle file cannot be created' '
	mkdir adir &&
	test_must_fail git bundle create adir --all
'

test_expect_success 'bundle --stdin' '
	echo main | git bundle create stdin-bundle.bdl --stdin &&
	cat >expect <<-EOF &&
	$(git rev-parse main)	refs/heads/main
	EOF
	git ls-remote stdin-bundle.bdl >actual &&
	test_cmp expect actual
'

test_expect_success 'bundle --stdin <rev-list options>' '
	echo main | git bundle create hybrid-bundle.bdl --stdin tag &&
	cat >expect <<-EOF &&
	$(git rev-parse main)	refs/heads/main
	EOF
	git ls-remote stdin-bundle.bdl >actual &&
	test_cmp expect actual
'

# --stdin tabular input
test_expect_success 'bundle --stdin understands tabular-like output' '
	test_must_fail git rev-parse refs/heads/second &&

	cat >in <<-EOF &&
	$(git rev-parse :/initial)	refs/heads/initial
	EOF
	git bundle create initial.bdl --stdin <in &&
	cat >expect <<-EOF &&
	$(git rev-parse :/initial)	refs/heads/initial
	EOF
	git ls-remote initial.bdl >actual &&
	test_cmp expect actual
'

test_expect_success 'bundle --stdin mixed rev-list and tabular input' '
	cat >in <<-EOF &&
	$(git rev-parse :/initial)	refs/heads/initial
	main
	EOF
	git bundle create mixed.bdl --stdin <in &&

	cat >expect <<-EOF &&
	$(git rev-parse main)	refs/heads/main
	$(git rev-parse :/initial)	refs/heads/initial
	EOF
	git ls-remote mixed.bdl >actual &&
	test_cmp expect actual
'

# --stdin tabular input rev validation
test_expect_success 'bundle --stdin tabular input requires valid revisions' '
	cat >in <<-EOF &&
	$(test_oid deadbeef)	refs/heads/deadbeef
	EOF
	cat >expect <<-EOF &&
	fatal: bad object $(test_oid deadbeef)
	EOF
	test_must_fail git bundle create err.bdl --stdin <in 2>actual &&
	test_cmp expect actual &&
	test_path_is_missing err.bdl
'

# --stdin tabular input ref validation
test_expect_success 'bundle --stdin tabular input accepts one-level ref names' '
	cat >in <<-EOF &&
	$(git rev-parse HEAD)	HEAD
	$(git rev-parse :/initial)	initial
	EOF
	git bundle create one-level.bdl --stdin <in &&

	cat >expect <<-EOF &&
	$(git rev-parse :/initial)	initial
	$(git rev-parse HEAD)	HEAD
	EOF
	git ls-remote one-level.bdl >actual &&
	test_cmp expect actual
'

test_expect_success 'bundle --stdin tabular input requires valid refs' '
	cat >in <<-EOF &&
	$(git rev-parse :/second)	bad:ref:name
	EOF
	cat >expect <<-\EOF &&
	fatal: '"'"'bad:ref:name'"'"' is not a valid ref name
	EOF
	test_must_fail git bundle create err.bdl --stdin <in 2>actual &&
	test_cmp expect actual &&
	test_path_is_missing err.bdl
'

# --stdin tabular input parsing
test_expect_success 'bundle --stdin tabular input refuses extra fields' '
	cat >in <<-EOF &&
	$(git rev-parse :/initial)	refs/heads/a-branch	unknown-field
	EOF
	cat >expect <<-\EOF &&
	fatal: '"'"'refs/heads/a-branch	'"'"' is not a valid ref name
	EOF
	test_must_fail git bundle create err.bdl --stdin <in 2>actual &&
	test_cmp expect actual &&
	test_path_is_missing err.bdl
'

test_expect_success 'bundle --stdin tabular input refuses trailing tab' '
	sed "s/Z$//" >in <<-EOF &&
	$(git rev-parse :/initial)	refs/heads/a-branch	Z
	EOF
	cat >expect <<-\EOF &&
	fatal: '"'"'refs/heads/a-branch	'"'"' is not a valid ref name
	EOF
	test_must_fail git bundle create err.bdl --stdin <in 2>actual &&
	test_cmp expect actual &&
	test_path_is_missing err.bdl
'

test_expect_success 'bundle --stdin tabular input refuses empty field' '
	sed "s/Z$//" >in <<-EOF &&
	$(git rev-parse :/initial)		refs/heads/a-branch
	EOF
	cat >expect <<-\EOF &&
	fatal: '"'"'	'"'"' is not a valid ref name
	EOF
	test_must_fail git bundle create err.bdl --stdin <in 2>actual &&
	test_cmp expect actual &&
	test_path_is_missing err.bdl
'

# --stdin tabular input show-ref incompatibility
test_expect_success 'bundle --stdin tabular input is incompatible with "git show-ref"' '
	git show-ref >sr &&

	cat >expect <<-EOF &&
	fatal: bad revision '"'"'$(git rev-parse main) refs/heads/main'"'"'
	EOF
	test_must_fail git bundle create err.bdl --stdin <sr 2>actual &&
	test_cmp expect actual &&
	test_path_is_missing err.bdl
'

# --stdin tabular input for-each-ref compatibility
test_expect_success 'bundle --stdin tabular input is compatible with "git for-each-ref"' '
	git for-each-ref >fer &&
	git bundle create all.bdl --stdin <fer &&

	cat >expect <<-EOF &&
	$(git rev-parse main) refs/heads/main
	$(git rev-parse tag) refs/tags/tag
	EOF

	git bundle list-heads all.bdl >actual &&
	test_cmp expect actual
'

# --stdin tabular input for-each-ref parsing
test_expect_success 'bundle --stdin tabular "git for-each-ref" input ignores types' '
	git for-each-ref >fer &&
	cat fer &&
	sed -e "s/commit/blob/" -e "s/tag/commit/" <fer >fake-fer &&
	git bundle create all.bdl --stdin <fake-fer &&

	cat >expect <<-EOF &&
	$(git rev-parse main) refs/heads/main
	$(git rev-parse tag) refs/tags/tag
	EOF

	git bundle list-heads all.bdl >actual &&
	test_cmp expect actual
'

test_expect_success 'empty bundle file is rejected' '
	: >empty-bundle &&
	test_must_fail git fetch empty-bundle
'

# This triggers a bug in older versions where the resulting line (with
# --pretty=oneline) was longer than a 1024-char buffer.
test_expect_success 'ridiculously long subject in boundary' '
	: >file4 &&
	test_tick &&
	git add file4 &&
	printf "%01200d\n" 0 | git commit -F - &&
	test_commit fifth &&
	git bundle create long-subject-bundle.bdl HEAD^..HEAD &&

	cat >expect <<-EOF &&
	$(git rev-parse main) HEAD
	EOF
	git bundle list-heads long-subject-bundle.bdl >actual &&
	test_cmp expect actual &&

	git fetch long-subject-bundle.bdl &&
	sed -n "/^-/{p;q;}" long-subject-bundle.bdl >boundary &&
	grep "^-$OID_REGEX " boundary
'

test_expect_success 'prerequisites with an empty commit message' '
	: >file1 &&
	git add file1 &&
	test_tick &&
	git commit --allow-empty-message -m "" &&
	test_commit file2 &&
	git bundle create bundle HEAD^.. &&
	git bundle verify bundle
'

test_expect_success 'failed bundle creation does not leave cruft' '
	# This fails because the bundle would be empty.
	test_must_fail git bundle create fail.bundle main..main &&
	test_path_is_missing fail.bundle.lock
'

test_expect_success 'fetch SHA-1 from bundle' '
	test_create_repo foo &&
	test_commit -C foo x &&
	git -C foo bundle create tip.bundle -1 main &&
	git -C foo rev-parse HEAD >hash &&

	# Exercise to ensure that fetching a SHA-1 from a bundle works with no
	# errors
	git fetch --no-tags foo/tip.bundle "$(cat hash)"
'

test_expect_success 'git bundle uses expected default format' '
	git bundle create bundle HEAD^.. &&
	head -n1 bundle | grep "^# v$(test_oid version) git bundle$"
'

test_expect_success 'git bundle v3 has expected contents' '
	git branch side HEAD &&
	git bundle create --version=3 bundle HEAD^..side &&
	head -n2 bundle >actual &&
	cat >expect <<-EOF &&
	# v3 git bundle
	@object-format=$(test_oid algo)
	EOF
	test_cmp expect actual &&
	git bundle verify bundle
'

test_expect_success 'git bundle v3 rejects unknown capabilities' '
	cat >new <<-EOF &&
	# v3 git bundle
	@object-format=$(test_oid algo)
	@unknown=silly
	EOF
	test_must_fail git bundle verify new 2>output &&
	test_i18ngrep "unknown capability .unknown=silly." output
'

test_done
