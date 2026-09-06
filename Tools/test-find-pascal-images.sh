#!/bin/zsh

set -eu
setopt pipefail

readonly script_directory=${0:A:h}
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/pascal-finder-test.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

mock_cp2="$temporary_directory/cp2"
cat > "$mock_cp2" <<'MOCK'
#!/bin/zsh
command_name=$1
shift
case $command_name in
  list)
    [[ "$1" == *.dsk ]] || exit 1
    print SYSTEM.APPLE
    print SYSTEM.PASCAL
    print SYSTEM.LIBRARY
    ;;
  read-block)
    dd if=/dev/zero bs=512 count=1 2>/dev/null | xxd
    ;;
  catalog)
    print 'Disk image (Unadorned) - 140KB Pascal "TESTVOL", 10 blocks free'
    ;;
  extract)
    extraction_directory=""
    for argument in "$@"; do
      [[ "$argument" == --exdir=* ]] && extraction_directory=${argument#--exdir=}
    done
    member=${@[-1]}
    [[ -n "$extraction_directory" ]] || exit 1
    mkdir -p "$extraction_directory"
    print -n -- "contents of $member" > "$extraction_directory/${member:t}"
    ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$mock_cp2"

source_directory="$temporary_directory/source"
archive_staging="$temporary_directory/archive"
output_directory="$temporary_directory/results"
mkdir -p "$source_directory" "$archive_staging/nested folder"
print -n 'synthetic disk image' > "$archive_staging/nested folder/test image.dsk"
7z a "$source_directory/collection.zip" "$archive_staging/nested folder/test image.dsk" \
  >/dev/null

CP2_COMMAND="$mock_cp2" "$script_directory/find-pascal-images.sh" \
  --output "$output_directory" "$source_directory" >/dev/null

[[ -f "$output_directory/summary.csv" ]] || fail "summary was not created"
[[ $(wc -l < "$output_directory/summary.csv" | tr -d ' ') == 2 ]] ||
  fail "summary should contain one result"
grep -Fq 'collection.zip!test image.dsk' "$output_directory/summary.csv" ||
  fail "nested archive provenance was not retained"

manifest=("$output_directory"/images/*/manifest.json)
[[ ${#manifest} == 1 && -f ${manifest[1]} ]] || fail "manifest was not created"
[[ $(jq -r .volumeName "${manifest[1]}") == TESTVOL ]] ||
  fail "volume name was not recorded"
[[ $(jq -r '.files.interpreters[0].name' "${manifest[1]}") == SYSTEM.APPLE ]] ||
  fail "interpreter was not recorded"

result_directory=${manifest[1]:h}
[[ $(wc -c < "$result_directory/boot/bootblocks.bin" | tr -d ' ') == 1024 ]] ||
  fail "two logical boot blocks were not combined"
[[ -f "$result_directory/files/SYSTEM.PASCAL" ]] ||
  fail "SYSTEM.PASCAL was not extracted"
[[ -f "$result_directory/files/SYSTEM.LIBRARY" ]] ||
  fail "SYSTEM.LIBRARY was not extracted"

print -- "PASS: Pascal image finder tests"
