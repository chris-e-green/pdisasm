#!/bin/sh

set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 disk-image [output-file]" >&2
  exit 64
fi

for command_name in cp2 xxd; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: required command not found: $command_name" >&2
    exit 69
  fi
done

input=$1
if [ ! -f "$input" ]; then
  echo "error: disk image does not exist: $input" >&2
  exit 66
fi

if [ "$#" -eq 2 ]; then
  output=$2
else
  output="files/$(basename "$input")/bootsect.bin"
fi

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/extractboot.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

cp2 read-block "$input" 0 > "$temporary_directory/block0.hex"
cp2 read-block "$input" 1 > "$temporary_directory/block1.hex"
xxd -r "$temporary_directory/block0.hex" "$temporary_directory/block0.bin"
xxd -r "$temporary_directory/block1.hex" "$temporary_directory/block1.bin"

mkdir -p "$(dirname "$output")"
cat "$temporary_directory/block0.bin" "$temporary_directory/block1.bin" > "$output"
echo "$output"

