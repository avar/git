#!/bin/sh

test_description="Test bundle-uri with protocol v2 and 'git://' transport"

TEST_NO_CREATE_REPO=1

GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME=main
export GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME

. ./test-lib.sh

# Test protocol v2 with 'git://' transport
#
T5730_PROTOCOL=git
. "$TEST_DIRECTORY"/lib-t5370-protocol-v2-bundle-uri.sh

test_done
