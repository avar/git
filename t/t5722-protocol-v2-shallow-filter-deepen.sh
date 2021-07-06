#!/bin/sh

test_description='Test shallow fetches, deepening and filters with protocol v2'

GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME=main
export GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME

. ./test-lib.sh

test_expect_success 'setup filter tests' '
	git init server &&

	# 1 commit to create a file, and 1 commit to modify it
	test_commit -C server message1 a.txt &&
	test_commit -C server message2 a.txt &&
	git -C server config protocol.version 2 &&
	git -C server config uploadpack.allowfilter 1 &&
	git -C server config uploadpack.allowanysha1inwant 1 &&
	git -C server config protocol.version 2
'

test_expect_success 'partial clone' '
	test_when_finished "rm -rf trace client" &&
	GIT_TRACE_PACKET="$(pwd)/trace" git -c protocol.version=2 \
		clone --filter=blob:none "file://$(pwd)/server" client &&
	grep "version 2" trace &&

	# Ensure that the old version of the file is missing
	git -C client rev-list --quiet --objects --missing=print main \
		>observed.oids &&
	grep "$(git -C server rev-parse message1:a.txt)" observed.oids &&

	# Ensure that client passes fsck
	git -C client fsck
'

test_expect_success 'dynamically fetch missing object, does not list refs' '
	test_when_finished "rm -rf trace client" &&
	git -c protocol.version=2 \
		clone --filter=blob:none "file://$(pwd)/server" client &&
	GIT_TRACE_PACKET="$(pwd)/trace" git -C client -c protocol.version=2 \
		cat-file -p $(git -C server rev-parse message1:a.txt) &&
	grep "version 2" trace &&
	! grep "git> command=ls-refs" trace
'

test_expect_success 'partial fetch' '
	test_when_finished "rm -rf trace client" &&
	git init client &&
	SERVER="file://$(pwd)/server" &&

	GIT_TRACE_PACKET="$(pwd)/trace" git -C client -c protocol.version=2 \
		fetch --filter=blob:none "$SERVER" main:refs/heads/other &&
	grep "version 2" trace &&

	# Ensure that the old version of the file is missing
	git -C client rev-list --quiet --objects --missing=print other \
		>observed.oids &&
	grep "$(git -C server rev-parse message1:a.txt)" observed.oids &&

	# Ensure that client passes fsck
	git -C client fsck
'

test_expect_success 'do not advertise filter if not configured to do so' '
	test_when_finished "rm -rf trace" &&
	SERVER="file://$(pwd)/server" &&

	git -C server config uploadpack.allowfilter 1 &&
	GIT_TRACE_PACKET="$(pwd)/trace" git -c protocol.version=2 \
		ls-remote "$SERVER" &&
	grep "fetch=.*filter" trace &&

	rm "$(pwd)/trace" &&
	git -C server config uploadpack.allowfilter 0 &&
	GIT_TRACE_PACKET="$(pwd)/trace" git -c protocol.version=2 \
		ls-remote "$SERVER" &&
	grep "fetch=" trace >fetch_capabilities &&
	! grep filter fetch_capabilities
'

test_expect_success 'partial clone warns if filter is not advertised' '
	test_when_finished "rm -rf client" &&
	git -C server config uploadpack.allowfilter 0 &&

	cat >err.expect <<-\EOF &&
	Cloning into '"'"'client'"'"'...
	warning: filtering not recognized by server, ignoring
	EOF
	git -c protocol.version=2 \
		clone --filter=blob:none "file://$(pwd)/server" client >out 2>err.actual &&

	test_must_be_empty out &&
	test_cmp err.expect err.actual
'

test_expect_success 'create repo to be served by file:// transport' '
	git init file_parent &&
	test_commit -C file_parent one &&
	test_commit -C file_parent two &&
	test_commit -C file_parent three
'

test_expect_success 'default refspec is used to filter ref when fetchcing' '
	git -c protocol.version=2 clone "file://$(pwd)/file_parent" file_child &&

	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C file_child -c protocol.version=2 \
		fetch origin &&

	git -C file_child log -1 --format=%s three >actual &&
	git -C file_parent log -1 --format=%s three >expect &&
	test_cmp expect actual &&

	grep "ref-prefix refs/heads/" log &&
	grep "ref-prefix refs/tags/" log
'

test_expect_success 'even with handcrafted request, filter does not work if not advertised' '
	git -C server config uploadpack.allowfilter 0 &&

	# Custom request that tries to filter even though it is not advertised.
	test-tool pkt-line pack >in <<-EOF &&
	command=fetch
	object-format=$(test_oid algo)
	0001
	want $(git -C server rev-parse main)
	filter blob:none
	0000
	EOF

	cat >expect <<-EOF &&
	ERR fetch: unexpected argument: '"'"'filter blob:none'"'"'
	EOF

	cat >err.expect <<-\EOF &&
	fatal: fetch: unexpected argument: '"'"'filter blob:none'"'"'
	EOF
	test_must_fail test-tool -C server serve-v2 --stateless-rpc \
		<in >out 2>err.actual &&
	test-tool pkt-line unpack <out >actual &&
	test_cmp expect actual &&
	test_cmp err.expect err.actual &&

	# Exercise to ensure that if advertised, filter works
	git -C server config uploadpack.allowfilter 1 &&
	test-tool -C server serve-v2 --stateless-rpc <in >out 2>err &&
	test_must_be_empty err
'

test_expect_success 'upload-pack respects client shallows' '
	test_when_finished "rm -rf server client trace" &&

	git init server &&
	test_commit -C server base &&
	test_commit -C server client_has &&

	git clone --depth=1 "file://$(pwd)/server" client &&

	# Add extra commits to the client so that the whole fetch takes more
	# than 1 request (due to negotiation)
	test_commit_bulk -C client --id=c 32 &&

	git -C server checkout -b newbranch base &&
	test_commit -C server client_wants &&

	GIT_TRACE_PACKET="$(pwd)/trace" git -C client -c protocol.version=2 \
		fetch origin newbranch &&
	# Ensure that protocol v2 is used
	grep "fetch< version 2" trace
'

test_expect_success 'ensure that multiple fetches in same process from a shallow repo works' '
	test_when_finished "rm -rf server client trace" &&

	test_create_repo server &&
	test_commit -C server one &&
	test_commit -C server two &&
	test_commit -C server three &&
	git clone --shallow-exclude two "file://$(pwd)/server" client &&

	git -C server tag -a -m "an annotated tag" twotag two &&

	# Triggers tag following (thus, 2 fetches in one process)
	GIT_TRACE_PACKET="$(pwd)/trace" git -C client -c protocol.version=2 \
		fetch --shallow-exclude one origin &&
	# Ensure that protocol v2 is used
	grep "fetch< version 2" trace
'

test_expect_success 'deepen-relative' '
	test_when_finished "rm -rf server client trace" &&

	test_create_repo server &&
	test_commit -C server one &&
	test_commit -C server two &&
	test_commit -C server three &&
	git clone --depth 1 "file://$(pwd)/server" client &&
	test_commit -C server four &&

	# Sanity check that only "three" is downloaded
	git -C client log --pretty=tformat:%s main >actual &&
	echo three >expected &&
	test_cmp expected actual &&

	GIT_TRACE_PACKET="$(pwd)/trace" git -C client -c protocol.version=2 \
		fetch --deepen=1 origin &&
	# Ensure that protocol v2 is used
	grep "fetch< version 2" trace &&

	git -C client log --pretty=tformat:%s origin/main >actual &&
	cat >expected <<-\EOF &&
	four
	three
	two
	EOF
	test_cmp expected actual
'

test_done
