//
//  StandardProcedures.swift
//  pdisasm
//
//  Defines the in-built standard procedures available in the p-system,
//  which can be called from assembly code or from Pascal code via the `SYSTEM` unit.
//
//  Created by Christopher Green on 29/4/2026.
//


let cspProcs: [Int: (String, [Identifier], String)] = [
    0: ("IOC", [], ""),
    1: (
        "NEW",
        [
            Identifier(name: "PTR", type: "POINTER"),
            Identifier(name: "SIZE", type: "INTEGER"),
        ], ""
    ),
    2: (
        "MOVELEFT",
        [
            Identifier(name: "SRCADDR", type: "POINTER"),
            Identifier(name: "SRCOFFS", type: "INTEGER"),
            Identifier(name: "DESTADDR", type: "POINTER"),
            Identifier(name: "DESTOFFS", type: "INTEGER"),
            Identifier(name: "COUNT", type: "INTEGER"),
        ], ""
    ),
    3: (
        "MOVERIGHT",
        [
            Identifier(name: "SRCADDR", type: "POINTER"),
            Identifier(name: "SRCOFFS", type: "INTEGER"),
            Identifier(name: "DESTADDR", type: "POINTER"),
            Identifier(name: "DESTOFFS", type: "INTEGER"),
            Identifier(name: "COUNT", type: "INTEGER"),
        ], ""
    ),
    4: (
        "EXIT",
        [
            Identifier(name: "SEGMENT", type: "INTEGER"),
            Identifier(name: "PROCEDURE", type: "INTEGER"),
        ], ""
    ),
    5: (
        "UNITREAD",
        [
            Identifier(name: "UNIT", type: "INTEGER"),
            Identifier(name: "BUFFADDR", type: "POINTER"),
            Identifier(name: "BUFFOFFS", type: "INTEGER"),
            Identifier(name: "BYTCOUNT", type: "INTEGER"),
            Identifier(name: "BLOCKNUM", type: "INTEGER"),
            Identifier(name: "MODE", type: "INTEGER"),
        ], ""
    ),
    6: (
        "UNITWRITE",
        [
            Identifier(name: "UNIT", type: "INTEGER"),
            Identifier(name: "BUFFADDR", type: "POINTER"),
            Identifier(name: "BUFFOFFS", type: "INTEGER"),
            Identifier(name: "BYTCOUNT", type: "INTEGER"),
            Identifier(name: "BLOCKNUM", type: "INTEGER"),
            Identifier(name: "MODE", type: "INTEGER"),
        ], ""
    ),
    7: (
        "IDSEARCH",
        [
            Identifier(name: "SYMCURSOR", type: "0..1023"),
            Identifier(name: "SYMBUF", type: "PACKED ARRAY[0..1023] OF CHAR"),
        ], ""
    ),
    8: (
        "TREESEARCH",
        [
            Identifier(name: "ROOTP", type: "^NODE"),
            Identifier(name: "FOUNDP", type: "^NODE"),
            Identifier(name: "TARGET", type: "PACKED ARRAY [1..8] OF CHAR"),
        ], "INTEGER"
    ),
    9: (
        "TIME",
        [
            Identifier(name: "TIME1", type: "INTEGER"),
            Identifier(name: "TIME2", type: "INTEGER"),
        ], ""
    ),
    10: (
        "FILLCHAR",
        [
            Identifier(name: "DESTADDR", type: "POINTER"),
            Identifier(name: "DESTOFFS", type: "INTEGER"),
            Identifier(name: "COUNT", type: "INTEGER"),
            Identifier(name: "SRC", type: "CHAR"),
        ], ""
    ),
    11: (
        "SCAN",
        [
            Identifier(name: "JUNK", type: "INTEGER"),
            Identifier(name: "DESTADDR", type: "POINTER"),
            Identifier(name: "DESTOFFS", type: "INTEGER"),
            Identifier(name: "CH", type: "CHAR"),
            Identifier(name: "CHECK", type: "INTEGER"),
            Identifier(name: "COUNT", type: "INTEGER"),
        ], "INTEGER"
    ),
    12: (
        "UNITSTATUS",
        [
            Identifier(name: "UNIT", type: "INTEGER"),
            Identifier(name: "STATADDR", type: "POINTER"),
            Identifier(name: "STATOFFS", type: "INTEGER"),
            Identifier(name: "CTRLWORD", type: "INTEGER"),
        ], ""
    ),
    // skipping 13-20 (reserved)
    21: ("LOADSEGMENT", [Identifier(name: "SEGMENT", type: "INTEGER")], ""),
    22: ("UNLOADSEGMENT", [Identifier(name: "SEGMENT", type: "INTEGER")], ""),
    23: ("TRUNC", [Identifier(name: "NUM", type: "REAL")], "INTEGER"),
    24: ("ROUND", [Identifier(name: "NUM", type: "REAL")], "INTEGER"),
    // 25-31 are not Apple Pascal CSPs. Transcendental functions are imported
    // from the TRANSCEND intrinsic library and use ordinary library calls.
    32: ("MARK", [Identifier(name: "NP", type: "POINTER")], ""),
    33: ("RELEASE", [Identifier(name: "NP", type: "POINTER")], ""),
    34: ("IORESULT", [], "INTEGER"),
    35: ("UNITBUSY", [Identifier(name: "UNIT", type: "INTEGER")], "BOOLEAN"),
    36: ("PWROFTEN", [Identifier(name: "NUM", type: "INTEGER")], "REAL"),
    37: ("UNITWAIT", [Identifier(name: "UNIT", type: "INTEGER")], ""),
    38: ("UNITCLEAR", [Identifier(name: "UNIT", type: "INTEGER")], ""),
    39: ("HALT", [], ""),
    40: ("MEMAVAIL", [], "INTEGER"),
]
