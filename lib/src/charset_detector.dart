// Copyright 2026 The Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';

/// Maximum number of bytes sampled from the input for detection.
///
/// Only the first [_sampleSize] bytes are examined. This avoids loading large
/// files into memory and is sufficient for reliable BOM and structural
/// detection. The sample boundary is a hard byte cut — it is not aligned to
/// a character boundary. If a multi-byte sequence spans the boundary, Stage 2
/// (UTF-8 structural validation) may reject an otherwise valid UTF-8 file and
/// fall through to the Stage 3 probe. This is accepted as a documented
/// trade-off: the edge case is vanishingly rare and the consequence (a
/// `windows-1252` result instead of `utf-8`) is mild.
const int _sampleSize = 8 * 1024; // 8 KB

/// Explicit mapping from each candidate [Encoding] instance to its canonical
/// lowercase IANA label.
///
/// The detector always returns labels from this map — never [Encoding.name] —
/// because several codecs use non-hyphenated or otherwise non-IANA internal
/// names (e.g. `windows1252`, `latin-2`, `latin-9`). Owning this map makes
/// the public API contract stable and independent of any upstream name changes
/// in the `charset` package.
final Map<Encoding, String> _ianaLabels = {
  windows1252: 'windows-1252',
  latin1: 'iso-8859-1',
  latin2: 'iso-8859-2',
  latin9: 'iso-8859-15',
  shiftJis: 'shift-jis',
  eucJp: 'euc-jp',
  eucKr: 'euc-kr',
  gbk: 'gbk',
};

/// Candidate encodings to probe in Stage 3, partitioned into Western and CJK
/// groups. The probe order within each group is significant: the first
/// candidate that successfully decodes the sample wins. CJK candidates are
/// promoted to the front of the list when the sample contains a high
/// proportion of high bytes (see [_looksMultibyte]).
///
/// Ordering rationale for Western candidates:
/// - `windows-1252` is first because it is the most common legacy Western
///   encoding and accepts almost any byte sequence. Placing it first means
///   that if no CJK encoding matches, `windows-1252` wins immediately;
///   ISO-8859 variants follow to give them a chance before the fallback.
/// - `iso-8859-1` is a strict subset of `windows-1252` so it will match
///   whenever `windows-1252` would, but it is listed here for completeness
///   and to exercise the probe path in tests.
/// - `iso-8859-2` and `iso-8859-15` are more restrictive and can reject
///   byte sequences that `windows-1252` accepts.
final List<Encoding> _westernCandidates = [
  windows1252,
  latin1, // iso-8859-1
  latin2, // iso-8859-2
  latin9, // iso-8859-15
];

final List<Encoding> _cjkCandidates = [shiftJis, eucJp, eucKr, gbk];

/// Detects the character encoding of the given byte sequence.
///
/// Returns a lowercase IANA encoding label string. The following labels may
/// be returned:
///
/// - BOM-detected: `'utf-8'`, `'utf-16be'`, `'utf-16le'`, `'utf-32be'`,
///   `'utf-32le'`
/// - UTF-8 structural: `'utf-8'`
/// - Legacy 8-bit: `'windows-1252'`, `'iso-8859-1'`, `'iso-8859-2'`,
///   `'iso-8859-15'`
/// - CJK multi-byte: `'shift-jis'`, `'euc-jp'`, `'euc-kr'`, `'gbk'`
/// - Fallback: `'windows-1252'`
///
/// Detection proceeds through three ordered stages, falling through only
/// when the current stage cannot make a determination:
///
/// **Stage 1 — BOM inspection (deterministic)**
/// A byte-order mark (BOM), when present, is authoritative. The four-byte
/// UTF-32 BOMs are checked before the two-byte UTF-16 BOMs to prevent
/// UTF-32 LE from being misidentified as UTF-16 LE (they share the same
/// first two bytes: `FF FE`).
///
/// **Stage 2 — UTF-8 structural validation**
/// A leading 8 KB sample of the input is decoded with
/// `utf8.decode(allowMalformed: false)`. A successful decode means the
/// content is UTF-8 (or pure ASCII, which is a strict UTF-8 subset). Empty
/// input passes this stage and returns `'utf-8'`.
///
/// **Stage 3 — Candidate probe via the `charset` package**
/// The sample is tested against each candidate [Encoding] using the static
/// [Charset.canDecode] method. CJK encodings are promoted when more than 15%
/// of sample bytes are ≥ `0x80`. The first candidate to successfully decode
/// the sample wins. If no candidate matches, `'windows-1252'` is returned as
/// the fallback (following the WHATWG Encoding specification default).
///
/// Note: [Charset.canDecode] considers a decode invalid if the resulting
/// string contains the Unicode replacement character U+FFFD (`'?'`). Input
/// that legitimately contains U+FFFD will therefore be rejected by every
/// non-UTF codec regardless of its actual encoding. This is a known
/// limitation of the structural validity approach.
///
/// Example:
/// ```dart
/// import 'dart:io';
/// import 'dart:typed_data';
/// import 'package:betto_charset_detector/betto_charset_detector.dart';
///
/// void main() {
///   final bytes = File('data.csv').readAsBytesSync();
///   final encoding = detectCharset(Uint8List.fromList(bytes));
///   print('Detected encoding: $encoding');
/// }
/// ```
String detectCharset(Uint8List bytes) {
  // Extract a leading sample to limit memory usage.
  // The sample cap is applied first so that all subsequent stages operate
  // on the same bounded input.
  final sample = bytes.length > _sampleSize
      ? Uint8List.sublistView(bytes, 0, _sampleSize)
      : bytes;

  // Stage 1: BOM inspection.
  final bomResult = _detectBom(sample);
  if (bomResult != null) {
    return bomResult;
  }

  // Stage 2: UTF-8 structural validation.
  if (_isValidUtf8(sample)) {
    return 'utf-8';
  }

  // Stage 3: Candidate probe.
  return _probeEncoding(sample);
}

/// Returns the IANA encoding label indicated by a byte-order mark at the
/// start of [bytes], or `null` if no recognised BOM is present.
///
/// Four-byte BOMs are checked before two-byte BOMs. This ordering is
/// essential to correctly distinguish UTF-32 LE (`FF FE 00 00`) from UTF-16
/// LE (`FF FE`), as the two sequences share the same first two bytes.
///
/// | BOM bytes       | Returned label |
/// | :-------------- | :------------- |
/// | `00 00 FE FF`   | `'utf-32be'`   |
/// | `FF FE 00 00`   | `'utf-32le'`   |
/// | `EF BB BF`      | `'utf-8'`      |
/// | `FE FF`         | `'utf-16be'`   |
/// | `FF FE`         | `'utf-16le'`   |
String? _detectBom(Uint8List bytes) {
  final len = bytes.length;

  // Check 4-byte BOMs first to avoid misidentifying UTF-32 as UTF-16.
  if (len >= 4) {
    // UTF-32 BE BOM: 00 00 FE FF
    if (bytes[0] == 0x00 &&
        bytes[1] == 0x00 &&
        bytes[2] == 0xFE &&
        bytes[3] == 0xFF) {
      return 'utf-32be';
    }
    // UTF-32 LE BOM: FF FE 00 00
    if (bytes[0] == 0xFF &&
        bytes[1] == 0xFE &&
        bytes[2] == 0x00 &&
        bytes[3] == 0x00) {
      return 'utf-32le';
    }
  }

  // Check 3-byte BOMs.
  if (len >= 3) {
    // UTF-8 BOM: EF BB BF
    if (bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return 'utf-8';
    }
  }

  // Check 2-byte BOMs.
  if (len >= 2) {
    // UTF-16 BE BOM: FE FF
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return 'utf-16be';
    }
    // UTF-16 LE BOM: FF FE
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return 'utf-16le';
    }
  }

  return null;
}

/// Returns `true` if [bytes] can be successfully decoded as UTF-8.
///
/// Uses [utf8.decode] with `allowMalformed: false`. Any [FormatException]
/// (invalid byte sequence) causes the method to return `false`. Note that
/// this is a structural validity check — it does not distinguish UTF-8 from
/// pure ASCII (ASCII is a strict subset of UTF-8 and will return `true`).
///
/// An empty byte sequence returns `true` because it is vacuously valid UTF-8.
bool _isValidUtf8(Uint8List bytes) {
  try {
    // ignore: unnecessary_ignore
    utf8.decode(bytes, allowMalformed: false);
    return true;
  } on FormatException {
    return false;
  }
}

/// Returns `true` when more than 15% of the bytes in [sample] are ≥ `0x80`.
///
/// This heuristic is used to promote CJK candidate encodings (which use
/// multi-byte sequences in the high byte range) to the front of the probe
/// list. A threshold of >15% is chosen to avoid false promotion on Western
/// 8-bit text that may have a small number of accented characters.
bool _looksMultibyte(Uint8List sample) {
  if (sample.isEmpty) return false;
  var highByteCount = 0;
  for (final b in sample) {
    if (b >= 0x80) highByteCount++;
  }
  // Promote CJK when more than 15% of bytes are in the high range.
  return highByteCount / sample.length > 0.15;
}

/// Probes [bytes] against each candidate encoding using
/// [Charset.canDecode] and returns the IANA label of the first matching
/// encoding.
///
/// CJK candidates are moved to the front of the probe order when
/// [_looksMultibyte] returns `true` for [bytes]. This reduces false Western
/// matches on CJK content with dense high-byte sequences.
///
/// The probe is a structural validity check: [Charset.canDecode] decodes the
/// sample and rejects it if the decoded string contains the Unicode
/// replacement character U+FFFD. This makes the probe reliable for CJK
/// multi-byte encodings (which have strict structural constraints) but less
/// discriminating among Western 8-bit encodings (which can accept almost any
/// byte sequence).
///
/// Returns `'windows-1252'` if no candidate matches. This follows the WHATWG
/// Encoding specification fallback, as Windows-1252 is the most common legacy
/// Western encoding and a superset of ISO-8859-1.
String _probeEncoding(Uint8List bytes) {
  // Build the probe order based on whether the sample looks like multi-byte
  // (CJK) content.
  final candidates = _looksMultibyte(bytes)
      ? [..._cjkCandidates, ..._westernCandidates]
      : [..._westernCandidates, ..._cjkCandidates];

  for (final encoding in candidates) {
    if (Charset.canDecode(encoding, bytes)) {
      // Return the IANA label from the explicit map rather than encoding.name,
      // because some codecs use non-hyphenated or non-IANA internal names.
      return _ianaLabels[encoding] ?? encoding.name;
    }
  }

  // Fallback: windows-1252 per the WHATWG Encoding specification.
  return 'windows-1252';
}
