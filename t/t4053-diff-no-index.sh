#!/bin/sh

test_description='diff --no-index'

. ./test-lib.sh

test_expect_success 'setup' '
	mkdir a &&
	mkdir b &&
	echo 1 >a/1 &&
	echo 2 >a/2 &&
	git init repo &&
	echo 1 >repo/a &&
	mkdir -p non/git &&
	echo 1 >non/git/a &&
	echo 1 >non/git/b
'

test_expect_success 'git diff --no-index --exit-code' '
	git diff --no-index --exit-code a/1 non/git/a &&
	test_expect_code 1 git diff --no-index --exit-code a/1 a/2
'

test_expect_success 'git diff --no-index directories' '
	test_expect_code 1 git diff --no-index a b >cnt &&
	test_line_count = 14 cnt
'

test_expect_success 'git diff --no-index relative path outside repo' '
	(
		cd repo &&
		test_expect_code 0 git diff --no-index a ../non/git/a &&
		test_expect_code 0 git diff --no-index ../non/git/a ../non/git/b
	)
'

test_expect_success 'git diff --no-index with broken index' '
	(
		cd repo &&
		echo broken >.git/index &&
		git diff --no-index a ../non/git/a
	)
'

test_expect_success 'git diff outside repo with broken index' '
	(
		cd repo &&
		git diff ../non/git/a ../non/git/b
	)
'

test_expect_success 'git diff --no-index executed outside repo gives correct error message' '
	(
		GIT_CEILING_DIRECTORIES=$TRASH_DIRECTORY/non &&
		export GIT_CEILING_DIRECTORIES &&
		cd non/git &&
		test_must_fail git diff --no-index a 2>actual.err &&
		test_i18ngrep "usage: git diff --no-index" actual.err
	)
'

test_expect_success 'diff D F and diff F D' '
	(
		cd repo &&
		echo in-repo >a &&
		echo non-repo >../non/git/a &&
		mkdir sub &&
		echo sub-repo >sub/a &&

		test_must_fail git diff --no-index sub/a ../non/git/a >expect &&
		test_must_fail git diff --no-index sub/a ../non/git/ >actual &&
		test_cmp expect actual &&

		test_must_fail git diff --no-index a ../non/git/a >expect &&
		test_must_fail git diff --no-index a ../non/git/ >actual &&
		test_cmp expect actual &&

		test_must_fail git diff --no-index ../non/git/a a >expect &&
		test_must_fail git diff --no-index ../non/git a >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'turning a file into a directory' '
	(
		cd non/git &&
		mkdir d e e/sub &&
		echo 1 >d/sub &&
		echo 2 >e/sub/file &&
		printf "D\td/sub\nA\te/sub/file\n" >expect &&
		test_must_fail git diff --no-index --name-status d e >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'diff from repo subdir shows real paths (explicit)' '
	echo "diff --git a/../../non/git/a b/../../non/git/b" >expect &&
	test_expect_code 1 \
		git -C repo/sub \
		diff --no-index ../../non/git/a ../../non/git/b >actual &&
	head -n 1 <actual >actual.head &&
	test_cmp expect actual.head
'

test_expect_success 'diff from repo subdir shows real paths (implicit)' '
	echo "diff --git a/../../non/git/a b/../../non/git/b" >expect &&
	test_expect_code 1 \
		git -C repo/sub \
		diff ../../non/git/a ../../non/git/b >actual &&
	head -n 1 <actual >actual.head &&
	test_cmp expect actual.head
'

test_expect_success 'diff --no-index from repo subdir respects config (explicit)' '
	echo "diff --git ../../non/git/a ../../non/git/b" >expect &&
	test_config -C repo diff.noprefix true &&
	test_expect_code 1 \
		git -C repo/sub \
		diff --no-index ../../non/git/a ../../non/git/b >actual &&
	head -n 1 <actual >actual.head &&
	test_cmp expect actual.head
'

test_expect_success 'diff --no-index from repo subdir respects config (implicit)' '
	echo "diff --git ../../non/git/a ../../non/git/b" >expect &&
	test_config -C repo diff.noprefix true &&
	test_expect_code 1 \
		git -C repo/sub \
		diff ../../non/git/a ../../non/git/b >actual &&
	head -n 1 <actual >actual.head &&
	test_cmp expect actual.head
'

test_expect_success 'diff --no-index from repo subdir with absolute paths' '
	cat <<-EOF >expect &&
	1	1	$(pwd)/non/git/{a => b}
	EOF
	test_expect_code 1 \
		git -C repo/sub diff --numstat \
		"$(pwd)/non/git/a" "$(pwd)/non/git/b" >actual &&
	test_cmp expect actual
'

test_expect_success 'diff --no-index allows external diff' '
	test_expect_code 1 \
		env GIT_EXTERNAL_DIFF="echo external ;:" \
		git diff --no-index non/git/a non/git/b >actual &&
	echo external >expect &&
	test_cmp expect actual
'

test_expect_success 'diff --no-index normalizes mode: no changes' '
	echo foo >x &&
	cp x y &&
	git diff --no-index x y >out &&
	test_must_be_empty out
'

test_expect_success POSIXPERM 'diff --no-index normalizes mode: chmod +x' '
	chmod +x y &&
	cat >expected <<-\EOF &&
	diff --git a/x b/y
	old mode 100644
	new mode 100755
	EOF
	test_expect_code 1 git diff --no-index x y >actual &&
	test_cmp expected actual
'

test_expect_success POSIXPERM 'diff --no-index normalizes: mode not like git mode' '
	chmod 666 x &&
	chmod 777 y &&
	cat >expected <<-\EOF &&
	diff --git a/x b/y
	old mode 100644
	new mode 100755
	EOF
	test_expect_code 1 git diff --no-index x y >actual &&
	test_cmp expected actual
'

test_expect_success POSIXPERM,SYMLINKS 'diff --no-index normalizes: mode not like git mode (symlink)' '
	ln -s y z &&
	X_OID=$(git hash-object --stdin <x) &&
	Z_OID=$(printf "y" | git hash-object --stdin) &&
	cat >expected <<-EOF &&
	diff --git a/x b/x
	deleted file mode 100644
	index $X_OID..$ZERO_OID
	--- a/x
	+++ /dev/null
	@@ -1 +0,0 @@
	-foo
	diff --git a/z b/z
	new file mode 120000
	index $ZERO_OID..$Z_OID
	--- /dev/null
	+++ b/z
	@@ -0,0 +1 @@
	+y
	\ No newline at end of file
	EOF
	test_expect_code 1 git -c core.abbrev=no diff --no-index x z >actual &&
	test_cmp expected actual
'

test_done
