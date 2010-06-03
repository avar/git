#!/bin/sh

test_description='Gettext Shell fallbacks'

. ./test-lib.sh

GIT_TEXTDOMAINDIR="$GIT_EXEC_PATH/share/locale"
GIT_INTERNAL_GETTEXT_TEST_FALLBACKS=YesPlease

export GIT_TEXTDOMAINDIR GIT_INTERNAL_GETTEXT_TEST_FALLBACKS

. "$GIT_EXEC_PATH"/git-sh-i18n

test_expect_success 'sanity: $GIT_INTERNAL_GETTEXT_TEST_FALLBACKS is set' '
	test_expect_failure test -z "$GIT_INTERNAL_GETTEXT_TEST_FALLBACKS"
'

test_expect_success 'gettext: our gettext() fallback has pass-through semantics' '
    printf "test" > expect &&
    gettext "test" > actual &&
    test_cmp expect actual &&
    printf "test more words" > expect &&
    gettext "test more words" > actual &&
    test_cmp expect actual
'

test_expect_success 'eval_gettext: our eval_gettext() fallback has pass-through semantics' '
    printf "test" > expect &&
    eval_gettext "test" > actual &&
    test_cmp expect actual &&
    printf "test more words" > expect &&
    eval_gettext "test more words" > actual &&
    test_cmp expect actual
'

test_expect_success 'eval_gettext: our eval_gettext() fallback can interpolate variables' '
    printf "test YesPlease" > expect &&
    eval_gettext "test \$GIT_INTERNAL_GETTEXT_TEST_FALLBACKS" > actual &&
    test_cmp expect actual
'

test_done
