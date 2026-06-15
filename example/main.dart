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

// ignore_for_file: avoid_print

import 'dart:typed_data';

import 'package:betto_charset_detector/betto_charset_detector.dart';

void main() {
  // Example 1: UTF-8 BOM
  final utf8BomBytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x48, 0x65, 0x6C, 0x6C, 0x6F]);
  print('UTF-8 BOM: ${detectCharset(utf8BomBytes)}'); // utf-8

  // Example 2: Plain UTF-8 text (no BOM)
  final utf8Bytes = Uint8List.fromList('Hello, world!'.codeUnits);
  print('Plain UTF-8: ${detectCharset(utf8Bytes)}'); // utf-8

  // Example 3: UTF-16 BE BOM
  final utf16BeBytes = Uint8List.fromList([0xFE, 0xFF, 0x00, 0x48]);
  print('UTF-16 BE BOM: ${detectCharset(utf16BeBytes)}'); // utf-16be

  // Example 4: Empty input
  final emptyBytes = Uint8List(0);
  print('Empty input: ${detectCharset(emptyBytes)}'); // utf-8

  // Example 5: Fallback — arbitrary bytes that are not valid UTF-8
  final latin1Bytes = Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0xF3]); // "Helló" in latin-1
  print('Latin-1-ish bytes: ${detectCharset(latin1Bytes)}'); // windows-1252 or iso-8859-1
}
