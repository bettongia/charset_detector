---
title: Technical Specification
subtitle: betto_charset_detector
toc-title: "Contents"
...

- **Package:** `betto_charset_detector`
- **Version:** 0.1.0-dev.1
- **Dart SDK:** ≥ 3.12.0

# Purpose and scope

`betto_charset_detector` is a standalone, pure-Dart package that detects the
character encoding of an arbitrary byte sequence. It exposes a single
top-level function, `detectCharset`, that accepts a `Uint8List` and returns
a lowercase [IANA](https://www.iana.org/assignments/character-sets/character-sets.xhtml) encoding label string.

The package has no Flutter or native dependencies and is compatible with all
Dart and Flutter target platforms: mobile (Android, iOS), web, and desktop
(macOS, Windows, Linux).

# Detection algorithm

Detection proceeds through three ordered stages. Each stage is cheaper and
more reliable than the next; the pipeline falls through only when the
current stage cannot make a determination.

## Stage 1 — BOM inspection (deterministic)

A byte-order mark (BOM), when present, is authoritative. BOM checks are
ordered longest-match first to correctly distinguish UTF-32 from UTF-16 (the
first two bytes of the UTF-32 LE BOM, `FF FE`, are identical to the UTF-16
LE BOM).

| BOM bytes      | Returned label |
| :------------- | :------------- |
| `00 00 FE FF`  | `utf-32be`     |
| `FF FE 00 00`  | `utf-32le`     |
| `EF BB BF`     | `utf-8`        |
| `FE FF`        | `utf-16be`     |
| `FF FE`        | `utf-16le`     |

## Stage 2 — UTF-8 structural validation

A leading sample of the input (see [Sampling](#sampling)) is decoded with
`dart:convert`'s `utf8.decode(allowMalformed: false)`. A successful decode
means the content is UTF-8 (or pure ASCII, which is a strict UTF-8 subset).
Returns `utf-8`.

**Empty-input contract:** An empty `Uint8List` passes UTF-8 validation and
returns `utf-8`. This is the guaranteed behaviour — empty input is treated as
vacuously valid UTF-8.

## Stage 3 — Candidate probe

For legacy 8-bit and CJK encodings the static method
`Charset.canDecode(Encoding?, List<int>)` from the `charset` package is used
to test each candidate encoding against the sample.

**CJK promotion heuristic:** When more than 15% of sample bytes are ≥ `0x80`,
CJK candidates are promoted to the front of the probe order. This reduces
false Western matches on CJK content with dense high-byte sequences.

**Probe order (Western-first, i.e. ≤ 15% high bytes):**

1. `windows-1252`
2. `iso-8859-1`
3. `iso-8859-2`
4. `iso-8859-15`
5. `shift-jis`
6. `euc-jp`
7. `euc-kr`
8. `gbk`

When CJK is promoted, the CJK group (items 5–8) moves to the front.

The first candidate for which `Charset.canDecode` returns `true` wins.

**Fallback:** `windows-1252`. This follows the WHATWG Encoding specification
default — Windows-1252 is the most common legacy Western encoding and a
superset of ISO-8859-1.

**Why not `Charset.detect()`?** The `charset` package ships a
`Charset.detect()` method, but it is unsuitable: its `defaultDetectOrder`
has nearly all encodings commented out in the source, and its BOM handling
is buggy (UTF-16 BE BOM returns `utf8`; UTF-32 LE BOM is absent).

**Traditional Chinese (Big5):** Out of scope for this version. The `charset`
2.0.1 package ships no Big5 codec, and adding a separate dependency solely
for Big5 is not warranted at this stage.

# Sampling

Only the first 8 KB (8,192 bytes) of the input is examined. This avoids
loading large files into memory and is sufficient for reliable BOM and
structural detection.

The sample boundary is a **hard byte cut** — it is not aligned to a
character boundary. If an 8 KB boundary falls mid-way through a multi-byte
UTF-8 sequence, Stage 2 will reject an otherwise valid UTF-8 file and fall
through to Stage 3. This is a documented, accepted trade-off: the edge case
is vanishingly rare and the consequence (a `windows-1252` result instead of
`utf-8`) is mild.

# Supported encodings and IANA label contract

`detectCharset` always returns a lowercase [IANA](https://www.iana.org/assignments/character-sets/character-sets.xhtml) label from the following
closed set. The label is looked up from an explicit internal map — never from
`encoding.name` — so the set is stable and independent of any upstream name
changes in the `charset` package.

| Label          | Stage detected |
| :------------- | :------------- |
| `utf-8`        | BOM, Stage 2, or fallback for empty input |
| `utf-16be`     | BOM                                        |
| `utf-16le`     | BOM                                        |
| `utf-32be`     | BOM                                        |
| `utf-32le`     | BOM                                        |
| `windows-1252` | Stage 3 probe or fallback                  |
| `iso-8859-1`   | Stage 3 probe                              |
| `iso-8859-2`   | Stage 3 probe                              |
| `iso-8859-15`  | Stage 3 probe                              |
| `shift-jis`    | Stage 3 probe                              |
| `euc-jp`       | Stage 3 probe                              |
| `euc-kr`       | Stage 3 probe                              |
| `gbk`          | Stage 3 probe                              |

# Accuracy

Stage 3 uses structural validity rather than statistical n-gram analysis.
`windows-1252` accepts nearly any byte sequence, so the probe is most reliable
for CJK multi-byte encodings (which have strict structural constraints) and
less discriminating between Western 8-bit encodings. In practice Stage 2
handles the vast majority of modern files, and the remaining legacy Western
files are served adequately by the `windows-1252` fallback.

**Limitation:** `Charset.canDecode` considers a decode invalid when the
decoded string contains the Unicode replacement character U+FFFD. Input that
legitimately contains U+FFFD will therefore be rejected by every non-UTF
codec regardless of its actual encoding.

**Ambiguity between short CJK samples:** Short byte sequences can be
structurally valid in more than one CJK encoding (e.g. a short EUC-KR
sequence may also pass Shift-JIS validation). The probe order determines the
winner in such cases. Longer samples improve discrimination.

# Package dependency

```yaml
dependencies:
  charset: ^2.0.1
```

`charset` is a pure-Dart package (Apache-2.0) with no Flutter or native
dependencies.

# Why not uchardet / ICU?

`uchardet` (Mozilla's C++ port of the ICU character-set detection library) was
evaluated and deliberately not adopted. The decision rests on three
compounding factors.

## Build complexity without proportionate benefit

`uchardet` is implemented in C++, not C. Unlike a straightforward
`native_toolchain_c` / `CBuilder` integration, compiling it from source
requires invoking a C++ compiler (`clang++` / `g++`) in the build hook, plus
either enumerating its ~40 source files explicitly or writing a thin
`extern "C"` wrapper to bridge the C++ implementation to a C-compatible ABI.
That is a meaningfully higher maintenance burden, particularly across the
mobile target architectures (arm64-v8a, armeabi-v7a, x86\_64).

## The web platform requires a pure-Dart fallback regardless

`dart:ffi` is unavailable on web, so a conditional-export structure — native
builds use FFI, web builds use pure Dart — would be mandatory no matter how
capable the native path is. Because web input is overwhelmingly UTF-8 or
BOM-marked, and because web is where detection failures matter least (browsers
re-encode on render), the FFI path only improves outcomes on native platforms.
For a personal-scale vault ingestion workload, that is a narrow benefit that
does not justify the added complexity.

## Accuracy uplift is modest for the actual workload

The three-stage pipeline — BOM inspection, UTF-8 structural validation, then
`Charset.canDecode()` probing — correctly handles the vast majority of real
files. `uchardet`'s statistical n-gram models offer genuine advantages when
distinguishing similar Western 8-bit encodings (Latin-1 vs Windows-1252 vs
ISO-8859-2 on ambiguous content), but those cases are rare in practice and the
`windows-1252` fallback is the correct answer for unresolvable Western content
under the WHATWG Encoding specification anyway. For CJK content — where
statistical detection would give the most meaningful uplift — the structural
validity probes in Stage 3 already provide reliable discrimination because CJK
multi-byte encodings impose tight structural constraints.

## Revisability

This decision is explicitly revisable. If detection accuracy proves inadequate
once real vault ingestion data is available, the FFI path remains viable. The
conditional-export structure described above is already the correct shape to
accommodate it.

# Public API

```dart
/// Detects the character encoding of [bytes].
///
/// Returns a lowercase IANA encoding label (e.g. 'utf-8', 'shift-jis').
String detectCharset(Uint8List bytes);
```

Exported from `package:betto_charset_detector/betto_charset_detector.dart`.
