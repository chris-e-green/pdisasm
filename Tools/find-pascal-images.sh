#!/bin/zsh

set -u
setopt pipefail extendedglob

readonly program_name=$0
readonly script_directory=${0:A:h}
readonly cp2_command=${CP2_COMMAND:-cp2}
readonly seven_zip_command=${SEVEN_ZIP_COMMAND:-7z}

source_directory=""
output_directory="$script_directory/pascal-results"
max_depth=6
max_archive_bytes=$(( 4 * 1024 * 1024 * 1024 ))
probe_all=false

usage() {
  cat >&2 <<EOF
usage: $program_name [options] source-directory

options:
  --output DIR              result directory (default: $output_directory)
  --max-depth N             nested archive limit (default: $max_depth)
  --max-archive-bytes N     expanded archive limit (default: $max_archive_bytes)
  --probe-all               try unknown/extensionless files as disks and archives
  -h, --help                show this help
EOF
}

while (( $# > 0 )); do
  case $1 in
    --output)
      (( $# >= 2 )) || { usage; exit 64; }
      output_directory=$2
      shift 2
      ;;
    --max-depth)
      (( $# >= 2 )) || { usage; exit 64; }
      max_depth=$2
      shift 2
      ;;
    --max-archive-bytes)
      (( $# >= 2 )) || { usage; exit 64; }
      max_archive_bytes=$2
      shift 2
      ;;
    --probe-all)
      probe_all=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      print -u2 -- "error: unknown option: $1"
      usage
      exit 64
      ;;
    *)
      [[ -z "$source_directory" ]] || { usage; exit 64; }
      source_directory=$1
      shift
      ;;
  esac
done

[[ -n "$source_directory" ]] || { usage; exit 64; }
[[ -d "$source_directory" ]] || {
  print -u2 -- "error: source directory does not exist: $source_directory"
  exit 66
}
[[ "$max_depth" == <-> ]] || {
  print -u2 -- "error: --max-depth must be a nonnegative integer"
  exit 64
}
[[ "$max_archive_bytes" == <-> ]] || {
  print -u2 -- "error: --max-archive-bytes must be a nonnegative integer"
  exit 64
}

for command_name in "$cp2_command" "$seven_zip_command" awk jq shasum xxd; do
  command -v "$command_name" >/dev/null 2>&1 || {
    print -u2 -- "error: required command not found: $command_name"
    exit 69
  }
done

source_directory=${source_directory:A}
mkdir -p "$output_directory"
output_directory=${output_directory:A}
if [[ "$output_directory" == "$source_directory" ||
      "$output_directory" == "$source_directory"/* ]]; then
  print -u2 -- "error: output directory must not be inside the source tree"
  exit 64
fi

readonly results_directory="$output_directory/images"
readonly summary_file="$output_directory/summary.csv"
readonly errors_file="$output_directory/errors.tsv"
readonly temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/pascal-image-scan.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM
mkdir -p "$results_directory"

csv_row() {
  local -a escaped
  local value
  for value in "$@"; do
    escaped+=("\"${value//\"/\"\"}\"")
  done
  print -r -- ${(j:,:)escaped}
}

if [[ ! -f "$summary_file" ]]; then
  csv_row Source ImageSHA256 VolumeName InterpreterFilename InterpreterSHA256 \
    PascalSHA256 LibrarySHA256 BootBlocksSHA256 ResultDirectory > "$summary_file"
fi
[[ -f "$errors_file" ]] || print -r -- $'source\tstage\tdiagnostic' > "$errors_file"

record_error() {
  local provenance=$1
  local stage=$2
  local diagnostic=${3//$'\t'/ }
  diagnostic=${diagnostic//$'\n'/ }
  print -r -- "$provenance"$'\t'"$stage"$'\t'"$diagnostic" >> "$errors_file"
}

sha256() {
  shasum -a 256 -- "$1" | awk '{print $1}'
}

file_size() {
  stat -f %z -- "$1"
}

is_disk_hint() {
  local lower=${(L)1}
  [[ "$lower" == *.dsk || "$lower" == *.do || "$lower" == *.po ||
     "$lower" == *.2mg || "$lower" == *.woz || "$lower" == *.nib ||
     "$lower" == *.hdv || "$lower" == *.img || "$lower" == *.sdk ]]
}

is_archive_hint() {
  local lower=${(L)1}
  [[ "$lower" == *.zip || "$lower" == *.7z || "$lower" == *.rar ||
     "$lower" == *.tar || "$lower" == *.tgz || "$lower" == *.tar.gz ||
     "$lower" == *.gz || "$lower" == *.bz2 || "$lower" == *.xz ||
     "$lower" == *.shk ]]
}

catalog_image() {
  "$cp2_command" list "$1" 2>/dev/null
}

read_block() {
  local image=$1
  local block=$2
  local output=$3
  "$cp2_command" read-block "$image" "$block" 2>/dev/null | xxd -r > "$output"
  [[ -s "$output" ]]
}

extract_member() {
  local image=$1
  local member=$2
  local output=$3
  (( work_counter++ ))
  local extraction_directory="$temporary_root/member-$work_counter"
  mkdir -p "$extraction_directory"
  "$cp2_command" extract --raw --no-add-ext --strip-paths \
    --exdir="$extraction_directory" "$image" "$member" >/dev/null 2>&1 || return 1
  local extracted=("$extraction_directory"/*(N.))
  (( ${#extracted} == 1 )) || return 1
  cp "${extracted[1]}" "$output"
}

volume_name() {
  "$cp2_command" catalog "$1" 2>/dev/null |
    sed -n 's/^Disk image .* Pascal "\([^"]*\)".*/\1/p' | head -1
}

append_source() {
  local sources_file=$1
  local provenance=$2
  touch "$sources_file"
  grep -Fqx -- "$provenance" "$sources_file" 2>/dev/null ||
    print -r -- "$provenance" >> "$sources_file"
}

remove_summary_for_hash() {
  local image_hash=$1
  local temporary_summary="$temporary_root/summary-$image_hash.csv"
  grep -Fv -- ",\"$image_hash\"," "$summary_file" > "$temporary_summary" || true
  mv "$temporary_summary" "$summary_file"
}

inspect_disk() {
  local image=$1
  local provenance=$2
  local catalog=$3
  local -a entries interpreters
  entries=(${(f)catalog})
  local pascal_member=""
  local library_member=""
  local entry base upper

  for entry in "${entries[@]}"; do
    entry=${entry%$'\r'}
    base=${entry:t}
    upper=${(U)base}
    case "$upper" in
      SYSTEM.PASCAL) pascal_member=$entry ;;
      SYSTEM.LIBRARY) library_member=$entry ;;
      SYSTEM.APPLE|128K.APPLE|RT*.APPLE) interpreters+=("$entry") ;;
    esac
  done
  [[ -n "$pascal_member" && ${#interpreters} -gt 0 ]] || return 1

  local image_hash=$(sha256 "$image")
  local result_directory="$results_directory/$image_hash"
  local files_directory="$result_directory/files"
  local boot_directory="$result_directory/boot"
  mkdir -p "$files_directory" "$boot_directory"
  append_source "$result_directory/sources.txt" "$provenance"

  if [[ -f "$result_directory/manifest.json" ]] &&
      [[ $(jq -r '.schemaVersion // 0' "$result_directory/manifest.json" 2>/dev/null) == 2 ]]; then
    print -- "duplicate  $provenance"
    return 0
  fi
  remove_summary_for_hash "$image_hash"

  local block0="$boot_directory/boot-block-0.bin"
  local block1="$boot_directory/boot-block-1.bin"
  if ! read_block "$image" 0 "$block0" || ! read_block "$image" 1 "$block1"; then
    record_error "$provenance" boot "catalog matched but logical boot blocks could not be read"
    rm -f "$block0" "$block1"
    return 1
  fi
  cat "$block0" "$block1" > "$boot_directory/bootblocks.bin"

  local pascal_output="$files_directory/SYSTEM.PASCAL"
  extract_member "$image" "$pascal_member" "$pascal_output" || {
    record_error "$provenance" extract "failed to extract $pascal_member"
    return 1
  }

  local library_output=""
  if [[ -n "$library_member" ]]; then
    library_output="$files_directory/SYSTEM.LIBRARY"
    extract_member "$image" "$library_member" "$library_output" || {
      record_error "$provenance" extract "failed to extract $library_member"
      return 1
    }
  fi

  local -a interpreter_json
  local interpreter_member interpreter_name interpreter_output interpreter_hash
  for interpreter_member in "${interpreters[@]}"; do
    interpreter_name=${interpreter_member:t}
    interpreter_output="$files_directory/$interpreter_name"
    extract_member "$image" "$interpreter_member" "$interpreter_output" || {
      record_error "$provenance" extract "failed to extract $interpreter_member"
      continue
    }
    interpreter_hash=$(sha256 "$interpreter_output")
    interpreter_json+=("$(jq -n --arg name "$interpreter_name" --arg sha256 "$interpreter_hash" \
      '{name:$name,sha256:$sha256}')")
  done
  (( ${#interpreter_json} > 0 )) || return 1

  local pascal_hash=$(sha256 "$pascal_output")
  local library_hash=""
  [[ -n "$library_output" ]] && library_hash=$(sha256 "$library_output")
  local boot_hash=$(sha256 "$boot_directory/bootblocks.bin")
  local volume=$(volume_name "$image")
  local interpreters_json=$(printf '%s\n' "${interpreter_json[@]}" | jq -s .)

  jq -n \
    --arg imageSHA256 "$image_hash" \
    --arg volumeName "$volume" \
    --arg pascalSHA256 "$pascal_hash" \
    --arg librarySHA256 "$library_hash" \
    --arg bootBlock0SHA256 "$(sha256 "$block0")" \
    --arg bootBlock1SHA256 "$(sha256 "$block1")" \
    --arg bootBlocksSHA256 "$boot_hash" \
    --argjson interpreters "$interpreters_json" \
    '{schemaVersion:2,imageSHA256:$imageSHA256,volumeName:$volumeName,
      files:{systemPascal:{sha256:$pascalSHA256},systemLibrary:
        (if $librarySHA256 == "" then null else {sha256:$librarySHA256} end),
        interpreters:$interpreters},
      boot:{block0SHA256:$bootBlock0SHA256,block1SHA256:$bootBlock1SHA256,
        combinedSHA256:$bootBlocksSHA256}}' > "$result_directory/manifest.json"

  for interpreter_member in "${interpreters[@]}"; do
    interpreter_name=${interpreter_member:t}
    interpreter_output="$files_directory/$interpreter_name"
    [[ -f "$interpreter_output" ]] || continue
    csv_row "$provenance" "$image_hash" "$volume" "$interpreter_name" \
      "$(sha256 "$interpreter_output")" "$pascal_hash" "$library_hash" \
      "$boot_hash" "$result_directory" >> "$summary_file"
  done
  print -- "found      $provenance"
  return 0
}

validate_archive_paths() {
  local archive=$1
  local member_path
  local listing=$("$seven_zip_command" l -slt -- "$archive" 2>/dev/null) || return 1
  local after_separator=false
  while IFS= read -r member_path; do
    if [[ "$member_path" == "----------" ]]; then
      after_separator=true
      continue
    fi
    $after_separator || continue
    [[ "$member_path" == "Path = "* ]] || continue
    member_path=${member_path#Path = }
    [[ "$member_path" != /* && "$member_path" != [A-Za-z]:[\\/]* &&
       "$member_path" != ".." && "$member_path" != ../* &&
       "$member_path" != */../* ]] || return 1
  done <<< "$listing"

  local expanded=$(print -r -- "$listing" |
    awk -F' = ' '/^Size = [0-9]+$/ { total += $2 } END { printf "%.0f", total }')
  (( expanded <= max_archive_bytes ))
}

typeset -i work_counter=0

expand_archive() {
  local archive=$1
  local provenance=$2
  local depth=$3
  (( depth < max_depth )) || {
    record_error "$provenance" archive "maximum archive depth reached"
    return 1
  }
  validate_archive_paths "$archive" || {
    record_error "$provenance" archive "invalid, unsafe, unsupported, or oversized archive"
    return 1
  }

  (( work_counter++ ))
  local extraction_directory="$temporary_root/archive-$work_counter"
  mkdir -p "$extraction_directory"
  "$seven_zip_command" x -y "-o$extraction_directory" -- "$archive" >/dev/null 2>&1 || {
    record_error "$provenance" archive "archive extraction failed"
    return 1
  }

  local member relative
  while IFS= read -r -d '' member; do
    relative=${member#$extraction_directory/}
    process_file "$member" "$provenance!$relative" $(( depth + 1 ))
  done < <(find "$extraction_directory" -type f -print0)
}

expand_shrinkit() {
  local archive=$1
  local provenance=$2
  local depth=$3
  (( depth < max_depth )) || return 1
  (( work_counter++ ))
  local extraction_directory="$temporary_root/shrinkit-$work_counter"
  mkdir -p "$extraction_directory"
  "$cp2_command" extract --raw --no-add-ext --exdir="$extraction_directory" "$archive" \
    >/dev/null 2>&1 || return 1
  local member relative
  while IFS= read -r -d '' member; do
    relative=${member#$extraction_directory/}
    process_file "$member" "$provenance!$relative" $(( depth + 1 ))
  done < <(find "$extraction_directory" -type f -print0)
}

process_file() {
  local file=$1
  local provenance=$2
  local depth=$3
  [[ -f "$file" ]] || return
  (( $(file_size "$file") <= max_archive_bytes )) || {
    record_error "$provenance" size "file exceeds configured size limit"
    return
  }

  local catalog=""
  if is_disk_hint "$file" || $probe_all; then
    catalog=$(catalog_image "$file")
    if [[ -n "$catalog" ]] && inspect_disk "$file" "$provenance" "$catalog"; then
      return
    fi
  fi

  if [[ "${(L)file}" == *.shk ]]; then
    expand_shrinkit "$file" "$provenance" "$depth" ||
      record_error "$provenance" archive "ShrinkIt extraction failed"
  elif is_archive_hint "$file" || $probe_all; then
    expand_archive "$file" "$provenance" "$depth" || true
  fi
}

print -- "Scanning: $source_directory"
print -- "Results:  $output_directory"
while IFS= read -r -d '' source_file; do
  relative=${source_file#$source_directory/}
  process_file "$source_file" "$relative" 0
done < <(find "$source_directory" -type f -print0)

print -- "Complete. Summary: $summary_file"
print -- "Diagnostics:      $errors_file"
