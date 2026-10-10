import 'translations.dart' show trf;

// AniList's media embeds: img220(url), img(url), img50%(url), webm(url),
// youtube(id).
final _embed = RegExp(r'\b(?:img\s*\d*%?|webm|youtube)\s*\([^)]*\)', caseSensitive: false);
final _spoiler = RegExp(r'~!(.*?)!~', dotAll: true);
final _lineBreak = RegExp(r'<br\s*/?>', caseSensitive: false);
final _paragraphEnd = RegExp(r'</p\s*>', caseSensitive: false);
final _htmlLink = RegExp(r'<a\b[^>]*>(.*?)</a\s*>', caseSensitive: false, dotAll: true);
final _markdownImage = RegExp(r'!\[[^\]]*\]\([^)]*\)');
final _markdownLink = RegExp(r'\[([^\]]+)\]\([^)\s]+\)');
// Only well-known tag names, so text like "a <b and c> d" or "<3" survives.
final _htmlTag = RegExp(
  r'</?(?:a|b|i|u|s|p|br|hr|em|strong|span|div|center|img|h[1-6]|ul|ol|li|'
  r'blockquote|code|pre|del|strike|sup|sub|small|big)\b[^>]*>',
  caseSensitive: false,
);
final _center = RegExp(r'~~~(.+?)~~~', dotAll: true);
final _strike = RegExp(r'~~(.+?)~~', dotAll: true);
final _bold = RegExp(r'(\*\*|__)(.+?)\1', dotAll: true);
// Single * or _ only counts as italics around a word, so snake_case and
// "2 * 3 * 4" are left alone.
final _italic = RegExp(r'(?<![\w*_])([*_])(?=\S)([^*_\n]+?)(?<=\S)\1(?![\w*_])');
final _heading = RegExp(r'^#{1,6}[ \t]+', multiLine: true);
final _quote = RegExp(r'^>[ \t]?', multiLine: true);
final _rule = RegExp(r'^[ \t]*(?:-{3,}|\*{3,}|_{3,})[ \t]*$', multiLine: true);
final _codeFence = RegExp(r'^[ \t]*```.*$', multiLine: true);
final _inlineCode = RegExp(r'`([^`\n]+)`');
final _numericEntity = RegExp(r'&#(x[0-9a-f]+|\d+);', caseSensitive: false);
final _spaces = RegExp(r'[ \t]{2,}');
final _edgeSpaces = RegExp(r'^[ \t]+|[ \t]+$', multiLine: true);
final _blankLines = RegExp(r'\n{3,}');

// A private-use character that never appears in real text, standing in for
// spoilers until the end so no later rule can rewrite the label.
const _spoilerSentinel = '';

const _namedEntities = {
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&apos;': "'",
  '&nbsp;': ' ',
};

/// Turns AniList activity markdown/HTML into readable plain text: spoilers
/// become [spoilerLabel], images and video embeds are dropped, links keep
/// their text, formatting marks and tags are removed and `<br>` becomes a
/// line break.
String cleanActivityText(String? text, {String spoilerLabel = '[spoiler]'}) {
  if (text == null || text.isEmpty) return '';
  var result = text
      .replaceAll('\r\n', '\n')
      // Spoilers go first so nothing inside them (images, links) leaks out.
      .replaceAll(_spoiler, _spoilerSentinel)
      .replaceAll(_embed, '')
      .replaceAll(_lineBreak, '\n')
      .replaceAll(_paragraphEnd, '\n')
      .replaceAllMapped(_htmlLink, (m) => m[1]!)
      .replaceAll(_markdownImage, '')
      .replaceAllMapped(_markdownLink, (m) => m[1]!)
      .replaceAll(_htmlTag, '')
      .replaceAllMapped(_center, (m) => m[1]!)
      .replaceAllMapped(_strike, (m) => m[1]!)
      .replaceAllMapped(_bold, (m) => m[2]!)
      .replaceAllMapped(_italic, (m) => m[2]!)
      .replaceAll(_heading, '')
      .replaceAll(_quote, '')
      .replaceAll(_rule, '')
      .replaceAll(_codeFence, '')
      .replaceAllMapped(_inlineCode, (m) => m[1]!);
  result = _decodeEntities(result);
  return result
      .replaceAll(_spaces, ' ')
      .replaceAll(_edgeSpaces, '')
      .replaceAll(_blankLines, '\n\n')
      .trim()
      .replaceAll(_spoilerSentinel, spoilerLabel);
}

String _decodeEntities(String text) {
  var result = text.replaceAllMapped(_numericEntity, (m) {
    final value = m[1]!;
    final code = value.startsWith(RegExp('[xX]'))
        ? int.tryParse(value.substring(1), radix: 16)
        : int.tryParse(value);
    final valid = code != null && code > 0 && code <= 0x10FFFF;
    return valid ? String.fromCharCode(code) : m[0]!;
  });
  _namedEntities.forEach((entity, char) => result = result.replaceAll(entity, char));
  // Last, so "&amp;lt;" decodes to "&lt;" rather than "<".
  return result.replaceAll('&amp;', '&');
}

/// "5m ago" / "3h ago" / "2d ago" for an AniList `createdAt` (Unix seconds).
/// Timestamps slightly in the future (clock skew) read as "0m ago".
String relativeTime(int createdAt, String lang, {DateTime? now}) {
  final diff = (now ?? DateTime.now())
      .difference(DateTime.fromMillisecondsSinceEpoch(createdAt * 1000));
  if (diff.isNegative || diff.inMinutes < 60) {
    return trf('feed_minutes_ago', lang, {'n': diff.isNegative ? 0 : diff.inMinutes});
  }
  if (diff.inHours < 24) return trf('feed_hours_ago', lang, {'n': diff.inHours});
  return trf('feed_days_ago', lang, {'n': diff.inDays});
}
