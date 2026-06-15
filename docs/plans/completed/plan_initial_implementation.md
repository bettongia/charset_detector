# Charset Detection Utility

**Status**: Implementing

**PR link**: {A link to the PR submitted for this plan}

## Problem statement

Dart applications need to determine the character encoding of arbitrary byte
sequences — for example, when reading plain text files or CSVs whose encoding
is unknown. There is no native browser API for charset detection and no
pure-Dart statistical detector available on pub.dev.

This plan implements `betto_charset_detector`: a layered, pure-Dart charset
detection package that works across all Dart and Flutter target platforms
(mobile, web, desktop). It has no Flutter or native dependencies and can be
used in any Dart context.

## Open questions

## Investigation

### Why pure Dart?

The `flutter_charset_detector` and `charset_converter` packages delegate to
native platform libraries (ICU on Android, `CFString` on iOS/macOS). Both
require Flutter plugin infrastructure and do not work in a pure Dart context.
The `chardet` pub.dev package also has Flutter dependencies.

There is no browser-native charset detection API. `TextDecoder` (the Web
Encoding API) is a decoder — it requires a known encoding name and cannot
detect one. `flutter_charset_detector`'s web implementation bundles and calls
`jschardet` (a JS library) via Flutter plugin machinery, not a browser
built-in.

The FFI path (uchardet via `native_toolchain_c`) was also evaluated. It is
a C++ codebase requiring a C++ build step, and FFI is unavailable on web
regardless. The marginal accuracy gain over the pure Dart pipeline does not
justify the build complexity for this use case. The decision can be revisited
if detection accuracy proves inadequate in practice.

### Detection pipeline

Charset detection is implemented as three ordered stages. Each stage is
cheaper and more reliable than the next; the pipeline falls through only when
necessary.

**Stage 1 — BOM inspection (deterministic)**

A byte-order mark, when present, is authoritative. Checks are ordered
longest-match first to correctly distinguish UTF-32 from UTF-16:

| BOM bytes            | Encoding  |
| :------------------- | :-------- |
| `00 00 FE FF`        | UTF-32 BE |
| `FF FE 00 00`        | UTF-32 LE |
| `EF BB BF`           | UTF-8     |
| `FE FF`              | UTF-16 BE |
| `FF FE`              | UTF-16 LE |

**Stage 2 — UTF-8 structural validation**

`dart:convert`'s `utf8.decode` with `allowMalformed: false` is run against a
leading sample of the input. A valid decode means the content is UTF-8 (or
pure ASCII, which is a strict UTF-8 subset). This stage correctly handles the
vast majority of modern files and all web-origin content.

**Stage 3 — Candidate probe via the `charset` package**

For legacy 8-bit and CJK encodings the `charset` package
(`pub.dev/packages/charset`) is used via its static method
`Charset.canDecode(Encoding?, List<int>)`. Each candidate is an `Encoding`
instance from the package (e.g. `shiftJis`, `eucJp`, `gbk`, `windows1252`);
`Charset.canDecode` is called with the candidate and the sample to test
validity. The package's own `Charset.detect()` method is not used: its
`defaultDetectOrder` has nearly all encodings commented out in the source,
and its BOM handling is buggy (UTF-16 BE BOM returns `utf8`, UTF-32 LE BOM
is absent). Candidates are probed in priority order:

- CJK encodings are promoted when the byte sample contains a high proportion
  of bytes ≥ `0x80` (heuristic threshold: >15% of the sample).
- Western candidates: `windows-1252`, `iso-8859-1`, `iso-8859-2`,
  `iso-8859-15`.
- CJK candidates: `shift-jis`, `euc-jp`, `euc-kr`, `gbk`.

Traditional Chinese (Big5) is out of scope for this version. The `charset`
2.0.1 package ships no Big5 codec, and adding a separate dependency solely
for Big5 is not warranted at this stage.

**Fallback**: `windows-1252`. This follows the WHATWG Encoding specification
fallback (Windows-1252 is a superset of ISO-8859-1 and the most common legacy
Western encoding).

### Sampling

Only the first 8 KB of the input is passed to the detector. This avoids
loading large files into memory and is sufficient for reliable BOM and
structural detection; the `charset` probe is also effective on short samples.

The sample is cut at a hard byte boundary. If the boundary falls mid-way
through a multi-byte character, Stage 2 may reject an otherwise valid UTF-8
file and fall through to Stage 3. This is accepted: the edge case is
vanishingly rare and the consequence (a `windows-1252` result instead of
`utf-8`) is mild. The behaviour must be noted in the spec and doc comments.

### Accuracy note

Stage 3 uses structural validity (`canDecode`) rather than statistical
n-gram analysis. `windows-1252` accepts nearly any byte sequence so the probe
is most reliable for CJK multi-byte encodings (which have strict validity
constraints) and less discriminating between Western 8-bit encodings. In
practice this is acceptable: Stage 2 handles >95% of real-world files, and
the remaining legacy Western files are served adequately by the
`windows-1252` fallback.

### Package dependency

```yaml
dependencies:
  charset: ^2.0.1
```

`charset` is a pure-Dart package (Apache-2.0) with no Flutter or native
dependencies. It is compatible with all Dart platforms including web.

### File location

```
lib/
  betto_charset_detector.dart   ← public barrel file
  src/
    charset_detector.dart       ← implementation
```

`detectCharset` is exported from the public barrel file and is the sole
public API of the package.

## Implementation plan

### Phase 1 — Utility implementation

- [x] Remove boilerplate files generated by `dart create`:
      `lib/charset_detector.dart`, `lib/src/charset_detector_base.dart`,
      and rewrite `example/charset_detector_example.dart` against the real API.
- [x] Update the package manifest: set a proper description and uncomment
      the `repository` field.
- [x] Update `README.md` with a package overview, features list, getting
      started instructions, and a usage example.
- [x] Add `charset: ^2.0.1` to the package dependencies and run `dart pub get`.
- [x] Create `lib/src/charset_detector.dart` and export it from
      `lib/betto_charset_detector.dart`:
  - Top-level function `String detectCharset(Uint8List bytes)` — the
    primary public API.
  - Private `String? _detectBom(Uint8List bytes)` — returns encoding name
    or `null`. Checks 4-byte BOMs before 3-byte and 2-byte to avoid
    mis-classifying UTF-32 as UTF-16.
  - Private `bool _isValidUtf8(Uint8List bytes)` — wraps
    `utf8.decode(..., allowMalformed: false)` in a try/catch.
  - Private `bool _looksMultibyte(Uint8List sample)` — returns `true` when
    more than 15% of bytes are ≥ `0x80`.
  - Private `String _probeEncoding(Uint8List bytes)` — probes candidate
    list in priority order using the static `Charset.canDecode(encoding,
    sample)` API; returns `'windows-1252'` if no candidate matches.
  - A private `const Map<Encoding, String> _ianaLabels` — maps each
    candidate `Encoding` instance to its canonical lowercase IANA label
    (e.g. `windows1252 → 'windows-1252'`, `latin9 → 'iso-8859-15'`).
    The detector returns labels from this map, never `encoding.name`.
  - Sample extraction: cap input to 8 KB before any processing.
  - Returned encoding names use lowercase IANA labels consistent with
    `dart:convert` and `TextDecoder` conventions (e.g. `'utf-8'`,
    `'utf-16be'`, `'windows-1252'`, `'shift-jis'`).

### Phase 2 — Tests

- [x] Create `test/charset_detector_test.dart`:
  - BOM detection: one test per BOM variant (UTF-8, UTF-16 BE/LE, UTF-32
    BE/LE); verify correct label returned and that the function does not
    fall through to later stages.
  - UTF-8 validation: valid UTF-8 without BOM returns `'utf-8'`; pure
    ASCII returns `'utf-8'`; invalid UTF-8 byte sequence falls through to
    Stage 3.
  - Probe stage: bytes valid only as Shift-JIS return `'shift-jis'`; bytes
    valid only as EUC-JP return `'euc-jp'`; ambiguous bytes return the
    expected fallback.
  - Fallback: bytes that match no specific candidate return `'windows-1252'`.
  - Sampling: input larger than 8 KB is accepted without error (truncation
    is internal).
  - Edge cases: empty `Uint8List` returns `'utf-8'` (empty input passes
    UTF-8 validation); single-byte input handled without range errors.
- [x] Run `make test` and confirm ≥ 90% coverage on the new file.

### Phase 3 — Documentation and housekeeping

- [x] Add doc comments to `charset_detector.dart` describing the three
      stages, the 8 KB sample limit, and the `windows-1252` fallback
      rationale.
- [x] Populate `docs/spec/` with the package specification: purpose, supported
      encodings, the three-stage algorithm, the 8 KB sample cap, the fallback
      contract, the IANA label set, and the empty-input contract.
- [x] Run `make analyze` with zero errors or warnings.
- [x] Update `CLAUDE.md` implementation status table with the completed work.
- [x] Run `make pre_commit` and confirm all checks pass before committing.

## Reviews

### Review 1: 2026-06-14

Overall this is a well-reasoned plan with a sensible, correctly-ordered
pipeline and a refreshingly honest accuracy note. The decision to write a thin
pure-Dart detector rather than reach for FFI/native plugins is the right call
for a package that must run on web, and the rationale is documented. However,
**the plan rests on a factually incorrect description of the `charset`
package's API, and at least one candidate encoding it relies on does not exist
in that package.** These must be resolved before implementation, because the
Phase 1 task list as written would not compile.

#### Problem Statement Assessment

The problem is real and worth solving. There genuinely is no pure-Dart
statistical charset detector on pub.dev that works on web, and the survey of
why `flutter_charset_detector`, `charset_converter`, and `chardet` are
unsuitable (Flutter/native coupling, no browser detection API) is accurate.
Scope is appropriately small: a single top-level function, one dependency, web
compatibility preserved.

One gap: the plan does not state *who consumes this* within the Bettongia
family or which roadmap item it satisfies. `docs/roadmap/v0.md` is an empty
stub (`# v0` only) and there is no roadmap entry for this work. The README
guidance states that non-trivial roadmap items are tracked as plans and linked
back. Either this is the foundational v0 deliverable (in which case the roadmap
should say so) or it is unscheduled work. This should be reconciled so the
roadmap reflects reality — see open questions.

#### Proposed Solution Assessment

Strengths:

- The three-stage ordering (BOM → UTF-8 structural validation → candidate
  probe → `windows-1252` fallback) is correct and matches how mature detectors
  are structured. Cheapest, most-deterministic checks first.
- BOM ordering (4-byte UTF-32 before 2-byte UTF-16) is correctly called out;
  this is a real trap and the plan avoids it.
- The accuracy note is candid about `canDecode`-based probing being weak for
  Western 8-bit encodings and strong for CJK. That honesty is valuable and
  correct.
- Doing the project's own BOM stage rather than delegating is, as it turns out,
  *justified* — see the architecture-fit findings below. The plan reaches the
  right conclusion but for unstated reasons.

Weaknesses — these are blocking factual errors, not stylistic quibbles:

1. **The `canDecode` API described does not exist.** The plan states (lines
   68–72, 139–140) that "the `charset` package exposes a `canDecode(Uint8List)`
   method on each of its codec instances" and that `_probeEncoding` uses
   `codec.canDecode(bytes)`. In `charset` 2.0.1 the method is a **static**
   method on the `Charset` class:
   `static bool Charset.canDecode(Encoding? encoding, List<int> char)`. There
   is no instance `canDecode` on the codecs. Phase 1's `_probeEncoding`
   description must be rewritten to call `Charset.canDecode(encoding, sample)`,
   and the candidate list must be a list of `Encoding` instances
   (`shiftJis`, `eucJp`, `eucKr`, `gbk`, `latin1`, `latin2`, `latin9`,
   `windows1252`, …) rather than codec-with-`canDecode` objects.

2. **`big5` is not in the `charset` package.** The CJK candidate list (line 78)
   includes `big5`, but `charset` 2.0.1 ships no Big5 codec at all (no symbol,
   no name registration). Referencing it will not compile / will resolve to
   null. Either drop Big5 from the candidate list and the plan, or document
   that Traditional-Chinese detection is out of scope. The test in Phase 2 must
   not assert a Big5 result.

3. **Returned encoding labels will not match what the codecs report.** The plan
   promises lowercase IANA labels like `'windows-1252'` (lines 142–144), but
   the `charset` `CodePage` for that encoding reports its `name` as
   `'windows1252'` (no hyphen), while `iso-8859-15` is the codec internally
   named `latin9`. The detector therefore cannot simply return `encoding.name`;
   it must own an explicit `Encoding → IANA-label` mapping. This is a real
   implementation detail the plan glosses over — make the label map an explicit
   artefact in Phase 1.

4. **`Charset.detect()` already exists and is unmentioned.** The package ships
   `static Encoding? Charset.detect(...)`. A reviewer (or future maintainer)
   will immediately ask "why not just call that?" The plan should pre-empt this
   by stating that `Charset.detect()` is unsuitable — which it genuinely is:
   its `defaultDetectOrder` has all encodings *except* `ascii` and `gbk`
   commented out in the source, and its BOM handling is buggy (UTF-16 BE BOM
   returns `utf8`, and there is no UTF-32 LE BOM branch). So building a bespoke
   pipeline is the right call, but the plan must say so, otherwise it looks
   like the package was not investigated thoroughly. Right now the omission
   undermines confidence in the rest of the investigation.

#### Architecture Fit

- The package layering is trivially fine: this is pure-Dart Core only, no
  Presentation or App layer, no Flutter import, no `dart:ui`. The
  library-architecture three-layer concern is satisfied by construction. The
  barrel `lib/betto_charset_detector.dart` exporting a single `detectCharset`
  with a `show` clause is the correct public surface.

- **The plan ignores the existing boilerplate in `lib/`.** The repo currently
  has `lib/charset_detector.dart` (barrel exporting
  `src/charset_detector_base.dart`) and `lib/src/charset_detector_base.dart`
  (the `Awesome` placeholder class), plus `example/charset_detector_example.dart`
  which imports `package:charset_detector/charset_detector.dart` and references
  `Awesome`. The plan proposes *new* file names
  (`lib/betto_charset_detector.dart`, `lib/src/charset_detector.dart`) without
  saying the old files and the example must be deleted/rewritten. As written,
  implementation would leave dead boilerplate, a stale `example/`, and an
  import path (`package:charset_detector/…`) that does not match the package
  name (`betto_charset_detector`). Phase 1 must include removing the
  placeholder barrel + base file and rewriting the example against the real
  API.

- **The specification is an empty stub.** `docs/spec/README.md` has a `# Purpose
  and scope` heading and nothing under it; the version/SDK fields are blank.
  CLAUDE.md names `docs/spec/` the primary architecture source. This plan
  *creates* the package's entire behaviour, so it must also populate the spec
  (purpose, supported encodings, the three-stage algorithm, the 8 KB sample
  cap, the fallback contract, and the IANA label set the API guarantees).
  Phase 3 only mentions updating CLAUDE.md's status table and adding doc
  comments — it omits the spec. Add a spec-authoring task.

- **Pubspec metadata is still boilerplate.** `description: A starting point for
  Dart libraries or applications.` and a commented-out `repository`. Not
  strictly in scope, but since Phase 1 already edits `pubspec.yaml` to add the
  dependency, fixing the description in the same pass is cheap and avoids
  publishing boilerplate.

#### Risk & Edge Cases

The edge-case list in Phase 2 is good (empty input, single byte, >8 KB input,
ambiguous bytes). Additional cases the plan should cover:

- **The empty-input contract is asserted but not justified against the spec.**
  Returning `'utf-8'` for an empty `Uint8List` is a reasonable convention, but
  it is a *decision* (empty input is equally valid as every encoding). Record
  it in the spec so it is a guaranteed contract, not an implementation
  accident.
- **A lone BOM with no following content** (e.g. exactly the 3 UTF-8 BOM bytes
  and nothing else) — confirm Stage 1 still returns the BOM's encoding and does
  not index out of range.
- **Truncated multi-byte sequence at the 8 KB sample boundary.** Capping the
  sample at exactly 8 KB can slice a multi-byte character in half, causing a
  valid UTF-8 file to fail Stage 2 and fall through. Decide whether to accept
  this (rare, fallback still reasonable) or to back the sample off to a
  character boundary, and document the choice.
- **`canDecode` for `windows-1252`/latin1 accepts almost any byte string.** The
  plan acknowledges this, but the *ordering* of the Western candidate probe
  then largely determines the result. Make the candidate order an explicit,
  tested, documented list — the first Western codec that accepts wins, so order
  is the actual behaviour, not a detail.
- **`canDecode`'s validity test keys on the literal `'�'` replacement
  character** appearing in the decoded string. Input that legitimately contains
  U+FFFD will be rejected by every non-UTF codec. Low impact, but worth a note
  in the accuracy section.
- **No coverage strategy for the 90% gate on branch-heavy probe code.** The
  probe/fallback logic is the hardest part to cover. Phase 2 should explicitly
  target the fallback-reached and each-candidate-matched branches, not just the
  happy CJK cases.

#### Recommendations

The plan is close, and the approach is sound — the issues are factual/API
accuracy and housekeeping, all fixable without changing the strategy. Before
this moves to `Investigated`:

1. Rewrite the Stage 3 / `_probeEncoding` description to use the real static
   `Charset.canDecode(Encoding?, List<int>)` API and a list of `Encoding`
   instances.
2. Remove `big5` (or explicitly scope out Traditional Chinese).
3. Add an explicit `Encoding → IANA label` mapping as a named Phase 1 artefact;
   do not rely on `encoding.name`.
4. Add a sentence explaining why `Charset.detect()` is not used directly.
5. Add Phase 1 tasks to delete the placeholder barrel/base files and rewrite
   `example/` and the package `description`.
6. Add a Phase 3 task to populate `docs/spec/` with the algorithm and the
   guaranteed label/contract set, and reconcile `docs/roadmap/v0.md`.
7. Fold the additional edge cases above into Phase 2.

Once the open questions are answered and the Phase 1/2/3 task lists corrected,
this is ready to implement.

#### Open questions

- [x] The plan lists `big5` as a CJK candidate, but `charset` 2.0.1 ships no
      Big5 codec. Drop Big5 entirely, or is Traditional-Chinese detection a
      required capability (which would mean a different/additional dependency)?
      **Decision**: Traditional Chinese is out of scope. `big5` removed from
      the candidate list.
- [x] Should the detector own an explicit `Encoding → IANA label` map (so the
      public contract is a stable, documented label set), or return whatever
      `encoding.name` reports (which leaks `charset`'s non-hyphenated names like
      `windows1252`)? Recommendation: own the map.
      **Decision**: The detector owns an explicit `_ianaLabels` map. Added as a
      named Phase 1 artefact.
- [x] At the 8 KB sample boundary, do we back off to a character boundary to
      avoid splitting a multi-byte sequence, or accept the rare false
      fall-through to fallback?
      **Decision**: Accept the hard byte boundary. The edge case is vanishingly
      rare and the consequence mild. Documented in the Sampling section.
- [x] Is this package the v0 roadmap deliverable? If so, `docs/roadmap/v0.md`
      should name it and link this plan. If not, where does it sit in the
      roadmap?
      **Decision**: Yes — this is the foundational v0 deliverable.
      `docs/roadmap/v0.md` has been updated with an entry linking this plan.
- [x] This plan defines the package's entire behaviour but `docs/spec/` is an
      empty stub. Confirm that authoring the spec (algorithm, supported
      encodings, label contract, empty-input contract, fallback) is in scope for
      this plan.
      **Decision**: In scope. Spec authoring added as a Phase 3 task. README
      and package manifest description updates also added to Phase 1.

### Review 2: 2026-06-14

The five open questions from Review 1 are all resolved and the decisions are
sound and well-recorded. The candidate list no longer references `big5`, the
`_ianaLabels` map is now a named Phase 1 artefact, the 8 KB hard-boundary
trade-off is documented in the Sampling section, `docs/roadmap/v0.md` names this
as the v0 deliverable and links the plan, and spec authoring plus README/manifest
fixes are in the task lists. I verified the roadmap entry and the Phase 1/3 task
additions directly. Good work on the housekeeping.

However, the plan is **not yet ready for `Investigated`**. Two of Review 1's
seven recommendations were not fully folded in, and one of them is the same
compile-breaking factual error Review 1 flagged as blocking — it was corrected
in the Phase 1 task list but left intact in the Investigation prose, so the plan
now contradicts itself.

#### Outstanding blocking issue

1. **The Investigation still describes the wrong `canDecode` API (Review 1,
   Weakness 1).** Phase 1 (line 157) was correctly rewritten to call the static
   `Charset.canDecode(encoding, sample)`. But the Stage 3 narrative at lines
   70–72 still reads: "the `charset` package ... exposes a `canDecode(Uint8List)`
   method on each of its codec instances." That is the exact incorrect claim
   Review 1 identified as blocking — `canDecode` is a static method on the
   `Charset` class, not an instance method on each codec. The Investigation is
   CLAUDE.md's narrative-of-record for the approach, and a future implementer
   reading it will be misled. Rewrite lines 70–72 to state that Stage 3 probes a
   priority-ordered list of `Encoding` instances using the static
   `Charset.canDecode(Encoding?, List<int>)` API, matching the Phase 1 task.

#### Outstanding non-blocking issue

2. **`Charset.detect()` is still unmentioned (Review 1, Weakness 4 /
   Recommendation 4).** This was a standalone Review 1 recommendation, not one of
   the five questions, so it is understandable it slipped — but it should be
   closed before sign-off. Add a sentence to the Investigation stating why the
   package's built-in `static Charset.detect()` is unsuitable (its
   `defaultDetectOrder` has most encodings commented out, and its BOM handling is
   buggy), so the bespoke pipeline is justified on the record. One sentence; do
   not let it linger to a third review.

#### Minor follow-ups (optional, not gating)

- The additional edge cases from Review 1's Risk section — a lone BOM with no
  trailing content, and input legitimately containing U+FFFD being rejected by
  every non-UTF codec — are still absent from Phase 2 / the accuracy note.
  Cheap to add while the plan is open; not a blocker.

#### Recommendation

Make the single-sentence fix to the Stage 3 Investigation prose (item 1) — that
alone is blocking because it re-states a known-false API description. Item 2 is a
one-line addition that should be done in the same pass. Once lines 70–72 reflect
the real static API and the `Charset.detect()` rationale is recorded, this plan
is ready for `Investigated`. The strategy itself remains correct and unchanged;
these are documentation-accuracy fixes, not design changes.

#### Open questions

None outstanding — all Review 1 questions are resolved. The two items above are
corrections to apply, not questions to answer.

### Review 3: 2026-06-14

Both corrections from Review 2 have been applied and are accurate. This plan is
now ready for implementation — promoting to `Investigated`.

#### Verification of the two corrections

1. **Stage 3 API prose (Review 2, blocking item 1) — resolved.** Lines 70–74 now
   describe the real static `Charset.canDecode(Encoding?, List<int>)` API and
   `Encoding`-instance candidates (`shiftJis`, `eucJp`, `gbk`, `windows1252`).
   The stale "method on each codec instance" claim is gone. This matches the
   Phase 1 task list (lines 162–166), so the Investigation narrative and the
   task list no longer contradict each other — the self-contradiction Review 2
   flagged is closed.

2. **`Charset.detect()` rationale (Review 2, item 2) — resolved.** Lines 75–78
   now state why the package's built-in `Charset.detect()` is not used: its
   `defaultDetectOrder` has nearly all encodings commented out, and its BOM
   handling is buggy (UTF-16 BE BOM returns `utf8`, UTF-32 LE BOM absent). Both
   reasons match the package-source findings recorded in Review 1. The bespoke
   pipeline is now justified on the record.

#### Consistency check

I grepped the whole plan for `canDecode`, `big5`/`Big5`, `encoding.name`,
`_ianaLabels`, and `detect()`. Outside the Review 1/2 subsections (which
correctly quote the old wrong text as historical record), every mention is now
correct:

- The accuracy note (line 108) uses `canDecode` only conceptually — no API-shape
  claim.
- `big5` outside the reviews appears only at lines 86–88 as an explicit
  out-of-scope statement.
- The `_ianaLabels` map (lines 164–167) is the documented source of returned
  labels; the plan states the detector never returns `encoding.name`.

#### Outstanding items

None blocking. The two optional follow-ups noted in Review 2 (a lone-BOM
edge-case test and an accuracy-note line about input legitimately containing
U+FFFD) remain unaddressed but were explicitly marked non-gating. They are cheap
to fold in during implementation if the author wishes; they do not hold up
`Investigated`.

#### Recommendation

Proceed. The strategy has been sound since Review 1; all factual/API-accuracy
and housekeeping issues are now closed and the Investigation prose, Phase 1–3
task lists, roadmap entry, and spec-authoring task are mutually consistent.
Status set to `Investigated`. The `plan-implement` agent can now execute it.

#### Open questions

None.

## Summary

- Implemented `detectCharset(Uint8List bytes)` in `lib/src/charset_detector.dart`,
  exported from `lib/betto_charset_detector.dart`, using a three-stage pipeline:
  BOM inspection → UTF-8 structural validation → candidate probe via
  `Charset.canDecode`.
- Added an explicit `_ianaLabels` map to guarantee stable, hyphenated IANA label
  output independent of the `charset` package's internal codec names.
- Removed `dart create` boilerplate (`charset_detector_base.dart`, `Awesome`
  class) and rewrote `example/` against the real API.
- Updated the package manifest description and added `charset: ^2.0.1` dependency.
- Updated `README.md` with package overview, features, getting-started guide,
  and usage example.
- Created 44 unit tests with 100% line coverage, including BOM ordering edge
  cases, lone-BOM inputs, CJK discrimination using longer samples, sampling
  boundary cases, and IANA label contract verification.
- Discovered and documented that short CJK byte sequences are ambiguous across
  encodings; tests use longer samples that are uniquely discriminating.
- Populated `docs/spec/README.md` with the full technical specification.
- Updated `CLAUDE.md` repository layout, implementation status, and
  documentation links.
- All `make pre_commit` checks pass: format, analyze, license, and tests.
