#!/bin/sh

test_description='basic git gc tests
'

. ./test-lib.sh
. "$TEST_DIRECTORY"/lib-terminal.sh

test_expect_success 'setup' '
	# do not let the amount of physical memory affects gc
	# behavior, make sure we always pack everything to one pack by
	# default
	git config gc.bigPackThreshold 2g &&

	# These are simply values which, when hashed as a blob with a newline,
	# produce a hash where the first byte is 0x17 in their respective
	# algorithms.
	test_oid_cache <<-EOF
	obj1 sha1:263
	obj1 sha256:34

	obj2 sha1:410
	obj2 sha256:174

	obj3 sha1:523
	obj3 sha256:313

	obj4 sha1:790
	obj4 sha256:481
	EOF
'

test_expect_success 'gc empty repository' '
	git gc
'

test_expect_success 'gc does not leave behind pid file' '
	git gc &&
	test_path_is_missing .git/gc.pid
'

test_expect_success 'gc --gobbledegook' '
	test_expect_code 129 git gc --nonsense 2>err &&
	test_i18ngrep "[Uu]sage: git gc" err
'

test_expect_success 'gc -h with invalid configuration' '
	mkdir broken &&
	(
		cd broken &&
		git init &&
		echo "[gc] pruneexpire = CORRUPT" >>.git/config &&
		test_expect_code 129 git gc -h >usage 2>&1
	) &&
	test_i18ngrep "[Uu]sage" broken/usage
'

test_expect_success !GC 'gc is not aborted due to a stale symref' '
	git init remote &&
	(
		cd remote &&
		test_commit initial &&
		git clone . ../client &&
		git branch -m develop &&
		cd ../client &&
		git fetch --prune &&
		git gc
	)
'

test_expect_success !GC 'gc --keep-largest-pack' '
	test_create_repo keep-pack &&
	(
		cd keep-pack &&
		test_commit one &&
		test_commit two &&
		test_commit three &&
		git gc &&
		( cd .git/objects/pack && ls *.pack ) >pack-list &&
		test_line_count = 1 pack-list &&
		cp pack-list base-pack-list &&
		test_commit four &&
		git repack -d &&
		test_commit five &&
		git repack -d &&
		( cd .git/objects/pack && ls *.pack ) >pack-list &&
		test_line_count = 3 pack-list &&
		git gc --keep-largest-pack &&
		( cd .git/objects/pack && ls *.pack ) >pack-list &&
		test_line_count = 2 pack-list &&
		awk "/^P /{print \$2}" <.git/objects/info/packs >pack-info &&
		test_line_count = 2 pack-info &&
		test_path_is_file .git/objects/pack/$(cat base-pack-list) &&
		git fsck
	)
'

test_expect_success !GC 'auto gc with too many loose objects does not attempt to create bitmaps' '
	test_config gc.auto 3 &&
	test_config gc.autodetach false &&
	test_config pack.writebitmaps true &&
	# We need to create two objects whose sha1s start with 17
	# since this is what git gc counts.  As it happens, these
	# two blobs will do so.
	test_commit "$(test_oid obj1)" &&
	test_commit "$(test_oid obj2)" &&
	# Our first gc will create a pack; our second will create a second pack
	git gc --auto &&
	ls .git/objects/pack/pack-*.pack | sort >existing_packs &&
	test_commit "$(test_oid obj3)" &&
	test_commit "$(test_oid obj4)" &&

	git gc --auto 2>err &&
	test_i18ngrep ! "^warning:" err &&
	ls .git/objects/pack/pack-*.pack | sort >post_packs &&
	comm -1 -3 existing_packs post_packs >new &&
	comm -2 -3 existing_packs post_packs >del &&
	test_line_count = 0 del && # No packs are deleted
	test_line_count = 1 new # There is one new pack
'

test_expect_success !GC 'gc --no-quiet' '
	GIT_PROGRESS_DELAY=0 git -c gc.writeCommitGraph=true gc --no-quiet >stdout 2>stderr &&
	test_must_be_empty stdout &&
	test_i18ngrep "Computing commit graph generation numbers" stderr
'

test_expect_success !GC,TTY 'with TTY: gc --no-quiet' '
	test_terminal env GIT_PROGRESS_DELAY=0 \
		git -c gc.writeCommitGraph=true gc --no-quiet >stdout 2>stderr &&
	test_must_be_empty stdout &&
	test_i18ngrep "Enumerating objects" stderr &&
	test_i18ngrep "Computing commit graph generation numbers" stderr
'

test_expect_success !GC 'gc --quiet' '
	git -c gc.writeCommitGraph=true gc --quiet >stdout 2>stderr &&
	test_must_be_empty stdout &&
	test_must_be_empty stderr
'

test_expect_success 'gc.reflogExpire{Unreachable,}=never skips "expire" via "gc"' '
	test_config gc.reflogExpire never &&
	test_config gc.reflogExpireUnreachable never &&

	GIT_TRACE=$(pwd)/trace.out git gc &&

	# Check that git-pack-refs is run as a sanity check (done via
	# gc_before_repack()) but that git-expire is not.
	grep -E "^trace: (built-in|exec|run_command): git pack-refs --" trace.out &&
	! grep -E "^trace: (built-in|exec|run_command): git reflog expire --" trace.out
'

test_expect_success 'one of gc.reflogExpire{Unreachable,}=never does not skip "expire" via "gc"' '
	>trace.out &&
	test_config gc.reflogExpire never &&
	GIT_TRACE=$(pwd)/trace.out git gc &&
	grep -E "^trace: (built-in|exec|run_command): git reflog expire --" trace.out
'

test_lazy_prereq GNU_PARALLEL '
	parallel --version | grep -q "^GNU parallel"
'

test_racy_gc_auto () {
	result=$1
	config=$2
	sleep_bf=$3
	sleep_bfnl=$4
	fork_works=$5
	sleep_pfpl=$6

	test_expect_$result !GC,C_LOCALE_OUTPUT,GNU_PARALLEL "gc -c gc.autoDetach=$config --auto lock before running & messaging with sleep($sleep_pfpl) & sleep($sleep_bf) & sleep($sleep_bfnl) & fork($fork_works)" "
		>out &&
		>errors &&
		git init gc-lock &&
		test_when_finished 'rm -rf gc-lock' &&
		(
			# See 'two objects whose sha1s start with 17' comment above
			test_commit -C gc-lock 263 &&
			test_commit -C gc-lock 410 &&
			test_config -C gc-lock gc.auto 3 &&
			test_seq 1 16 | parallel --jobs=50% -k \"
				echo {}: &&
				GIT_TEST_GC_SLEEP_BEFORE_FORK=$sleep_bf \
				GIT_TEST_GC_SLEEP_BEFORE_FORK_NO_LOCK=$sleep_bfnl \
				GIT_TEST_GC_SLEEP_POST_FORK_POST_LOCK=$sleep_pfpl \
				GIT_TEST_GC_AUTO_DETACH=$fork_works \
				git -C gc-lock -c gc.autoDetach=$config \
					gc --auto || echo {} >>errors
			\" >>out 2>&1 &&
			cat out &&
			cat errors &&
			test_line_count = 0 errors
		)
	"
}

test_racy_gc_auto success false N/A N/A N/A 0
for sleep_post_fork_post_lock in 0 1
do
	for fork_works in true false
	do
		for sleep_before_fork in 0 1
		do
			for sleep_before_fork_no_lock in 0 1
			do
				test_racy_gc_auto success true $sleep_before_fork $sleep_before_fork_no_lock $fork_works $sleep_post_fork_post_lock
			done
		done
	done
done

test_racy_faked_gc_auto () {
	result=$1
	config=$2

	test_expect_$result C_LOCALE_OUTPUT,GNU_PARALLEL "gc -c gc.autoDetach=$config gc --auto with faked need_to_gc() racyness" "
		>out &&
		>errors &&
		test_seq 1 16 | parallel --jobs=50% -k \"
			echo {}: &&
			GIT_TEST_GC=true git -c gc.autoDetach=$config \
				gc --auto --no-quiet || echo {} >>errors
		\" >>out 2>&1 &&
		cat out &&
		cat errors &&
		test_line_count = 0 errors
	"
}
test_racy_faked_gc_auto success true
test_racy_faked_gc_auto success false

run_and_wait_for_auto_gc () {
	# We read stdout from gc for the side effect of waiting until the
	# background gc process exits, closing its fd 9.  Furthermore, the
	# variable assignment from a command substitution preserves the
	# exit status of the main gc process.
	# Note: this fd trickery doesn't work on Windows, but there is no
	# need to, because on Win the auto gc always runs in the foreground.
	doesnt_matter=$(git gc --auto 9>&1)
}

test_expect_success !GC 'background auto gc does not run if gc.log is present and recent but does if it is old' '
	test_commit foo &&
	test_commit bar &&
	git repack &&
	test_config gc.autopacklimit 1 &&
	test_config gc.autodetach true &&
	echo fleem >.git/gc.log &&
	git gc --auto 2>err &&
	test_i18ngrep "^warning:" err &&
	test_config gc.logexpiry 5.days &&
	test-tool chmtime =-345600 .git/gc.log &&
	git gc --auto &&
	test_config gc.logexpiry 2.days &&
	run_and_wait_for_auto_gc &&
	ls .git/objects/pack/pack-*.pack >packs &&
	test_line_count = 1 packs
'

test_expect_success 'background auto gc respects lock for all operations' '
	# make sure we run a background auto-gc
	test_commit make-pack &&
	git repack &&
	test_config gc.autopacklimit 1 &&
	test_config gc.autodetach true &&

	# create a ref whose loose presence we can use to detect a pack-refs run
	git update-ref refs/heads/should-be-loose HEAD &&
	test_path_is_file .git/refs/heads/should-be-loose &&

	# now fake a concurrent gc that holds the lock; we can use our
	# shell pid so that it looks valid.
	hostname=$(hostname || echo unknown) &&
	shell_pid=$$ &&
	if test_have_prereq MINGW && test -f /proc/$shell_pid/winpid
	then
		# In Git for Windows, Bash (actually, the MSYS2 runtime) has a
		# different idea of PIDs than git.exe (actually Windows). Use
		# the Windows PID in this case.
		shell_pid=$(cat /proc/$shell_pid/winpid)
	fi &&
	printf "%d %s" "$shell_pid" "$hostname" >.git/gc.pid &&

	# our gc should exit zero without doing anything
	run_and_wait_for_auto_gc &&
	test_path_is_file .git/refs/heads/should-be-loose
'

# DO NOT leave a detached auto gc process running near the end of the
# test script: it can run long enough in the background to racily
# interfere with the cleanup in 'test_done'.

test_done
