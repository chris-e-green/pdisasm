#!/bin/zsh

set -eu
setopt pipefail C_BASES
readonly program_name=$0

usage() {
  print -u2 -- "usage: $program_name [--volume-name name] interpreter-file"
}

volume_name_override=""
has_volume_name_override=false
while (( $# > 0 )); do
  case $1 in
    --volume-name)
      (( $# >= 2 )) || { usage; exit 64; }
      volume_name_override=$2
      has_volume_name_override=true
      shift 2
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
      (( $# == 1 )) || { usage; exit 64; }
      interpreter_argument=$1
      shift
      ;;
  esac
done

[[ -n ${interpreter_argument:-} ]] || { usage; exit 64; }

for command_name in bgrep xxd gawk md5; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    print -u2 -- "error: required command not found: $command_name"
    exit 69
  fi
done

readonly script_directory=${0:A:h}
readonly interpreter=$interpreter_argument
if [[ ! -f "$interpreter" ]]; then
  print -u2 -- "error: interpreter file does not exist: $interpreter"
  exit 66
fi

checksum() {
  md5 -q -- "$1"
}

signature_value() {
  local pattern=$1
  local label=$2
  local -a offsets
  offsets=(${(f)"$(bgrep -f "$pattern" -m "$script_directory/mask.bin" "$interpreter" |
    awk -F: '{ value=$2; gsub(/[[:space:]]/, "", value); print value }')"})

  if (( ${#offsets} == 0 )); then
    print -r -- 0
    return
  fi
  if (( ${#offsets} > 1 )); then
    print -u2 -- "error: multiple $label signatures found in: $interpreter"
    return 1
  fi

  local offset=$(( 16#${offsets[1]} + 1 ))
  local value=$(xxd -p -l 1 -s "$offset" "$interpreter")
  if [[ ${#value} != 2 ]]; then
    print -u2 -- "error: truncated $label signature in: $interpreter"
    return 1
  fi
  print -r -- "0x$value"
}

highest_segment_version() {
  local file=$1
  xxd -p -s 0x100 -l 32 -c 0 "$file" |
    sed 's/\([A-Fa-f0-9]\{2\}\)/& /g' |
    gawk '{
      for (i=2; i<=NF; i+=2) {
        value = strtonum("0x" $i)
        if (value > maximum) maximum = value
      }
    }
    END { printf "%X\n", rshift(maximum, 5) }'
}

segment_names() {
  local file=$1
  local size=$(wc -c < "$file" | tr -d '[:space:]')
  if (( size < 192 )); then
    print -u2 -- "error: codefile is too small for a segment dictionary: $file"
    return 1
  fi

  local -a names
  local slot length_bytes low_byte high_byte name
  for slot in {0..15}; do
    length_bytes=$(xxd -p -l 2 -s $(( slot * 4 + 2 )) "$file")
    low_byte=${length_bytes[1,2]}
    high_byte=${length_bytes[3,4]}
    if [[ "$low_byte$high_byte" != "0000" ]]; then
      name=$(xxd -p -l 8 -s $(( 64 + slot * 8 )) "$file" |
        gawk '{
          for (i=1; i<=length($0); i+=2) {
            value = and(strtonum("0x" substr($0, i, 2)), 0x7f)
            if (value != 0) printf "%c", value
          }
        }' | LC_ALL=C sed 's/[[:space:]]*$//')
      names+=("$name")
    fi
  done
  print -r -- ${(j:;:)names}
}

segment_numbers() {
  local file=$1
  local size=$(wc -c < "$file" | tr -d '[:space:]')
  if (( size < 288 )); then
    print -u2 -- "error: codefile is too small for segment information: $file"
    return 1
  fi

  local -a numbers
  local slot length_bytes segment_byte segment_number
  for slot in {0..15}; do
    length_bytes=$(xxd -p -l 2 -s $(( slot * 4 + 2 )) "$file")
    if [[ "$length_bytes" != "0000" ]]; then
      segment_byte=$(xxd -p -l 1 -s $(( 256 + slot * 2 )) "$file")
      segment_number=$(( 16#$segment_byte ))
      (( segment_number == 0 )) && segment_number=$slot
      numbers+=("$segment_number")
    fi
  done
  print -r -- ${(j:;:)numbers}
}

read_words() {
  local offset=$1
  local count=$2
  xxd -e -g 2 -c $(( count * 2 )) -s "$offset" -l $(( count * 2 )) "$interpreter" |
    sed 's/  .*//; s/^[^:]*: //'
}

format_handler_words() {
  local unimplemented_handler=$1
  shift
  local word
  for word in "$@"; do
    if [[ "$word" == "0000" ]]; then
      print -r -- RSRVD
    elif [[ "$word" == "$unimplemented_handler" ]]; then
      print -r -- UNIMPL
    else
      print -r -- "0x$word"
    fi
  done
}

csv_row() {
  local -a escaped
  local value
  for value in "$@"; do
    escaped+=("\"${value//\"/\"\"}\"")
  done
  print -r -- ${(j:,:)escaped}
}

readonly interpreter_path=${interpreter:h}
readonly interpreter_name=${interpreter:t}
readonly library_file="$interpreter_path/SYSTEM.LIBRARY"
readonly pascal_file="$interpreter_path/SYSTEM.PASCAL"
readonly manifest_file="${interpreter_path:h}/manifest.json"

volume_name=""
if $has_volume_name_override; then
  volume_name=$volume_name_override
elif [[ -f "$manifest_file" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    print -u2 -- "error: jq is required to read result manifest: $manifest_file"
    exit 69
  fi
  if ! volume_name=$(jq -er '.volumeName // "" | strings' "$manifest_file" 2>/dev/null); then
    print -u2 -- "error: unable to read volume name from manifest: $manifest_file"
    exit 65
  fi
fi

library_checksum=none
library_version=0
library_segments=""
library_segment_numbers=""
if [[ -f "$library_file" ]]; then
  library_checksum=$(checksum "$library_file")
  library_version=$(highest_segment_version "$library_file")
  library_segments=$(segment_names "$library_file")
  library_segment_numbers=$(segment_numbers "$library_file")
fi

pascal_checksum=none
pascal_version=0
pascal_segments=""
pascal_segment_numbers=""
if [[ -f "$pascal_file" ]]; then
  pascal_checksum=$(checksum "$pascal_file")
  pascal_version=$(highest_segment_version "$pascal_file")
  pascal_segments=$(segment_names "$pascal_file")
  pascal_segment_numbers=$(segment_numbers "$pascal_file")
fi

candidate_offsets=(0x0100 0x0500 0x0600 0x3100)
matching_offsets=()
matching_tables=()
for candidate_offset in $candidate_offsets; do
  words=$(read_words "$candidate_offset" 41)
  word_array=(${=words})
  if (( ${#word_array} == 41 )) &&
      [[ "$words" == *[1-9a-fA-F]* ]] &&
      [[ "$words" == *"0000 0000 0000"* ]]; then
    matching_offsets+=("$candidate_offset")
    matching_tables+=("$words")
  fi
done

if (( ${#matching_offsets} == 0 )); then
  print -u2 -- "error: no CSP table found in: $interpreter"
  exit 65
fi
if (( ${#matching_offsets} > 1 )); then
  print -u2 -- "error: multiple CSP tables found in: $interpreter (${(j:, :)matching_offsets})"
  exit 65
fi

csp_offset=${matching_offsets[1]}
opcode_offset=$(( csp_offset - 0x100 ))
opcode_words=$(read_words "$opcode_offset" 128)
opcode_table=(${=opcode_words})
csp_table=(${=matching_tables[1]})

if (( ${#opcode_table} != 128 )); then
  print -u2 -- "error: truncated opcode table in: $interpreter"
  exit 65
fi

unimplemented_handler=${opcode_table[$(( 211 - 128 + 1 ))]}
opcode_212_handler=${opcode_table[$(( 212 - 128 + 1 ))]}
if [[ "$unimplemented_handler" != "$opcode_212_handler" ]]; then
  print -u2 -- "error: opcodes 211 and 212 use different handlers in: $interpreter"
  exit 65
fi

opcode_table=("${(@f)$(format_handler_words "$unimplemented_handler" "${opcode_table[@]}")}")
csp_table=("${(@f)$(format_handler_words "$unimplemented_handler" "${csp_table[@]}")}")
printf -v opcode_offset_hex '0x%04X' "$opcode_offset"
printf -v csp_offset_hex '0x%04X' "$csp_offset"

fields=(
  "$interpreter_path" "$volume_name" "" "$interpreter_name" "$(checksum "$interpreter")"
  "$pascal_checksum" "$library_checksum"
  "$pascal_segments" "$pascal_segment_numbers"
  "$library_segments" "$library_segment_numbers"
  "$(signature_value "$script_directory/version.bin" version)"
  "$(signature_value "$script_directory/flavor.bin" flavor)"
  "$pascal_version" "$library_version" "$opcode_offset_hex" "$csp_offset_hex"
)
fields+=("${opcode_table[@]}")
fields+=("${csp_table[@]}")
csv_row "${fields[@]}"
