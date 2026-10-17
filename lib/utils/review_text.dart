import 'text_scan.dart';

/// Turns the markdown/HTML mix that AniList reviews are written in into
/// readable plain text.
///
/// Images and video embeds are dropped, links keep only their text,
/// emphasis/centring/header markers are removed, and spoilers
/// (`~!hidden!~`) are replaced by [spoilerPlaceholder] so nothing is
/// revealed. Runs of three or more newlines collapse into one blank line.
String cleanReviewText(String? raw, {String spoilerPlaceholder = '[spoiler]'}) {
  if (raw == null) return '';
  return _memo.of('$spoilerPlaceholder\u0000$raw', () => _clean(raw, spoilerPlaceholder));
}

final _memo = LruMemo();

String _clean(String raw, String spoilerPlaceholder) {
  var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // Spoilers go first so nothing inside them (images, links…) survives, and
  // become a sentinel so later steps can't mangle the placeholder text.
  text = replaceSpoilers(text, _spoilerSentinel);
  for (final pattern in _embeds) {
    text = text.replaceAll(pattern, '');
  }
  text = _stripHtml(text);
  text = text.replaceAllMapped(_link, (m) => m[1]!);
  text = _stripLineMarkers(text);
  text = _stripEmphasis(text);
  text = _decodeEntities(text);
  return text
      .replaceAll(_lineEdgeSpaces, '')
      .replaceAll(_extraNewlines, '\n\n')
      .trim()
      .replaceAll(_spoilerSentinel, spoilerPlaceholder);
}

// A private-use character that never appears in real text.
const _spoilerSentinel = '';

// AniList's img(url), img220(url) and img50%(url), video embeds, markdown
// images and <img> tags.
final _embeds = [
  RegExp(r'(?<![A-Za-z0-9_])(?:img\d*%?|youtube|webm)\([^)\s(]{0,2048}\)', caseSensitive: false),
  RegExp(r'!\[[^\[\]]{0,1000}\]\([^)(]{0,2048}\)'),
  RegExp(r'<img\b[^<>]{0,1000}>', caseSensitive: false),
];

final _lineBreakTag = RegExp(r'<br\s*/?>', caseSensitive: false);
// Closing block-level tags end a line, so "<h1>Story</h1>Text" doesn't
// read as "StoryText".
final _blockEndTag = RegExp(
  r'</(?:p|div|h[1-6]|li|ul|ol|blockquote|center|pre|table|tr)\s*>|<hr\s*/?>',
  caseSensitive: false,
);
// Only real tags: "<3" or "2 < 3 > 1" are left alone.
final _anyTag = RegExp(r'</?[A-Za-z][A-Za-z0-9]*(?:\s[^<>]{0,1000})?/?>');

String _stripHtml(String text) => text
    .replaceAll(_lineBreakTag, '\n')
    .replaceAll(_blockEndTag, '\n')
    .replaceAll(_anyTag, '');

final _link = RegExp(r'\[([^\[\]]{0,1000})\]\([^)(]{0,2048}\)');

final _horizontalRule = RegExp(r'^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$', multiLine: true);
final _header = RegExp(r'^[ \t]*#{1,6}[ \t]*', multiLine: true);
final _blockquote = RegExp(r'^[ \t]*(?:>[ \t]?)+', multiLine: true);
final _listItem = RegExp(r'^[ \t]*[-*+][ \t]+', multiLine: true);

/// Removes markers that only mean something at the start of a line. Quotes
/// go before headers (">## Title"), rules before list items so "* * *"
/// isn't read as a bullet.
String _stripLineMarkers(String text) => text
    .replaceAll(_blockquote, '')
    .replaceAll(_horizontalRule, '')
    .replaceAll(_header, '')
    .replaceAll(_listItem, '• ');

// A span's text stops where the closing [mark] run starts, which is where a
// lazy match would end anyway; the cap keeps unclosed openers from rescanning
// each other. Bold may wrap onto the next line, but never across a blank line.
String _span(String mark, int count) =>
    '((?:[^\n$mark]|$mark(?!${mark * (count - 1)})|\n(?!\n)){1,2000}?)';

final _emphasis = [
  RegExp(r'\*\*\*' + _span(r'\*', 3) + r'\*\*\*'),
  RegExp('___${_span('_', 3)}___'),
  RegExp(r'\*\*' + _span(r'\*', 2) + r'\*\*'),
  RegExp('__${_span('_', 2)}__'),
  RegExp(r'~~(?=\S)((?:[^~\n]|~(?!~)){1,2000}?)~~'),
  // Single markers only count around a word, so snake_case and 2*3*4 stay.
  RegExp(r'(?<![A-Za-z0-9_*])\*(?![\s*])([^*\n]{1,2000}?)(?<![\s*])\*(?![A-Za-z0-9_*])'),
  RegExp(r'(?<![A-Za-z0-9_])_(?![\s_])([^_\n]{1,2000}?)(?<![\s_])_(?![A-Za-z0-9_])'),
];

// Nested markers like "____x____" need a second pass.
const _maxEmphasisPasses = 3;

String _stripEmphasis(String text) {
  var result = text.replaceAll('~~~', '');
  for (var pass = 0; pass < _maxEmphasisPasses; pass++) {
    final before = result;
    for (final pattern in _emphasis) {
      result = result.replaceAllMapped(pattern, (m) => m[1]!);
    }
    if (result == before) break;
  }
  return result;
}

const _namedEntities = {
  'quot': '"',
  'apos': "'",
  'lt': '<',
  'gt': '>',
  'nbsp': ' ',
  'amp': '&',
};

final _entity = RegExp(r'&(?:#(\d{1,7})|#[xX]([0-9a-fA-F]{1,6})|([a-zA-Z]+));');

/// Decodes numeric and the common named entities in a single pass, last, so
/// a decoded "&lt;b&gt;" stays literal text instead of becoming a tag.
String _decodeEntities(String text) => text.replaceAllMapped(_entity, (m) {
      final code = m[1] != null
          ? int.tryParse(m[1]!)
          : (m[2] != null ? int.tryParse(m[2]!, radix: 16) : null);
      if (code != null) {
        return code > 0 && code <= 0x10FFFF ? String.fromCharCode(code) : m[0]!;
      }
      return _namedEntities[m[3]!.toLowerCase()] ?? m[0]!;
    });

final _lineEdgeSpaces = RegExp(r'^[ \t]+|[ \t]+$', multiLine: true);
final _extraNewlines = RegExp(r'\n{3,}');
