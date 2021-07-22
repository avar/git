#!/bin/sh

test_description="Test bundle-uri with protocol v2 and 'file://' transport"

TEST_NO_CREATE_REPO=1

GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME=main
export GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME

. ./test-lib.sh

# Test protocol v2 with 'file://' transport
#
T5730_PROTOCOL=file
. "$TEST_DIRECTORY"/lib-t5370-protocol-v2-bundle-uri.sh

test_done
