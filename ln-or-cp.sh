#!/bin/sh

install_fallback_ln_cp=
install_symlinks=
no_install_hardlinks=
no_cross_directory_hardlinks=
symlink_target=
while test $# != 0
do
	case "$1" in
	--install-fallback-ln-cp)
		install_fallback_ln_cp="$2"
		shift
		;;
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
		if ! ln -f "$target" "$link"
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
		if ! ln -f -s "$symlink_target" "$link"
		then
			hardlink_or_cp
		fi
	else
		hardlink_or_cp
	fi
}

main_no_fallbacks () {
	if test -n "$no_install_hardlinks" -a -z "$install_symlinks"
	then
		cp "$target" "$link"
	elif test -n "$install_symlinks" -o -n "$no_cross_directory_hardlinks"
	then
		ln -f -s "$symlink_target" "$link"
	elif test -n "$no_install_hardlinks"
	then
		cp "$target" "$link"
	else
		ln -f "$target" "$link"
	fi
}

if test -z "$install_fallback_ln_cp"
then
	# The stricter mode, where we know what we want
	main_no_fallbacks
else
	main_with_fallbacks

fi
