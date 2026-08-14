//
// Copyright (c) 2025 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation

/// A word on the command line, together with enough information to splice a completion
/// back into the buffer it was parsed from.
struct REPLToken {
  /// the unescaped, unquoted value of the word
  let value: String
  /// the index in the buffer at which the word starts
  let start: String.Index
  /// whether the word was introduced with a double quote
  let isQuoted: Bool
}

/// Splits `buffer` into words, honouring double quotes and backslash escapes. Unterminated
/// quotes and trailing backslashes are tolerated, as the buffer is typically a line that is
/// still being edited.
///
/// The second element of the result is true if the buffer ends on a word separator, i.e. if
/// the next character typed would begin a new word.
func replTokenize(_ buffer: String) -> (tokens: [REPLToken], endsWithSeparator: Bool) {
  var tokens = [REPLToken]()
  var endsWithSeparator = true
  var index = buffer.startIndex

  while index < buffer.endIndex {
    while index < buffer.endIndex, buffer[index].isWhitespace {
      index = buffer.index(after: index)
    }
    guard index < buffer.endIndex else { break }

    let start = index
    var value = ""
    var isQuoted = false
    var inQuotes = false

    scan: while index < buffer.endIndex {
      let character = buffer[index]

      switch character {
      case "\\":
        let next = buffer.index(after: index)
        if next < buffer.endIndex {
          value.append(buffer[next])
          index = buffer.index(after: next)
        } else {
          index = next
        }
      case "\"":
        if index == start { isQuoted = true }
        inQuotes.toggle()
        index = buffer.index(after: index)
      default:
        if character.isWhitespace, !inQuotes { break scan }
        value.append(character)
        index = buffer.index(after: index)
      }
    }

    tokens.append(REPLToken(value: value, start: start, isQuoted: isQuoted))
    endsWithSeparator = index < buffer.endIndex
  }

  return (tokens, endsWithSeparator)
}

/// Escapes `value` such that `replTokenize()` will yield it back as a single word. Spaces and
/// other characters that are significant to the tokenizer are escaped with a backslash, unless
/// the word being completed was introduced with a double quote, in which case the quoting style
/// the user started with is preserved.
///
/// A completion that names a block ends in a path separator, and is left unterminated when
/// quoted so that the path can be extended by typing further components.
func replEscape(_ value: String, quoted: Bool = false) -> String {
  if quoted {
    var escaped = "\""
    for character in value {
      if character == "\"" || character == "\\" { escaped.append("\\") }
      escaped.append(character)
    }
    if !value.hasSuffix(String(ocaPathSeparator)) { escaped.append("\"") }
    return escaped
  } else {
    var escaped = ""
    for character in value {
      if character.isWhitespace || character == "\"" || character == "\\" {
        escaped.append("\\")
      }
      escaped.append(character)
    }
    return escaped
  }
}

extension String {
  /// The word the cursor is on, i.e. the word a completion would replace.
  var replFinalWord: String {
    let (tokens, endsWithSeparator) = replTokenize(self)
    guard let last = tokens.last, !endsWithSeparator else { return "" }
    return last.value
  }
}
