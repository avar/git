#!/bin/sh

test_description='Test git-bundle --stdin in detail'

. ./test-lib.sh
. "$TEST_DIRECTORY"/lib-bundle.sh

test_expect_success 'setup' '
	test_commit --no-tag initial &&
	test_commit --no-tag second &&
	test_commit --no-tag third &&
	test_commit --no-tag fourth &&
	test_commit --no-tag fifth &&
	test_commit --no-tag sixth &&
	test_commit --no-tag seventh &&

	git tag -a -m"my tag" tag :/second &&
	git branch trunk :/third &&
	git branch next :/fifth &&
	git branch unstable :/sixth &&

	git checkout -b divergent :/initial &&
	test_commit --no-tag alt-2nd &&

	git checkout -
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
	test_cmp expect actual &&
	test_bundle_object_count initial.bdl 3
'

test_expect_success 'bundle --stdin mixed rev-list and tabular input' '
	cat >in <<-EOF &&
	$(git rev-parse :/initial)	refs/heads/initial
	$(git symbolic-ref --short HEAD)
	EOF
	git bundle create mixed.bdl --stdin <in &&

	cat >expect <<-EOF &&
	$(git rev-parse HEAD)	$(git symbolic-ref HEAD)
	$(git rev-parse :/initial)	refs/heads/initial
	EOF
	git ls-remote mixed.bdl >actual &&
	test_cmp expect actual &&
	test_bundle_object_count mixed.bdl 21
'

test_expect_success 'bundle --stdin basic rev-range tabular input, RHS is a ref name' '
	cat >in <<-EOF &&
	HEAD~1..$(git symbolic-ref --short HEAD)	refs/tags/latest-update
	EOF
	git bundle create latest-update.bdl --stdin <in &&

	cat >expect <<-EOF &&
	$(git rev-parse HEAD)	refs/tags/latest-update
	EOF
	git ls-remote latest-update.bdl >actual &&
	test_cmp expect actual &&
	test_bundle_object_count --thin latest-update.bdl 4
'

test_expect_success 'bundle --stdin basic rev-range tabular input, LHS is a ref name' '
	cat >in <<-EOF &&
	trunk..$(git rev-parse :/fourth)	refs/tags/post-trunk-update
	EOF
	git bundle create post-trunk-update.bdl --stdin <in &&

	cat >expect <<-EOF &&
	$(git rev-parse :/fourth)	refs/tags/post-trunk-update
	EOF
	git ls-remote post-trunk-update.bdl >actual &&
	test_cmp expect actual &&
	test_bundle_object_count post-trunk-update.bdl 3
'

test_expect_success 'bundle --stdin basic rev-range tabular input, LHS and RHS are not ref names' '
	cat >in <<-EOF &&
	HEAD~2..HEAD~1	refs/tags/penultimate-update
	EOF
	git bundle create penultimate-update.bdl --stdin <in &&

	cat >expect <<-EOF &&
	$(git rev-parse HEAD~)	refs/tags/penultimate-update
	EOF
	git ls-remote penultimate-update.bdl >actual &&
	test_cmp expect actual &&
	test_bundle_object_count --thin penultimate-update.bdl 4
'

test_expect_success 'bundle --stdin complex rev-range tabular input, multiple ranges' '
	cat >in <<-EOF &&
	:/initial..:/second	refs/tags/second-push
	:/fourth..:/fifth	refs/tags/fourth-push
	EOF
	git bundle create multiple-updates.bdl --stdin <in &&

	cat >expect <<-EOF &&
	$(git rev-parse :/fifth)	refs/tags/fourth-push
	$(git rev-parse :/second)	refs/tags/second-push
	EOF
	git ls-remote multiple-updates.bdl >actual &&
	test_cmp expect actual &&
	test_bundle_object_count --thin multiple-updates.bdl 4
'

test_expect_success 'bundle --stdin complex rev-range mixed tabular and ref name input' '
	cat >in <<-EOF &&
	trunk~..trunk
	$(git rev-parse :/initial)..$(git rev-parse :/alt-2nd)	refs/tags/first-divergent-push
	EOF
	git bundle create mixed-multiple-updates.bdl --stdin <in &&

	cat >expect <<-EOF &&
	$(git rev-parse :/alt-2nd)	refs/tags/first-divergent-push
	$(git rev-parse trunk)	refs/heads/trunk
	EOF
	git ls-remote mixed-multiple-updates.bdl >actual &&
	test_cmp expect actual &&
	test_bundle_object_count mixed-multiple-updates.bdl 6
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
	test_cmp expect actual &&
	test_bundle_object_count one-level.bdl 21
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

test_expect_success 'bundle --stdin tabular input with non-existing reference' '
	sed "s/Z$//" >in <<-EOF &&
	^topic/deleted	refs/heads/topic-deleted
	$(git rev-parse :/initial)	refs/heads/a-branch
	EOF
	cat >expect <<-\EOF &&
	fatal: bad revision '"'"'^topic/deleted'"'"'
	EOF
	test_must_fail git bundle create err.bdl --stdin <in 2>actual &&
	test_cmp expect actual &&
	test_path_is_missing err.bdl
'

test_expect_success 'bundle --stdin tabular input with non-existing reference and --ignore-missing (existing first)' '
	sed "s/Z$//" >in <<-EOF &&
	$(git rev-parse :/initial)	refs/heads/a-branch
	^topic/deleted	refs/heads/topic-deleted
	EOF

	git bundle create ignore-missing.bdl --ignore-missing --stdin <in &&
	cat >expect <<-EOF &&
	$(git rev-parse :/initial)	refs/heads/a-branch
	EOF
	git ls-remote ignore-missing.bdl >actual &&
	test_cmp expect actual &&
	test_bundle_object_count ignore-missing.bdl 3
'

test_expect_success 'bundle --stdin tabular input with non-existing reference and --ignore-missing (deleted first)' '
	sed "s/Z$//" >in <<-EOF &&
	^topic/deleted	refs/heads/topic-deleted
	$(git rev-parse :/initial)	refs/heads/a-branch
	EOF

	FOO=1 git bundle create ignore-missing2.bdl --ignore-missing --stdin <in &&
	cat >expect <<-EOF &&
	$(git rev-parse :/initial)	refs/heads/a-branch
	EOF
	git ls-remote ignore-missing2.bdl >actual &&
	test_cmp expect actual &&
	test_bundle_object_count ignore-missing2.bdl 3
'

test_expect_success 'bundle --stdin tabular input with non-existing reference and --ignore-missing (mixed existing and deleted)' '
	sed "s/Z$//" >in <<-EOF &&
	$(git rev-parse HEAD)	$(git symbolic-ref HEAD)
	^topic/deleted	refs/heads/topic-deleted
	$(git rev-parse :/initial)	refs/heads/a-branch
	^topic/deleted2	refs/heads/topic-deleted2
	EOF

	FOO=1 git bundle create ignore-missing3.bdl --ignore-missing --stdin <in &&
	cat >expect <<-EOF &&
	$(git rev-parse :/initial)	refs/heads/a-branch
	$(git rev-parse HEAD)	$(git symbolic-ref HEAD)
	EOF
	git ls-remote ignore-missing3.bdl >actual &&
	test_cmp expect actual &&
	test_bundle_object_count ignore-missing2.bdl 3
'

# --stdin tabular input show-ref incompatibility
test_expect_success 'bundle --stdin tabular input is incompatible with "git show-ref"' '
	git show-ref >sr &&

	cat >expect <<-EOF &&
	fatal: bad revision '"'"'$(git rev-parse divergent) refs/heads/divergent'"'"'
	EOF
	test_must_fail git bundle create err.bdl --stdin <sr 2>actual &&
	test_cmp expect actual &&
	test_path_is_missing err.bdl
'

# --stdin tabular input for-each-ref compatibility
test_expect_success 'bundle --stdin tabular input is compatible with "git for-each-ref"' '
	git for-each-ref >fer &&
	git bundle create fer-fmt.bdl --stdin <fer &&

	cat >expect <<-EOF &&
	$(git rev-parse divergent) refs/heads/divergent
	$(git rev-parse HEAD) $(git symbolic-ref HEAD)
	$(git rev-parse next) refs/heads/next
	$(git rev-parse trunk) refs/heads/trunk
	$(git rev-parse unstable) refs/heads/unstable
	$(git rev-parse tag) refs/tags/tag
	EOF
	git bundle list-heads fer-fmt.bdl >actual &&
	test_cmp expect actual &&
	test_bundle_object_count fer-fmt.bdl 25
'

test_expect_success 'bundle --stdin tabular input errors on corrpt "git for-each-ref" output' '
	git for-each-ref >fer.raw &&
	tr " " "?" <fer.raw >fer &&
	cat >expect <<-EOF &&
	fatal: bad revision '"'"'$(git rev-parse divergent)?'"'"'
	EOF
	test_must_fail git bundle create fer-fmt-bad.bdl --stdin <fer 2>actual &&
	test_cmp expect actual &&
	test_path_is_missing fer-fmt-bad.bdl

'

# --stdin tabular input for-each-ref parsing
test_expect_success 'bundle --stdin tabular "git for-each-ref" input ignores types' '
	git for-each-ref >fer &&
	cat fer &&
	sed -e "s/commit/blob/" -e "s/tag/commit/" <fer >fake-fer &&
	git bundle create all.bdl --stdin <fake-fer &&

	cat >expect <<-EOF &&
	$(git rev-parse divergent) refs/heads/divergent
	$(git rev-parse HEAD) $(git symbolic-ref HEAD)
	$(git rev-parse next) refs/heads/next
	$(git rev-parse trunk) refs/heads/trunk
	$(git rev-parse unstable) refs/heads/unstable
	$(git rev-parse tag) refs/tags/tag
	EOF

	git bundle list-heads all.bdl >actual &&
	test_cmp expect actual &&
	test_bundle_object_count all.bdl 25
'

test_done
