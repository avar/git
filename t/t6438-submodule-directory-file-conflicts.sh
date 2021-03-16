#!/bin/sh

test_description='merge can handle submodules'

. ./test-lib.sh
. "$TEST_DIRECTORY"/lib-submodule-update.sh

# merges without conflicts
test_submodule_switch "merge"

test_submodule_switch "merge --ff"

test_submodule_switch "merge --ff-only"

if test "$GIT_TEST_MERGE_ALGORITHM" = ort
then
	:  # No special additional KNOWN_FAILURE knobs to set
else
	KNOWN_FAILURE_NOFF_MERGE_DOESNT_CREATE_EMPTY_SUBMODULE_DIR=1
	KNOWN_FAILURE_NOFF_MERGE_ATTEMPTS_TO_MERGE_REMOVED_SUBMODULE_FILES=1
fi
test_submodule_switch "merge --no-ff"

test_done
