/// Turns the markdown/HTML mix that AniList reviews are written in into
/// readable plain text.
///
/// Images and video embeds are dropped, links keep only their text,
/// emphasis/centring/header markers are removed, and spoilers
/// (`~!hidden!~`) are replaced by [spoilerPlaceholder] so nothing is
/// revealed. Runs of three or more newlines collapse into one blank line.
String cleanReviewText(String? raw, {String spoilerPlaceholder = '[spoiler]'}) {
  if (raw == null) return '';
  var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // Spoilers go first so nothing inside them (images, links…) survives, and
  // become a sentinel so later steps can't mangle the placeholder text.
  text = text.replaceAll(_spoiler, _spoilerSentinel);
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

final _spoiler = RegExp(r'~!([\s\S]*?)!~');

// AniList's img(url), img220(url) and img50%(url), video embeds, markdown
// images and <img> tags.
final _embeds = [
  RegExp(r'(?<![A-Za-z0-9_])(?:img\d*%?|youtube|webm)\([^)\s]*\)', caseSensitive: false),
  RegExp(r'!\[[^\]]*\]\([^)]*\)'),
  RegExp(r'<img\b[^>]*>', caseSensitive: false),
];

final _lineBreakTag = RegExp(r'<br\s*/?>', caseSensitive: false);
// Closing block-level tags end a line, so "<h1>Story</h1>Text" doesn't
// read as "StoryText".
final _blockEndTag = RegExp(
  r'</(?:p|div|h[1-6]|li|ul|ol|blockquote|center|pre|table|tr)\s*>|<hr\s*/?>',
  caseSensitive: false,
);
// Only real tags: "<3" or "2 < 3 > 1" are left alone.
final _anyTag = RegExp(r'</?[A-Za-z][A-Za-z0-9]*(?:\s[^<>]*)?/?>');

String _stripHtml(String text) => text
    .replaceAll(_lineBreakTag, '\n')
    .replaceAll(_blockEndTag, '\n')
    .replaceAll(_anyTag, '');

final _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');

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

// Bold may wrap onto the next line, but never across a blank line.
const _withinParagraph = r'((?:[^\n]|\n(?!\n))+?)';

final _emphasis = [
  RegExp(r'\*\*\*' + _withinParagraph + r'\*\*\*'),
  RegExp('___${_withinParagraph}___'),
  RegExp(r'\*\*' + _withinParagraph + r'\*\*'),
  RegExp('__${_withinParagraph}__'),
  RegExp(r'~~(?=\S)(.+?)~~'),
  // Single markers only count around a word, so snake_case and 2*3*4 stay.
  RegExp(r'(?<![A-Za-z0-9_*])\*(?![\s*])(.+?)(?<![\s*])\*(?![A-Za-z0-9_*])'),
  RegExp(r'(?<![A-Za-z0-9_])_(?![\s_])(.+?)(?<![\s_])_(?![A-Za-z0-9_])'),
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
