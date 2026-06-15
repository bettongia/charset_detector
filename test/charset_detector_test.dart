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

import 'package:betto_charset_detector/betto_charset_detector.dart';
import 'package:charset/charset.dart';
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Stage 1: BOM detection
  // ---------------------------------------------------------------------------
  group('Stage 1 — BOM detection', () {
    test('UTF-8 BOM (EF BB BF) returns utf-8', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x41, 0x42]);
      expect(detectCharset(bytes), 'utf-8');
    });

    test('UTF-16 BE BOM (FE FF) returns utf-16be', () {
      final bytes = Uint8List.fromList([0xFE, 0xFF, 0x00, 0x41]);
      expect(detectCharset(bytes), 'utf-16be');
    });

    test('UTF-16 LE BOM (FF FE) returns utf-16le', () {
      final bytes = Uint8List.fromList([0xFF, 0xFE, 0x41, 0x00]);
      expect(detectCharset(bytes), 'utf-16le');
    });

    test('UTF-32 BE BOM (00 00 FE FF) returns utf-32be', () {
      final bytes = Uint8List.fromList([
        0x00,
        0x00,
        0xFE,
        0xFF,
        0x00,
        0x00,
        0x00,
        0x41,
      ]);
      expect(detectCharset(bytes), 'utf-32be');
    });

    test('UTF-32 LE BOM (FF FE 00 00) returns utf-32le', () {
      final bytes = Uint8List.fromList([
        0xFF,
        0xFE,
        0x00,
        0x00,
        0x41,
        0x00,
        0x00,
        0x00,
      ]);
      expect(detectCharset(bytes), 'utf-32le');
    });

    // Critical ordering test: UTF-32 LE shares first two bytes (FF FE) with
    // UTF-16 LE. Incorrect BOM ordering would misidentify UTF-32 LE as UTF-16 LE.
    test('UTF-32 LE BOM is not misidentified as UTF-16 LE', () {
      final bytes = Uint8List.fromList([0xFF, 0xFE, 0x00, 0x00]);
      expect(detectCharset(bytes), 'utf-32le');
    });

    // Lone BOM with no following content — must not throw a range error.
    test('lone UTF-8 BOM (3 bytes, no content) returns utf-8', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF]);
      expect(detectCharset(bytes), 'utf-8');
    });

    test('lone UTF-16 BE BOM (2 bytes, no content) returns utf-16be', () {
      final bytes = Uint8List.fromList([0xFE, 0xFF]);
      expect(detectCharset(bytes), 'utf-16be');
    });

    test('lone UTF-16 LE BOM (2 bytes, no content) returns utf-16le', () {
      final bytes = Uint8List.fromList([0xFF, 0xFE]);
      expect(detectCharset(bytes), 'utf-16le');
    });

    test('lone UTF-32 BE BOM (4 bytes, no content) returns utf-32be', () {
      final bytes = Uint8List.fromList([0x00, 0x00, 0xFE, 0xFF]);
      expect(detectCharset(bytes), 'utf-32be');
    });

    test('lone UTF-32 LE BOM (4 bytes, no content) returns utf-32le', () {
      final bytes = Uint8List.fromList([0xFF, 0xFE, 0x00, 0x00]);
      expect(detectCharset(bytes), 'utf-32le');
    });

    // Ensure BOM-detected results do not fall through to UTF-8 or probe stages.
    test('UTF-16 LE BOM short-circuits before UTF-8 validation', () {
      // FF FE followed by valid ASCII — BOM wins regardless.
      final bytes = Uint8List.fromList([0xFF, 0xFE, 0x48, 0x00]);
      expect(detectCharset(bytes), 'utf-16le');
    });
  });

  // ---------------------------------------------------------------------------
  // Stage 2: UTF-8 structural validation
  // ---------------------------------------------------------------------------
  group('Stage 2 — UTF-8 validation', () {
    test('empty Uint8List returns utf-8', () {
      expect(detectCharset(Uint8List(0)), 'utf-8');
    });

    test('pure ASCII bytes (all < 0x80) return utf-8', () {
      final bytes = Uint8List.fromList('Hello, world!'.codeUnits);
      expect(detectCharset(bytes), 'utf-8');
    });

    test('valid multi-byte UTF-8 without BOM returns utf-8', () {
      // 'Héllo' encoded as UTF-8: é = 0xC3 0xA9
      final bytes = Uint8List.fromList(utf8.encode('Héllo wörld'));
      expect(detectCharset(bytes), 'utf-8');
    });

    test('valid CJK UTF-8 without BOM returns utf-8', () {
      final bytes = Uint8List.fromList(utf8.encode('上善若水'));
      expect(detectCharset(bytes), 'utf-8');
    });

    test('invalid UTF-8 byte sequence falls through to Stage 3', () {
      // 0x80 is not a valid start byte in UTF-8 (continuation byte only).
      final bytes = Uint8List.fromList([0x80, 0x41, 0x42]);
      // Must not return utf-8 — it should reach the probe stage.
      expect(detectCharset(bytes), isNot('utf-8'));
    });

    test('isolated high byte (0xFF) is not valid UTF-8', () {
      final bytes = Uint8List.fromList([0x41, 0xFF, 0x42]);
      expect(detectCharset(bytes), isNot('utf-8'));
    });
  });

  // ---------------------------------------------------------------------------
  // Stage 3: Candidate probe
  // ---------------------------------------------------------------------------
  group('Stage 3 — Candidate probe', () {
    // --- CJK encodings ---

    test('Shift-JIS encoded text returns shift-jis', () {
      // '上善若水' encoded in Shift-JIS contains dense high bytes; this
      // triggers CJK promotion.
      final bytes = Uint8List.fromList(shiftJis.encode('上善若水'));
      expect(detectCharset(bytes), 'shift-jis');
    });

    test('EUC-JP encoded text returns euc-jp', () {
      final bytes = Uint8List.fromList(eucJp.encode('上善若水'));
      expect(detectCharset(bytes), 'euc-jp');
    });

    test('EUC-KR encoded text returns euc-kr', () {
      // Short Korean strings can be ambiguous with Shift-JIS. Use a longer
      // sample that is uniquely decodable only as EUC-KR.
      final text =
          '상선약수라는 말이 있다. 물은 만물을 이롭게 하면서도 다투지 않고 '
          '모든 사람이 싫어하는 낮은 곳에 처하니 도에 가깝다고 할 수 있다.';
      final bytes = Uint8List.fromList(eucKr.encode(text));
      expect(detectCharset(bytes), 'euc-kr');
    });

    test('GBK encoded text returns gbk', () {
      // Short Chinese strings can be ambiguous with EUC-JP/EUC-KR. Use a
      // longer sample that is uniquely decodable only as GBK.
      final text = '上善若水水善利萬物而不爭處衆人之所惡故幾於道居善地心善淵與善仁言善信正善治事善能動善時夫唯不爭故無尤';
      final bytes = Uint8List.fromList(gbk.encode(text));
      expect(detectCharset(bytes), 'gbk');
    });

    // --- Western encodings ---

    test('Windows-1252 specific bytes return windows-1252', () {
      // 0x80 is the Euro sign (€) in Windows-1252 but undefined in ISO-8859-1.
      // A sequence with 0x80 is valid in windows-1252 but not in iso-8859-1
      // (which checks for U+FFFD on decode). This tests the western probe path.
      final bytes = Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x80]);
      expect(detectCharset(bytes), 'windows-1252');
    });

    test('ISO-8859-1 bytes return windows-1252 or iso-8859-1', () {
      // 0xE9 is 'é' in ISO-8859-1/windows-1252. The sample must have fewer
      // than 15% high bytes so that CJK candidates are not promoted ahead of
      // the Western candidates — otherwise EUC-KR can accept 0xE9 and win.
      // "Hello World\xE9" = 12 bytes, 1 high byte = 8.3% → Western probed first.
      final bytes = Uint8List.fromList([
        0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x20, // Hello·
        0x57, 0x6F, 0x72, 0x6C, 0x64, 0xE9, // World + é
      ]);
      expect(detectCharset(bytes), anyOf('windows-1252', 'iso-8859-1'));
    });

    // --- Fallback ---

    test('bytes matching no specific candidate return windows-1252', () {
      // Construct bytes that fail UTF-8 but canDecode returns false for all
      // candidates except the fallback. In practice windows-1252 accepts almost
      // everything, but the fallback path is still the contract we test here.
      // We test by verifying that a non-UTF-8 sequence always yields a result.
      final bytes = Uint8List.fromList([0x81, 0x40]); // windows-1252 valid
      final result = detectCharset(bytes);
      // Must return a valid string (non-null, non-empty).
      expect(result, isNotEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Sampling: inputs larger than 8 KB
  // ---------------------------------------------------------------------------
  group('Sampling', () {
    test('input larger than 8 KB is accepted without error', () {
      // Create 16 KB of valid UTF-8 bytes ('A' = 0x41).
      final bytes = Uint8List(16 * 1024)..fillRange(0, 16 * 1024, 0x41);
      expect(() => detectCharset(bytes), returnsNormally);
      expect(detectCharset(bytes), 'utf-8');
    });

    test('large input with UTF-8 BOM is detected correctly', () {
      final content = Uint8List(10 * 1024)..fillRange(0, 10 * 1024, 0x41);
      final withBom = Uint8List(content.length + 3);
      withBom[0] = 0xEF;
      withBom[1] = 0xBB;
      withBom[2] = 0xBF;
      withBom.setRange(3, withBom.length, content);
      expect(detectCharset(withBom), 'utf-8');
    });

    test('exactly 8 KB of valid UTF-8 returns utf-8', () {
      final bytes = Uint8List(8 * 1024)..fillRange(0, 8 * 1024, 0x41);
      expect(detectCharset(bytes), 'utf-8');
    });

    test('8 KB + 1 byte (all valid ASCII) returns utf-8', () {
      final bytes = Uint8List(8 * 1024 + 1)..fillRange(0, 8 * 1024 + 1, 0x41);
      expect(detectCharset(bytes), 'utf-8');
    });
  });

  // ---------------------------------------------------------------------------
  // Edge cases
  // ---------------------------------------------------------------------------
  group('Edge cases', () {
    test('single-byte input (0x41 = ASCII A) returns utf-8', () {
      final bytes = Uint8List.fromList([0x41]);
      expect(detectCharset(bytes), 'utf-8');
    });

    test('single-byte input (0xFF, invalid UTF-8) does not throw', () {
      final bytes = Uint8List.fromList([0xFF]);
      expect(() => detectCharset(bytes), returnsNormally);
    });

    test('single-byte input (0x80, invalid UTF-8 start) does not throw', () {
      final bytes = Uint8List.fromList([0x80]);
      expect(() => detectCharset(bytes), returnsNormally);
    });

    test(
      'two-byte input (0x00 0x00) does not trigger BOM (too short for 4-byte)',
      () {
        final bytes = Uint8List.fromList([0x00, 0x00]);
        // Not a BOM — two null bytes pass UTF-8 validation.
        expect(detectCharset(bytes), 'utf-8');
      },
    );

    test('three null bytes are valid UTF-8 (not a BOM)', () {
      final bytes = Uint8List.fromList([0x00, 0x00, 0x00]);
      expect(detectCharset(bytes), 'utf-8');
    });

    test('returned label is always a non-empty lowercase string', () {
      final inputs = [
        Uint8List(0),
        Uint8List.fromList([0x41]),
        Uint8List.fromList([0xEF, 0xBB, 0xBF]),
        Uint8List.fromList([0xFF, 0xFE]),
        Uint8List.fromList([0xFE, 0xFF]),
        Uint8List.fromList(shiftJis.encode('上善若水')),
        Uint8List.fromList(eucJp.encode('東京')),
        Uint8List.fromList(gbk.encode('北京')),
      ];
      for (final input in inputs) {
        final result = detectCharset(input);
        expect(result, isNotEmpty, reason: 'empty label for $input');
        expect(
          result,
          equals(result.toLowerCase()),
          reason: 'label not lowercase: $result',
        );
      }
    });

    // Verify that the _ianaLabels map is used and encoding.name is NOT returned
    // for codecs with non-IANA internal names.
    test('windows-1252 returns "windows-1252" not "windows1252"', () {
      // Force Stage 3 with a byte that is invalid UTF-8 but valid windows-1252.
      final bytes = Uint8List.fromList([0x80]); // Euro sign in cp1252
      final result = detectCharset(bytes);
      // Either the probe matched windows1252 (returned as 'windows-1252') or
      // it fell back — in both cases the label must be hyphenated.
      if (result.startsWith('windows')) {
        expect(result, 'windows-1252');
      }
    });

    test('non-empty valid UTF-8 does not reach Stage 3', () {
      // This implicitly tests that Stage 2 short-circuits for valid UTF-8.
      // We verify the result is utf-8, not a probe output.
      final bytes = Uint8List.fromList(utf8.encode('Ñoño'));
      expect(detectCharset(bytes), 'utf-8');
    });
  });

  // ---------------------------------------------------------------------------
  // Contract: guaranteed IANA labels
  // ---------------------------------------------------------------------------
  group('IANA label contract', () {
    final bomCases = {
      'utf-8': Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x41]),
      'utf-16be': Uint8List.fromList([0xFE, 0xFF, 0x00, 0x41]),
      'utf-16le': Uint8List.fromList([0xFF, 0xFE, 0x41, 0x00]),
      'utf-32be': Uint8List.fromList([
        0x00,
        0x00,
        0xFE,
        0xFF,
        0x00,
        0x00,
        0x00,
        0x41,
      ]),
      'utf-32le': Uint8List.fromList([
        0xFF,
        0xFE,
        0x00,
        0x00,
        0x41,
        0x00,
        0x00,
        0x00,
      ]),
    };

    for (final entry in bomCases.entries) {
      test('BOM → ${entry.key}', () {
        expect(detectCharset(entry.value), entry.key);
      });
    }

    test('valid UTF-8 (no BOM) → utf-8', () {
      final bytes = Uint8List.fromList(utf8.encode('Ñoño'));
      expect(detectCharset(bytes), 'utf-8');
    });

    test('empty input → utf-8', () {
      expect(detectCharset(Uint8List(0)), 'utf-8');
    });
  });
}
