#!/bin/sh

install_symlinks=
no_install_hardlinks=
no_cross_directory_hardlinks=
symlink_target=
while test $# != 0
do
	case "$1" in
	--install-symlinks)
		install_symlinks="$2"
		shift
		;;
	--no-install-hardlinks)
		no_install_hardlinks="$2"
		shift
		;;
	--no-cross-directory-hardlinks)
		no_cross_directory_hardlinks="$2"
		shift
		;;
	--symlink-target)
		symlink_target="$2"
		shift
		;;
	*)
		break
		;;
	esac
	shift
done

target="$1"
if test -z "$symlink_target"
then
	symlink_target="$target"
fi
link="$2"

hardlink_or_cp () {
	if test -z "$no_install_hardlinks" -a -z "$no_cross_directory_hardlinks"
	then
		if ! ln "$target" "$link"
		then
			cp "$target" "$link"
		fi

	else
		cp "$target" "$link"
	fi
}

main_with_fallbacks () {
	if test -n "$install_symlinks" -o -n "$no_install_hardlinks"
	then
		if ! ln -s "$symlink_target" "$link"
		then
			hardlink_or_cp
		fi
	else
		hardlink_or_cp
	fi
}

main_with_fallbacks
