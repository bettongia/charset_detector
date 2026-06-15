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

/// Manual investigation script for `Charset.canDecode` behaviour.
///
/// This tool exists because the `charset` package's `canDecode` is a structural
/// validity check, not a statistical detector. Many short byte sequences are
/// structurally valid in more than one encoding (e.g. a short EUC-KR sequence
/// may also pass Shift-JIS validation). This script was used to determine which
/// test inputs are long enough to be uniquely discriminating, and to verify the
/// probe order used in `_probeEncoding`.
///
/// Run with: `dart run tool/probe_test.dart`
library;

import 'dart:convert';

import 'package:charset/charset.dart';

void main() {
  // Test: EUC-KR encoded text
  final eucKrBytes = eucKr.encode('상선이 물과 같다');
  print('EUC-KR bytes (first 10): ${eucKrBytes.take(10).toList()}');
  print('canDecode shiftJis: ${Charset.canDecode(shiftJis, eucKrBytes)}');
  print('canDecode eucJp:    ${Charset.canDecode(eucJp, eucKrBytes)}');
  print('canDecode eucKr:    ${Charset.canDecode(eucKr, eucKrBytes)}');
  print('canDecode gbk:      ${Charset.canDecode(gbk, eucKrBytes)}');
  print('');

  // Test: GBK encoded text
  final gbkBytes = gbk.encode('上善若水');
  print('GBK bytes (first 10): ${gbkBytes.take(10).toList()}');
  print('canDecode shiftJis: ${Charset.canDecode(shiftJis, gbkBytes)}');
  print('canDecode eucJp:    ${Charset.canDecode(eucJp, gbkBytes)}');
  print('canDecode eucKr:    ${Charset.canDecode(eucKr, gbkBytes)}');
  print('canDecode gbk:      ${Charset.canDecode(gbk, gbkBytes)}');
  print('');

  // Test latin bytes
  final latinBytes = [0x48, 0x65, 0x6C, 0x6C, 0xE9];
  print('Latin bytes: $latinBytes');
  print('canDecode windows1252: ${Charset.canDecode(windows1252, latinBytes)}');
  print('canDecode latin1:      ${Charset.canDecode(latin1, latinBytes)}');
  print('canDecode eucKr:       ${Charset.canDecode(eucKr, latinBytes)}');
  print('canDecode shiftJis:    ${Charset.canDecode(shiftJis, latinBytes)}');
  print('canDecode gbk:         ${Charset.canDecode(gbk, latinBytes)}');
  print('');

  // Shift-JIS encoded '上善若水'
  final sjisBytes = shiftJis.encode('上善若水');
  print('ShiftJIS bytes (first 10): ${sjisBytes.take(10).toList()}');
  print('canDecode shiftJis: ${Charset.canDecode(shiftJis, sjisBytes)}');
  print('canDecode eucJp:    ${Charset.canDecode(eucJp, sjisBytes)}');
  print('canDecode eucKr:    ${Charset.canDecode(eucKr, sjisBytes)}');
  print('canDecode gbk:      ${Charset.canDecode(gbk, sjisBytes)}');
  print('');

  // EUC-JP encoded '上善若水'
  final eucJpBytes = eucJp.encode('上善若水');
  print('EUC-JP bytes (first 10): ${eucJpBytes.take(10).toList()}');
  print('canDecode shiftJis: ${Charset.canDecode(shiftJis, eucJpBytes)}');
  print('canDecode eucJp:    ${Charset.canDecode(eucJp, eucJpBytes)}');
  print('canDecode eucKr:    ${Charset.canDecode(eucKr, eucJpBytes)}');
  print('canDecode gbk:      ${Charset.canDecode(gbk, eucJpBytes)}');
  print('');

  // Korean text with more content for better discrimination
  final longerKorean =
      '상선약수라는 말이 있다. 물은 만물을 이롭게 하면서도 다투지 않고 '
      '모든 사람이 싫어하는 낮은 곳에 처하니 도에 가깝다고 할 수 있다.';
  final longerEucKrBytes = eucKr.encode(longerKorean);
  print(
    'Longer EUC-KR bytes (first 20): ${longerEucKrBytes.take(20).toList()}',
  );
  print('canDecode shiftJis: ${Charset.canDecode(shiftJis, longerEucKrBytes)}');
  print('canDecode eucJp:    ${Charset.canDecode(eucJp, longerEucKrBytes)}');
  print('canDecode eucKr:    ${Charset.canDecode(eucKr, longerEucKrBytes)}');
  print('canDecode gbk:      ${Charset.canDecode(gbk, longerEucKrBytes)}');
  print('');

  // Longer GBK text
  final longerChinese = '上善若水水善利萬物而不爭處衆人之所惡故幾於道居善地心善淵與善仁言善信正善治事善能動善時夫唯不爭故無尤';
  final longerGbkBytes = gbk.encode(longerChinese);
  print('Longer GBK bytes (first 20): ${longerGbkBytes.take(20).toList()}');
  print('canDecode shiftJis: ${Charset.canDecode(shiftJis, longerGbkBytes)}');
  print('canDecode eucJp:    ${Charset.canDecode(eucJp, longerGbkBytes)}');
  print('canDecode eucKr:    ${Charset.canDecode(eucKr, longerGbkBytes)}');
  print('canDecode gbk:      ${Charset.canDecode(gbk, longerGbkBytes)}');
}
