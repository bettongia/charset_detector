## 0.1.0-dev.2

## 0.1.0-dev.1

Initial development release of `betto_charset_detector`.

### Features

- `detectCharset(Uint8List bytes)` — single public entry point that returns a
  guaranteed lowercase IANA encoding label for an arbitrary byte sequence.

- **Stage 1 — BOM inspection (deterministic):** Recognises five BOMs before any
  heuristic processing. Four-byte BOMs (`UTF-32 BE/LE`) are checked before
  two-byte BOMs to prevent `UTF-32 LE` (`FF FE 00 00`) being misidentified as
  `UTF-16 LE` (`FF FE`).

- **Stage 2 — UTF-8 structural validation:** Validates the input (up to the 8 KB
  sample cap) with `utf8.decode(allowMalformed: false)`. Pure ASCII passes this
  stage because ASCII is a strict UTF-8 subset. Empty input also returns
  `utf-8`.

- **Stage 3 — Candidate probe via the `charset` package:** Probes Western and
  CJK legacy encodings using `Charset.canDecode`. CJK candidates are promoted to
  the front of the probe order when more than 15% of sample bytes are ≥ `0x80`.
  Falls back to `windows-1252` (WHATWG Encoding specification default) if no
  candidate matches.

- **Supported encodings:**
  - BOM-detected: `utf-8`, `utf-16be`, `utf-16le`, `utf-32be`, `utf-32le`
  - Structural: `utf-8` (including pure ASCII)
  - Western legacy: `windows-1252`, `iso-8859-1`, `iso-8859-2`, `iso-8859-15`
  - CJK multi-byte: `shift-jis`, `euc-jp`, `euc-kr`, `gbk`
  - Fallback: `windows-1252`

- **8 KB sampling policy:** Only the first 8 192 bytes are examined, bounding
  memory usage for large inputs while remaining sufficient for reliable
  detection.

- **Stable IANA label contract:** All returned labels are taken from an explicit
  `Encoding → label` map rather than `Encoding.name`, insulating callers from
  upstream name changes in the `charset` package (e.g. `windows1252` →
  `windows-1252`, `latin-2` → `iso-8859-2`).

- **Pure Dart, no native dependencies:** Compatible with all Dart and Flutter
  target platforms — mobile, web, and desktop — with a single dependency on the
  `charset` package.
