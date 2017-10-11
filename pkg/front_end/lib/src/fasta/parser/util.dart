// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.parser.util;

import '../scanner.dart' show Token;

import '../scanner/token_constants.dart' show KEYWORD_TOKEN;

import '../../scanner/token.dart' show BeginToken;

bool isKeywordOrIdentifier(Token token) =>
    token.kind == KEYWORD_TOKEN || token.isIdentifier;

/// Returns true if [token] is the symbol or keyword [value].
bool optional(String value, Token token) {
  return identical(value, token.stringValue);
}

/// Returns the close brace, bracket, or parenthesis of [left]. For '<', it may
/// return null.
Token closeBraceTokenFor(BeginToken left) => left.endToken;
