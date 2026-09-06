#!/bin/zsh

set -eu
setopt pipefail

readonly script_directory=${0:A:h}
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/pdisasm-tools-test.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

assert_equal() {
  local expected=$1
  local actual=$2
  local description=$3
  [[ "$actual" == "$expected" ]] ||
    fail "$description (expected '$expected', got '$actual')"
}

csv_column_count() {
  gawk 'BEGIN { FPAT = "([^,]*)|(\"([^\"]|\"\")+\")" } { print NF }'
}

for command_name in bgrep xxd gawk jq md5; do
  command -v "$command_name" >/dev/null 2>&1 ||
    fail "required test command not found: $command_name"
done

header=$(zsh "$script_directory/header.sh")
assert_equal 186 "$(print -r -- "$header" | csv_column_count)" \
  "header column count"
[[ "$header" == *'"SLDO 8"'* ]] || fail "header contains SLDO 8"

result_directory="$temporary_directory/path with spaces"
fixture_directory="$result_directory/files"
mkdir -p "$fixture_directory"
fixture="$fixture_directory/SYSTEM.APPLE"
print -r -- '{"volumeName":"TEST,VOLUME"}' > "$result_directory/manifest.json"
dd if=/dev/zero of="$fixture" bs=1 count=8192 2>/dev/null

# Put a nonzero 128-word opcode table at 0x0400.
for offset in {0..127}; do
  printf '\x01\x00' | dd of="$fixture" bs=1 seek=$(( 0x0400 + offset * 2 )) conv=notrunc 2>/dev/null
done
# Opcodes 211 and 212 share the interpreter's unimplemented handler.
printf 'df91df91' | xxd -r -p |
  dd of="$fixture" bs=1 seek=$(( 0x0400 + (211 - 128) * 2 )) conv=notrunc 2>/dev/null

# Put a 41-word CSP table at 0x0500, including three reserved null entries.
for offset in {0..40}; do
  value=1
  (( offset >= 13 && offset <= 15 )) && value=0
  printf '%02x00' "$value" | xxd -r -p |
    dd of="$fixture" bs=1 seek=$(( 0x0500 + offset * 2 )) conv=notrunc 2>/dev/null
done
# A CSP entry can use the same unimplemented handler.
printf 'df91' | xxd -r -p |
  dd of="$fixture" bs=1 seek=$(( 0x0500 )) conv=notrunc 2>/dev/null

printf 'a9348d21bf' | xxd -r -p |
  dd of="$fixture" bs=1 seek=$(( 0x0700 )) conv=notrunc 2>/dev/null
printf 'a9568d22bf' | xxd -r -p |
  dd of="$fixture" bs=1 seek=$(( 0x0710 )) conv=notrunc 2>/dev/null

pascal_file="$fixture_directory/SYSTEM.PASCAL"
library_file="$fixture_directory/SYSTEM.LIBRARY"
dd if=/dev/zero of="$pascal_file" bs=1 count=512 2>/dev/null
dd if=/dev/zero of="$library_file" bs=1 count=512 2>/dev/null

# Active slots have a nonzero code length at slot * 4 + 2. Names are at 64 + slot * 8.
printf '0100' | xxd -r -p | dd of="$pascal_file" bs=1 seek=2 conv=notrunc 2>/dev/null
printf '%-8s' 'PASCAL' | dd of="$pascal_file" bs=1 seek=64 conv=notrunc 2>/dev/null
printf '0200' | xxd -r -p | dd of="$pascal_file" bs=1 seek=6 conv=notrunc 2>/dev/null
printf '%-8s' 'EDITOR' | dd of="$pascal_file" bs=1 seek=72 conv=notrunc 2>/dev/null
printf '04' | xxd -r -p | dd of="$pascal_file" bs=1 seek=256 conv=notrunc 2>/dev/null
printf '07' | xxd -r -p | dd of="$pascal_file" bs=1 seek=258 conv=notrunc 2>/dev/null
printf '0100' | xxd -r -p | dd of="$library_file" bs=1 seek=2 conv=notrunc 2>/dev/null
printf '%-8s' 'TURTLEGR' | dd of="$library_file" bs=1 seek=64 conv=notrunc 2>/dev/null
# A stored zero uses the dictionary slot number, which is zero for this entry.

row=$(zsh "$script_directory/getinterpreter.sh" "$fixture")
assert_equal 186 "$(print -r -- "$row" | csv_column_count)" \
  "data column count"
[[ "$row" == '"'"$fixture_directory"'","TEST,VOLUME","","SYSTEM.APPLE",'* ]] ||
  fail "path and manifest volume name are preserved"
[[ "$row" == *',"0x34","0x56",'* ]] ||
  fail "version and flavor signatures are decoded"
[[ "$row" == *',"PASCAL;EDITOR","4;7","TURTLEGR","0","0x34","0x56",'* ]] ||
  fail "companion segment names and numbers are emitted in slot order"
[[ "$row" == *',"0x0400","0x0500","0x0001","0x0001",'* ]] ||
  fail "offsets and table words retain hexadecimal formatting"
[[ "$row" == *',"UNIMPL","UNIMPL",'* ]] ||
  fail "opcodes 211 and 212 use the UNIMPL representation"
[[ "$row" == *',"UNIMPL","0x0001",'* ]] ||
  fail "CSP entries sharing the unimplemented handler use UNIMPL"
[[ "$row" == *',"RSRVD","RSRVD","RSRVD",'* ]] ||
  fail "zero handler addresses use the RSRVD representation"
[[ "$row" != *'"0x91df"'* && "$row" != *'"0x0000"'* ]] ||
  fail "raw unimplemented and reserved addresses must not remain"

override_row=$(zsh "$script_directory/getinterpreter.sh" --volume-name OVERRIDE "$fixture")
[[ "$override_row" == '"'"$fixture_directory"'","OVERRIDE","","SYSTEM.APPLE",'* ]] ||
  fail "explicit volume-name override takes precedence"

short_fixture="$temporary_directory/short.bin"
dd if=/dev/zero of="$short_fixture" bs=1 count=64 2>/dev/null
if zsh "$script_directory/getinterpreter.sh" "$short_fixture" >/dev/null 2>&1; then
  fail "a file without a CSP table must be rejected"
fi

bad_directory="$temporary_directory/bad-result"
mkdir -p "$bad_directory"
cp "$short_fixture" "$bad_directory/SYSTEM.APPLE"
duplicate_result="$temporary_directory/duplicate-result"
duplicate_directory="$duplicate_result/files"
mkdir -p "$duplicate_directory"
cp "$fixture_directory"/* "$duplicate_directory/"
print -r -- '{"volumeName":"DUPLICATE"}' > "$duplicate_result/manifest.json"
batch_errors="$temporary_directory/batch-errors.txt"
if batch_output=$(zsh "$script_directory/allinterpreters.sh" "$temporary_directory" \
    2>"$batch_errors"); then
  fail "batch analysis must report a nonzero status when an interpreter fails"
fi
assert_equal 2 "$(print -r -- "$batch_output" | wc -l | tr -d ' ')" \
  "batch analysis continues and combines duplicate interpreters"
[[ "$batch_output" == *'Also found at:'*'path with spaces/files (volume: TEST,VOLUME)'* ]] ||
  fail "duplicate path and volume are missing from the comment"
grep -Fq '1 of 3 interpreter files failed analysis' "$batch_errors" ||
  fail "batch failure summary is missing"

if zsh "$script_directory/allinterpreters.sh" "$temporary_directory/missing" >/dev/null 2>&1; then
  fail "a missing archive directory must be rejected"
fi

print -- "PASS: tool regression tests"
