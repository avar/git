#!/bin/sh

test_description='Test git-bundle --stdin in detail'

. ./test-lib.sh

test_expect_success 'setup' '
	test_commit --no-tag initial &&
	test_commit --no-tag second &&
	test_commit --no-tag third &&
	test_commit --no-tag fourth &&
	git tag -a -m"my tag" tag :/second
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
	$(git symbolic-ref --short HEAD)
	EOF
	git bundle create mixed.bdl --stdin <in &&

	cat >expect <<-EOF &&
	$(git rev-parse HEAD)	$(git symbolic-ref HEAD)
	$(git rev-parse :/initial)	refs/heads/initial
	EOF
	git ls-remote mixed.bdl >actual &&
	test_cmp expect actual
'

test_expect_success 'bundle --stdin rev-range tabular input' '
	cat >in <<-EOF &&
	HEAD~3..HEAD~2	refs/tags/update-for-second-push
	EOF
	git bundle create first-update.bdl --stdin <in &&

	cat >expect <<-EOF &&
	$(git rev-parse :/second)	refs/tags/update-for-second-push
	EOF
	git ls-remote first-update.bdl >actual &&
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
	fatal: bad revision '"'"'$(git rev-parse HEAD) $(git symbolic-ref HEAD)'"'"'
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
	$(git rev-parse HEAD) $(git symbolic-ref HEAD)
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
	$(git rev-parse HEAD) $(git symbolic-ref HEAD)
	$(git rev-parse tag) refs/tags/tag
	EOF

	git bundle list-heads all.bdl >actual &&
	test_cmp expect actual
'

test_done
