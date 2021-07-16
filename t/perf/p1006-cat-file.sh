#!/bin/sh

test_description='Basic sort performance tests'
. ./perf-lib.sh

test_perf_default_repo

test_expect_success 'setup' '
	git rev-list --all >rla
'

test_perf 'cat-file --batch-check' '
	git cat-file --batch-check <rla
'

test_done
