/// Replaces every `~!…!~` spoiler span with [replacement] in one linear pass.
///
/// A regex here backtracks quadratically on text with many openers and no
/// closer; once one search finds no `!~`, no later opener can match either.
String replaceSpoilers(String text, String replacement) {
  var start = text.indexOf('~!');
  if (start < 0) return text;
  final out = StringBuffer();
  var copied = 0;
  while (start >= 0) {
    final close = text.indexOf('!~', start + 2);
    if (close < 0) break;
    out
      ..write(text.substring(copied, start))
      ..write(replacement);
    copied = close + 2;
    start = text.indexOf('~!', copied);
  }
  out.write(text.substring(copied));
  return out.toString();
}

/// A small least-recently-used cache for pure text-cleaning results, so a
/// rebuild or a scroll doesn't clean the same text again.
class LruMemo {
  LruMemo({this.capacity = 200, this.maxKeyLength = 50000});

  final int capacity;

  /// Longer inputs are computed but not stored, to bound memory.
  final int maxKeyLength;
  final _entries = <String, String>{};

  String of(String key, String Function() compute) {
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit;
      return hit;
    }
    final value = compute();
    if (key.length <= maxKeyLength) {
      _entries[key] = value;
      if (_entries.length > capacity) _entries.remove(_entries.keys.first);
    }
    return value;
  }
}
