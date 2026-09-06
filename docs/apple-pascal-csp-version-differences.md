I have found the following versions of Apple Pascal's implementation. There are also "flavours" of Apple Pascal within the version, where the flavour indicates a specific feature set (for example, whether it is a runtime-only implementation or a full development P-Machine).

The smallest version is the 48K implementation which is based on version 1.1. It does not implement CSP IDs 7 or 8, and also does not implement 13-20, 23-31, or 36 (It does not contain support for REAL values at all).

Version 1.0 of Apple Pascal does not implement CSP ID 12. All other versions do.

No version of Apple Pascal implements CSP IDs 13-20 as they are reserved.

No version of Apple Pascal implements CSP IDs 25-31 as they are instead implemented as intrinsic functions within the TRANSCEND library.

All developer versions besides 1.0 (that is, 1.1 and 1.2) implement IDs 0-12, 21-24, and 32-40.

The developer version of 1.3 does not implement IDs 7 and 8.

Run-time versions of 1.1, 1.2, and 1.3 do not implement IDs 7 or 8.

## Draft version and flavour matrix

This matrix is a draft intended to make the current conclusions explicit. Entries
marked `TODO` need confirmation from an interpreter binary, source listing, or
version-specific documentation.

Legend:

- `yes`: implemented by this interpreter profile.
- `no`: not implemented by this interpreter profile.
- `FP`: implemented only when floating-point support is present.
- `reserved`: reserved CSP number with no Apple Pascal implementation.
- `library`: not a CSP; provided through an intrinsic or external library.
- `TODO`: not yet verified.

The `VERSION` byte values are `0` for 1.0, `2` for 1.1, `3` for 1.2, and `4`
for 1.3. Version 1.1 uses enumerated `FLAVOR` values. Versions 1.2 and 1.3 use
a bit field, so their numeric flavour values are not directly comparable with
1.1.

| Apple Pascal profile | Filename     | `VERSION` | `FLAVOR` | Development/ runtime | Memory/ features    | CSP 0-6 | CSP 7-8 | CSP 9-11 | CSP 12 | CSP 13-20 | CSP 21-22 | CSP 23-24 | CSP 25-31 | CSP 32-35 | CSP 36 | CSP 37-40 | Evidence/status |
| -------------------- | ------------ | --------: | -------- | -------------------- | ------------------- | ------- | ------- | -------- | ------ | --------- | --------- | --------- | ---------- | -------- | ------ | --------- | --------------- |
| 1.0 full             | SYSTEM.APPLE | 0         | 0        | development          | 64K, sets, FP       | yes     | yes     | yes      | no     | reserved  | yes       | yes       | library    | yes      | yes    | yes       | confirmed against binary |
| 1.0 runtime 6        | RT0006.APPLE | 0         | 0        | runtime              | 48K, sets, FP       | yes     | no      | yes      | no     | reserved  | yes       | yes       | library    | yes      | yes    | yes       | confirmed against binary |
| 1.0 runtime 4        | RT0004.APPLE | 0         | 0        | runtime              | 48K, no sets, no FP | yes     | no      | yes      | no     | reserved  | yes       | no        | no         | yes      | no     | yes       | confirmed against binary |
| 1.0 runtime 3        | RT0003.APPLE | 0         | 0        | runtime              | 64K, no sets, no FP | yes     | no      | yes      | no     | reserved  | yes       | no        | no         | yes      | no     | yes       | confirmed against binary |
| 1.1 full             | SYSTEM.APPLE | 2         | 1        | development          | 64K, sets, FP       | yes     | yes     | yes      | yes    | reserved  | yes       | yes       | library    | yes      | yes    | yes       | confirmed against binary |
| 1.1 runtime          | RTSTND.APPLE | 2         | 2        | runtime              | 48K, sets, FP       | yes     | no      | yes      | yes    | reserved  | yes       | yes       | library    | yes      | yes    | yes       | confirmed against binary |
| 1.1 runtime          | RTSTRP.APPLE | 2         | 5        | runtime              | 48K, no sets, no FP | yes     | no      | yes      | yes    | reserved  | yes       | no        | no         | yes      | no     | yes       | confirmed against binary |
| 1.1 runtime          | SYSTEM.APPLE | 2         | A        | runtime              | 64K, sets, FP       | yes     | no      | yes      | yes    | reserved  | yes       | yes       | library    | yes      | yes    | yes       | confirmed against binary |
| 1.1 runtime          | SYSTEM.APPLE | 2         | B        | runtime              | 64K, sets, FP       | yes     | no      | yes      | yes    | reserved  | yes       | yes       | library    | yes      | yes    | yes       | confirmed against binary |
| 1.2 full             | SYSTEM.APPLE | 3         | 0        | development          | 64K, sets, FP       | yes     | yes     | yes      | yes    | reserved  | yes       | yes       | library    | yes      | yes    | yes       | confirmed against binary |
| 1.2 runtime          | SYSTEM.APPLE | 3         | 1        | runtime              | 64K, sets, FP       | yes     | no      | yes      | yes    | reserved  | yes       | yes       | library    | yes      | yes    | yes       | confirmed against binary |
| 1.2 runtime          | RTSTND.APPLE | 3         | 21       | runtime              | 48K, sets, FP       | yes     | no      | yes      | yes    | reserved | yes        | yes       | library    | yes      | yes    | yes       | confirmed against binary |
| 1.2 runtime          | RTSTRP.APPLE | 3         | 27       | runtime              | 48K, no sets, no FP | yes     | no      | yes      | no     | reserved | yes        | yes       | library    | yes      | no     | yes       | confirmed against binary |
| 1.2 full             | SYSTEM.APPLE | 3         | 40       | development          | 128K, sets, FP      | yes     | yes     | yes      | yes    | reserved | yes        | yes       | library    | yes      | yes    | yes       | confirmed against binary |
| 1.2 runtime          | SYSTEM.APPLE | 3         | 41       | runtime              | 128K, sets, FP      | yes     | no      | yes      | yes    | reserved | yes        | yes       | library    | yes      | yes    | yes       | confirmed against binary |
| 1.3 full             | SYSTEM.APPLE | 4         | 0        | development          | 64K, sets, FP       | yes     | no      | yes      | yes    | reserved | yes        | yes       | library    | yes   | yes    | yes       | Apple Technical Note #14 confirms removal of CSP 7-8 |
| 1.3 runtime          | SYSTEM.APPLE | 4         | 1        | runtime              | 64K, sets, FP       | yes     | no      | yes      | yes    | reserved | yes        | yes       | library    | yes   | yes    | yes       | Apple Technical Note #14 confirms removal of CSP 7-8 |
| 1.3 full             | SYSTEM.APPLE | 4         | 40       | development          | 128K, sets, FP      | yes     | no      | yes      | yes    | reserved | yes        | yes       | library    | yes   | yes    | yes       | Apple Technical Note #14 confirms removal of CSP 7-8 |
| 1.3 runtime          | SYSTEM.APPLE | 4         | 41       | runtime              | 128K, sets, FP      | yes     | no      | yes      | yes    | reserved | yes        | yes       | library    | yes   | yes    | yes       | Apple Technical Note #14 confirms removal of CSP 7-8 |

### Flavour encoding notes

For version 1.1:

| `FLAVOR` | Full/runtime | Language card | Sets | Floating point |
| ---: | --- | --- | --- | --- |
| 1 | full | yes | yes | yes |
| 2 | runtime | no | yes | yes |
| 3 | runtime | no | no | yes |
| 4 | runtime | no | yes | no |
| 5 | runtime | no | no | no |
| 6 | runtime | yes | yes | yes |
| 7 | runtime | yes | no | yes |
| 8 | runtime | yes | yes | no |
| 9 | runtime | yes | no | no |

For versions 1.2 and 1.3:

| Bit(s) | Meaning |
| --- | --- |
| 0 | `0` = full, `1` = runtime |
| 1 | floating-point support is omitted when set |
| 2 | set support is omitted when set |
| 5-6 | `00` = 64K, `01` = 48K, `10` = 128K, `11` = reserved |
| 7 | console output is directed to the graphics screen when set |
