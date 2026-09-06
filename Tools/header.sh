#!/bin/zsh

set -eu

columns=(
  Path VolumeName Comment Filename InterpreterMD5 PascalMD5 LibraryMD5
  PascalSegments PascalSegmentNumbers LibrarySegments LibrarySegmentNumbers
  InterpreterVersion InterpreterFlavor PascalSegmentVersion
  LibrarySegmentVersion OpcodeTableOffset CSPTableOffset
)

opcode_names=(
  ABI ABR ADI ADR LAND DIF DVI DVR CHK FLO FLT INN INT LOR MODI MPI MPR
  NGI NGR LNOT SRS SBI SBR SGS SQI SQR STO IXS UNI LDE CSP LDCN ADJ FJP
  INC IND IXA LAO LSA LAE MOV LDO SAS SRO XJP RNP CIP CEQL CGEQ CGTR LDA
  LDC CLEQ CLES LOD CNEQ STR UJP LDP STP LDM STM LDB STB IXP RBP CBP EQUI
  GEQI GRTI LLA LDCI LEQI LESI LDL NEQI STL CXP CLP CGP LPA STE NOP OP211
  OP212 BPT XIT NOP215
)

opcode=128
for name in $opcode_names; do
  columns+=("$name $opcode")
  (( opcode++ ))
done
for index in {1..16}; do columns+=("SLDL $index"); done
for index in {1..16}; do columns+=("SLDO $index"); done
for index in {0..7}; do columns+=("SIND $index"); done

csp_names=(
  IOC NEW MOVL MOVR EXIT UREAD UWRT IDS TRS TIME FLCH SCAN USTAT
  RSRVD13 RSRVD14 RSRVD15 RSRVD16 RSRVD17 RSRVD18 RSRVD19 RSRVD20
  LDS ULS TNC RND SIN COS LOG ATAN LN EXP SQRT MRK RLS IOR UBUSY POT
  UWAIT UCLR HLT MEMAV
)
columns+=($csp_names)

csv_fields=()
for value in $columns; do
  csv_fields+=("\"${value//\"/\"\"}\"")
done
print -r -- ${(j:,:)csv_fields}
