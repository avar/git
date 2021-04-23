#!/bin/sh

test_description='test show-branch'

GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME=main
export GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME

. ./test-lib.sh

test_expect_success 'setup' '
	numbers="1 2 3 4 5 6 7 8 9 10" &&
	test_commit initial &&
	for i in $numbers
	do
		git checkout -b branch$i main &&
		test_commit branch$i &&
		echo branch$i >>branches
	done
'

cat > expect << EOF
! [branch1] branch1
 ! [branch2] branch2
  ! [branch3] branch3
   ! [branch4] branch4
    ! [branch5] branch5
     ! [branch6] branch6
      ! [branch7] branch7
       ! [branch8] branch8
        ! [branch9] branch9
         * [branch10] branch10
----------
         * [branch10] branch10
        +  [branch9] branch9
       +   [branch8] branch8
      +    [branch7] branch7
     +     [branch6] branch6
    +      [branch5] branch5
   +       [branch4] branch4
  +        [branch3] branch3
 +         [branch2] branch2
+          [branch1] branch1
+++++++++* [branch10^] initial
EOF

test_expect_success 'show-branch with more than 8 branches' '
	git show-branch $(cat branches) >out &&
	test_cmp expect out

'

test_expect_success 'show-branch with showbranch.default' '
	for i in $numbers; do
		test_config showbranch.default branch$i --add
	done &&
	git show-branch >out &&
	test_cmp expect out
'

test_expect_success 'show-branch --color output' '
	cat >expect.raw <<-\EOF &&
	> <RED>!<RESET> [branch1] branch1
	>  <GREEN>!<RESET> [branch2] branch2
	>   <YELLOW>!<RESET> [branch3] branch3
	>    <BLUE>!<RESET> [branch4] branch4
	>     <MAGENTA>!<RESET> [branch5] branch5
	>      <CYAN>!<RESET> [branch6] branch6
	>       <BOLD;RED>!<RESET> [branch7] branch7
	>        <BOLD;GREEN>!<RESET> [branch8] branch8
	>         <BOLD;YELLOW>!<RESET> [branch9] branch9
	>          <BOLD;BLUE>*<RESET> [branch10] branch10
	> ----------
	>          <BOLD;BLUE>*<RESET> [branch10] branch10
	>         <BOLD;YELLOW>+<RESET>  [branch9] branch9
	>        <BOLD;GREEN>+<RESET>   [branch8] branch8
	>       <BOLD;RED>+<RESET>    [branch7] branch7
	>      <CYAN>+<RESET>     [branch6] branch6
	>     <MAGENTA>+<RESET>      [branch5] branch5
	>    <BLUE>+<RESET>       [branch4] branch4
	>   <YELLOW>+<RESET>        [branch3] branch3
	>  <GREEN>+<RESET>         [branch2] branch2
	> <RED>+<RESET>          [branch1] branch1
	> <RED>+<RESET><GREEN>+<RESET><YELLOW>+<RESET><BLUE>+<RESET><MAGENTA>+<RESET><CYAN>+<RESET><BOLD;RED>+<RESET><BOLD;GREEN>+<RESET><BOLD;YELLOW>+<RESET><BOLD;BLUE>*<RESET> [branch10^] initial
	EOF
	git show-branch --color=always $(cat branches) >out.raw &&
	test_decode_color <out.raw >out &&
	sed -e "s/^> //" <expect.raw >expect &&
	test_cmp expect out
'

test_done
