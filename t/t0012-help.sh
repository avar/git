#!/bin/sh

test_description='help'

. ./test-lib.sh

configure_help () {
	test_config help.format html &&

	# Unless the path has "://" in it, Git tries to make sure
	# the documentation directory locally exists. Avoid it as
	# we are only interested in seeing an attempt to correctly
	# invoke a help browser in this test.
	test_config help.htmlpath test://html &&

	# Name a custom browser
	test_config browser.test.cmd ./test-browser &&
	test_config help.browser test
}

test_expect_success "setup" '
	# Just write out which page gets requested
	write_script test-browser <<-\EOF
	echo "$*" >test-browser.log
	EOF
'

# make sure to exercise these code paths, the output is a bit tricky
# to verify
test_expect_success 'basic help commands' '
	git help >/dev/null &&
	git help -a --no-verbose >/dev/null &&
	git help -g >/dev/null &&
	git help -a >/dev/null
'

test_expect_success 'invalid usage' '
	test_expect_code 129 git help -c git-add &&
	test_expect_code 129 git help -g git-add &&

	test_expect_code 129 git help -a -c &&
	test_expect_code 129 git help -g -c &&

	test_expect_code 129 git help --user-formats git-add
'

test_expect_success "works for commands and guides by default" '
	configure_help &&
	git help status &&
	echo "test://html/git-status.html" >expect &&
	test_cmp expect test-browser.log &&
	git help revisions &&
	echo "test://html/gitrevisions.html" >expect &&
	test_cmp expect test-browser.log
'

test_expect_success "--exclude-guides does not work for guides" '
	>test-browser.log &&
	test_must_fail git help --exclude-guides revisions &&
	test_must_be_empty test-browser.log
'

test_expect_success "--help does not work for guides" "
	cat <<-EOF >expect &&
		git: 'revisions' is not a git command. See 'git --help'.
	EOF
	test_must_fail git revisions --help 2>actual &&
	test_cmp expect actual
"

test_expect_success 'git help' '
	git help >help.output &&
	test_i18ngrep "^   clone  " help.output &&
	test_i18ngrep "^   add    " help.output &&
	test_i18ngrep "^   log    " help.output &&
	test_i18ngrep "^   commit " help.output &&
	test_i18ngrep "^   fetch  " help.output
'

test_expect_success 'git help -a' '
	git help -a >help.output &&
	grep "^Main Porcelain Commands" help.output &&
	grep "^User-facing file formats" help.output
'

test_expect_success 'git help -g' '
	git help -g >help.output &&
	test_i18ngrep "^   everyday   " help.output &&
	test_i18ngrep "^   tutorial   " help.output
'

test_expect_success 'git help --formats' '
	git help --user-formats >help.output &&
	grep "^   gitattributes   " help.output &&
	grep "^   gitmailmap   " help.output
'

test_expect_success 'git help -c' '
	git help -c >help.output &&
	cat >expect <<-\EOF &&

	'"'"'git help config'"'"' for more information
	EOF
	grep -v -E \
		-e "^[^.]+\.[^.]+$" \
		-e "^[^.]+\.[^.]+\.[^.]+$" \
		help.output >actual &&
	test_cmp expect actual
'

test_expect_success 'git help --config-for-completion-vars' '
	git help -c >human &&
	grep -E \
	     -e "^[^.]+\.[^.]+$" \
	     -e "^[^.]+\.[^.]+\.[^.]+$" human |
	     sed -e "s/\*.*//" -e "s/<.*//" |
	     sort -u >human.munged &&

	git help --config-for-completion-vars >vars &&
	test_cmp human.munged vars
'

test_expect_success 'git help --config-for-completion-sections' '
	git help -c >human &&
	grep -E \
	     -e "^[^.]+\.[^.]+$" \
	     -e "^[^.]+\.[^.]+\.[^.]+$" human |
	     sed -e "s/\..*//" |
	     sort -u >human.munged &&

	git help --config-for-completion-sections >sections &&
	test_cmp human.munged sections
'

test_expect_success 'generate builtin list' '
	git --list-cmds=builtins >builtins
'

while read builtin
do
	test_expect_success "$builtin can handle -h" '
		test_expect_code 129 git $builtin -h >output 2>&1 &&
		test_i18ngrep usage output
	'
done <builtins

test_done
