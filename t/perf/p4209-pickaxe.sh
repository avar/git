#!/bin/sh

test_description="Test pickaxe performance"

. ./perf-lib.sh

test_perf_default_repo

# Not --max-count, as that's the number of matching commit, so it's
# unbounded. We want to limit our revision walk here.
from_rev_desc=
from_rev=
if ! test_have_prereq EXPENSIVE
then
	max_count=1000
	from_rev=" $(git rev-list HEAD | head -n $max_count | tail -n 1).."
	from_rev_desc=" <limit-rev>.."
fi

for icase in \
	'' \
	'-i '
do
	# -S (no regex)
	for pattern in \
		'void' \
		'int main' \
		'uncommon' \
		'echo "æ"'
	do
		for opts in \
			'-S'
		do
			test_perf "git log $icase$opts'$pattern'$from_rev_desc" "
				git log --pretty=format:%H $icase$opts'$pattern'$from_rev
			"
		done
	done

	# -S (regex)
	for pattern in  \
		'(void|NULL)' \
		'if *\([^ ]+ & ' \
		'^\s*int \S+ = ' \
		'(echo|printf).*[æð]'
	do
		for opts in \
			'--pickaxe-regex -S'
		do
			test_perf "git log $icase$opts'$pattern'$from_rev_desc" "
				git log --pretty=format:%H $icase$opts'$pattern'$from_rev
			"
		done
	done

	# -G
	for pattern in  \
		'(void|NULL)' \
		'if *\([^ ]+ & ' \
		'^\s*int \S+ = ' \
		'(echo|printf).*[æð]'
	do
		for opts in \
			'-G' \
			'--pickaxe-regex -S'
		do
			test_perf "git log $icase$opts'$pattern'$from_rev_desc" "
				git log --pretty=format:%H $icase$opts'$pattern'$from_rev
			"
		done

		# -G extra
		for opts in \
			'--text -G' \
			'--text --pickaxe-all -G' \
			'--pickaxe-all -G' \
			'--pickaxe-all --pickaxe-regex -S'
		do
			test_perf PERF_EXTRA "git log $icase$opts'$pattern'$from_rev_desc" "
				git log --pretty=format:%H $icase$opts'$pattern'$from_rev
			"
		done
	done
done

test_done
