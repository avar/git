#!/bin/sh

target="$1"
link="$2"

ln "$target" "$link" 2>/dev/null ||
ln -s "$target" "$link" 2>/dev/null ||
cp "$target" "$link"
