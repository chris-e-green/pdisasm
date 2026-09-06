#!/bin/zsh

set -eu
setopt pipefail

readonly script_directory=${0:A:h}
readonly archive_path=${1:-$HOME/pascal}
readonly raw_rows=$(mktemp "${TMPDIR:-/tmp}/allinterpreters.XXXXXX")
trap 'rm -f "$raw_rows"' EXIT HUP INT TERM

if [[ ! -d "$archive_path" ]]; then
  print -u2 -- "error: archive directory does not exist: $archive_path"
  exit 1
fi

failures=0
processed=0
while IFS= read -r -d '' interpreter; do
  (( processed += 1 ))
  if row=$(zsh "$script_directory/getinterpreter.sh" "$interpreter"); then
    print -r -- "$row" >> "$raw_rows"
  else
    (( failures += 1 ))
    print -u2 -- "error: interpreter analysis failed: $interpreter"
  fi
done < <(find "$archive_path" -type f \( \
  -name 'SYSTEM.APPLE' -o \
  -name 'RT*.APPLE' -o \
  -name '128K.APPLE' \
\) -print0)

zsh "$script_directory/header.sh"
gawk -f "$script_directory/deduplicate-interpreters.awk" "$raw_rows"

if (( failures > 0 )); then
  print -u2 -- "error: $failures of $processed interpreter files failed analysis"
  exit 1
fi
