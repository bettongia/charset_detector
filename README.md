# betto_charset_detector

A pure-Dart charset detection library that works on all Dart and Flutter target
platforms — mobile, web, and desktop. No Flutter plugin infrastructure, no
native code, no FFI.

## Features

- Detects UTF-8, UTF-16 BE/LE, UTF-32 BE/LE via byte-order mark (BOM)
- Validates UTF-8 structural integrity without a BOM
- Probes legacy 8-bit and CJK encodings via the [`charset`][charset] package:
  - Western: `windows-1252`, `iso-8859-1`, `iso-8859-2`, `iso-8859-15`
  - CJK: `shift-jis`, `euc-jp`, `euc-kr`, `gbk`
- Falls back to `windows-1252` (the WHATWG Encoding spec default)
- Returns lowercase IANA encoding labels consistent with `dart:convert` and
  the browser `TextDecoder` API
- Works on web (no `dart:io` required), mobile, and desktop

## Getting started

Add `betto_charset_detector` to your `pubspec.yaml`:

```yaml
dependencies:
  betto_charset_detector: ^0.1.0-dev.1
```

Run `dart pub get` (or `flutter pub get`).

## Usage

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:betto_charset_detector/betto_charset_detector.dart';

void main() {
  final bytes = File('my_file.txt').readAsBytesSync();
  final encoding = detectCharset(Uint8List.fromList(bytes));
  print('Detected encoding: $encoding'); // e.g. "utf-8" or "shift-jis"
}
```

### Return values

`detectCharset` always returns a lowercase IANA label string:

| Detected encoding | Returned label  |
| :---------------- | :-------------- |
| UTF-8 (with BOM)  | `utf-8`         |
| UTF-8 (no BOM)    | `utf-8`         |
| UTF-16 big-endian | `utf-16be`      |
| UTF-16 little-endian | `utf-16le`   |
| UTF-32 big-endian | `utf-32be`      |
| UTF-32 little-endian | `utf-32le`   |
| Windows-1252      | `windows-1252`  |
| ISO-8859-1        | `iso-8859-1`    |
| ISO-8859-2        | `iso-8859-2`    |
| ISO-8859-15       | `iso-8859-15`   |
| Shift-JIS         | `shift-jis`     |
| EUC-JP            | `euc-jp`        |
| EUC-KR            | `euc-kr`        |
| GBK               | `gbk`           |

## Detection algorithm

Detection proceeds through three ordered stages, falling through only when
necessary:

1. **BOM inspection** — deterministic; longest-match first (4-byte UTF-32
   before 2-byte UTF-16).
2. **UTF-8 structural validation** — a leading 8 KB sample is decoded with
   `utf8.decode(allowMalformed: false)`. Valid decode → `utf-8`.
3. **Candidate probe** — the sample is tested against each candidate encoding
   using `Charset.canDecode` from the `charset` package. CJK encodings are
   promoted when >15% of sample bytes are ≥ 0x80.

Fallback: `windows-1252`.

Only the first 8 KB of input is read; the boundary is a hard byte cut (not
aligned to character boundaries). This is a documented trade-off: the edge
case of a valid UTF-8 file whose multi-byte sequence spans the 8 KB boundary
is vanishingly rare and the consequence (misdetected as `windows-1252`) is
mild.

Empty input returns `utf-8` (empty byte sequences are valid UTF-8).

## Additional information

- [Package specification](docs/spec/README.md)
- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)

[charset]: https://pub.dev/packages/charset
