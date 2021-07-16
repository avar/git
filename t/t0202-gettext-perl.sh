#!/bin/sh
#
# Copyright (c) 2010 Ævar Arnfjörð Bjarmason
#

test_description='Perl gettext interface (Git::I18N)'

. ./lib-gettext.sh

if ! test_have_prereq PERL; then
	skip_all='skipping perl interface tests, perl not available'
	test_done
fi

perl -MTest::More -e 0 2>/dev/null || {
	skip_all="Perl Test::More unavailable, skipping test"
	test_done
}

test_expect_success 'run t0202/test.pl to test Git::I18N.pm' '
	perl "$TEST_DIRECTORY"/t0202/test.pl 2>stderr &&
	test_must_be_empty stderr
'

test_done
