#!/bin/sh
set -e
set -x

only_range_diff=
only_merge=
only_compile=
only_basic_test=
only_test=
while test $# != 0
do
	case "$1" in
	--only-range-diff)
		only_range_diff=yes
		;;
	--only-merge)
		only_merge=yes
		;;
	--only-compile)
		only_compile=yes
		;;
	--only-basic-test)
		only_basic_test=yes
		;;
	--only-test)
		only_test=yes
		;;
	*)
		break
		;;
	esac
	shift
done

meta_dir="$(pwd)"
cd ~/g/git.build

tag_name() {
	date +'avargit-v%Y-%m-%d-%H%M%S'
}

tag_it() {
        tmp=$(mktemp /tmp/avargit-XXXXX)
	cat >$tmp <<-EOF
	object $1
	type commit
	tag $2
	tagger $(git config user.name) <$(git config user.email)> $(date "+%s %z")

	My personal git version built from (mostly) my outstanding topics.

	The hacky script that built this follows after the NUL:
	EOF

	printf "\0" >>$tmp
	cat "$meta_dir"/"$0" >>$tmp

        git mktag --strict <$tmp
}

show_built_from() {
        built_from=$(git version --build-options | grep -P -o '(?<=built from commit: ).*')
        echo "Info:"
        echo "  - Now running: $(git version)"
        echo "  - Now running built from: $(git reference $built_from)"
}

reset_it() {
        git reset --hard @{u}
        git merge --abort || :
        git reset --hard @{u}
}

show_built_from
reset_it
git checkout build-master || git checkout -b build-master -t origin/master

series_list=$(mktemp /tmp/avargit-series-XXXXX)
# TODO:
#   make-dot-not-HEAD-warn-3
#   avar/object-api-to-no-string-argument (TODO: handle -t "some garbage" case)
#   unconditional-abbrev-redo-2021-rebase
#   avar/no-templates
#   avar/test-lib-add-GIT_TEST_TIMEOUT-2
# Ejected:
#   avar/fix-tree-mode-fsck (in favor of avar/tree-walk-api-refactor)
#
# If we've got a previous resolution, the merge --continue will
# continue the merge. TODO: make it support --no-edit
set +x
for series in \
    avar/fsck-doc \
    avar/makefile-objs-targets-3 \
    avar/fsck-h-interface-5 \
    avar/t4018-diff-hunk-header-regex-tests-4-beginning \
    avar/t4018-diff-hunk-header-regex-tests-4 \
    avar/diff-W-context-3 \
    avar/pcre2-fixes-diffcore-pickaxe-pcre-etc-2-on-v2.31.0 \
    avar/commit-graph-usage \
    avar/worktree-add-orphan \
    avar/describe-test-refactoring-2 \
    avar/fix-coccicheck-4 \
    avar/object-is-type-error-refactor-2 \
    avar/nuke-read-tree-api-5 \
    avar/tree-walk-api-refactor-4 \
    avar/tree-walk-api-canon-mode-switch \
    avar/pr-git-973/newren/ort-remainder-v1 \
    avar/makefile-rename-git-binary-not-in-place \
    avar/mktag-broken-and-chain-typo \
    avar/support-test-verbose-under-prove-2 \
    avar/support-test-verbose-under-prove-2-for-avar/pcre2-fixes-diffcore-pickaxe-pcre-etc-2-on-v2.31.0 \
    avar/sh-remove-sha1-variables \
    avar/test-lib-bail-out-on-accidental-prove-invocation \
    avar/diff-no-index-tests-3 \
    avar/fix-rebase-no-reschedule-failed-exec-with-config \
    avar/remove-rebase-usebuiltin-warning \
    avar/format-patch-prettier-message-id \
    avar/robertfoss/send-email-fix
do
	echo $series >>$series_list
done

# Sanity check that this is all pushed out
while read -r branch
do
	if ! git rev-parse refs/remotes/avar/$branch >/dev/null 2>&1
	then
		echo Pushing missing $branch to avar remote
		git push avar $branch:$branch
	else
		git rev-parse $branch refs/remotes/avar/$branch >$series_list.tmp
		num_sha=$(uniq $series_list.tmp | wc -l)
		if test $num_sha -ne 1
		then
			echo Have $branch and avar/$branch at two different commits:
			cat $series_list.tmp
			# Die if I need to force push, will manually sort it out.
			git push avar $branch:$branch
		fi
	fi
done <$series_list

# Check what's already merged
while read -r branch
do
	git --no-pager range-diff --right-only origin/master...$branch >$series_list.range-diff
	grep -v -- " ----------- >" $series_list.range-diff >$series_list.range-diff.no-new || :
	if test -s $series_list.range-diff.no-new
	then
		echo "Have partial merge in rangediff of origin/master...$branch, rebase!:"
		cat $series_list.range-diff
	else
		echo "Have $(wc -l $series_list.range-diff | cut -d ' ' -f1) unmerged in range-diff of origin/master...$branch"
	fi
done <$series_list
test -n "$only_range_diff" && exit

# Merge it all together
set -x
while read -r branch
do
	git merge --no-edit $branch || EDITOR=cat git merge --continue
done <$series_list
test -n "$only_merge" && exit

# Configure
~/g/git.meta/config.mak.sh --prefix /home/avar/local

# Compile
make -j $(nproc) all man
test -n "$only_compile" && exit

# First run a smaller subset of tests, likelier to have failures:
git diff --diff-filter=ACMR --name-only --relative=t/ -p @{u}.. -- t/t[0-9]*.sh >/tmp/git.build-tests
tr '\n' ' ' </tmp/git.build-tests >/tmp/git.build-tests.tr
(
	cd t &&
	GIT_TEST_HTTPD=1 make GIT_PROVE_OPTS="--jobs=$(nproc) --timer" T="$(cat /tmp/git.build-tests.tr)"
)
test -n "$only_basic_test" && exit

# Run all tests
(
	cd t &&
	GIT_TEST_HTTPD=1 GIT_TEST_DEFAULT_HASH=sha256 make GIT_PROVE_OPTS="--exec /bin/bash --jobs=$(nproc) --timer --state=failed,slow,save"
)
test -n "$only_test" && exit

# Install it
new_version=$(git rev-parse HEAD)
new_tagname=$(tag_name)
new_tag=$(tag_it "$new_version" "$new_tagname")
last_version=$(git rev-parse avar/private)
make -j $(nproc) install install-man
show_built_from

# Post-install & report
echo "Range-diff between last built and what I've got now:"
git --no-pager range-diff --left-only avar/private...

echo "Shortlog from @{u}..:"
git --no-pager shortlog @{u}..

git push avar HEAD:private -f
git push avar $new_tag:refs/built-tags/$new_tagname

echo "Check out the CI result at:"
echo "  https://github.com/avar/git/commit/$new_version"

# Cleanup
rm -rf /tmp/avargit-*
