#!/bin/sh
printf '\033c\033]0;%s\a' Distopia
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Distopia.x86_64" "$@"
