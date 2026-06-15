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

/// A pure-Dart charset detection library for Dart and Flutter applications.
///
/// Detects character encodings using a three-stage pipeline:
/// 1. BOM inspection (deterministic)
/// 2. UTF-8 structural validation
/// 3. Candidate probe via the `charset` package
///
/// The single public entry point is [detectCharset].
///
/// Example:
/// ```dart
/// import 'dart:typed_data';
/// import 'package:betto_charset_detector/betto_charset_detector.dart';
///
/// final encoding = detectCharset(Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x41]));
/// // encoding == 'utf-8'
/// ```
library;

export 'src/charset_detector.dart' show detectCharset;
