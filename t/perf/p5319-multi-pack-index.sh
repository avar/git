#!/bin/sh

test_description='Test midx performance'

. ./perf-lib.sh

test_perf_large_repo

test_expect_success 'setup multi-pack-index' '
	git multi-pack-index write
'

test_perf 'midx write' '
	git multi-pack-index write
'

test_perf 'midx verify' '
	git multi-pack-index verify
'

test_done
