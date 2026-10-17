import 'package:anispark/utils/review_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cleanReviewText', () {
    test('returns an empty string for null or blank input', () {
      expect(cleanReviewText(null), '');
      expect(cleanReviewText('   \n\n  '), '');
    });

    test('turns <br> tags into newlines and normalises CRLF', () {
      expect(cleanReviewText('one<br>two<br/>three<BR />four'), 'one\ntwo\nthree\nfour');
      expect(cleanReviewText('one\r\ntwo'), 'one\ntwo');
    });

    test('strips HTML tags but keeps their text', () {
      expect(
        cleanReviewText('<b>Bold</b> and <a href="https://x.co">a link</a>'),
        'Bold and a link',
      );
    });

    test('puts a line break after block-level tags so words do not merge', () {
      expect(
        cleanReviewText('<h1><b>Story</b></h1>One Piece starts'),
        'Story\nOne Piece starts',
      );
      expect(cleanReviewText('<p>First</p><p>Second</p>'), 'First\nSecond');
    });

    test('leaves text that only looks like a tag alone', () {
      expect(cleanReviewText('I <3 this, and 2 < 3 > 1'), 'I <3 this, and 2 < 3 > 1');
    });

    test('drops AniList, markdown and HTML images', () {
      expect(cleanReviewText('a img220(https://x.co/a.jpg) b'), 'a  b');
      expect(cleanReviewText('img(https://x.co/a.png)\nText'), 'Text');
      expect(cleanReviewText('img50%(https://x.co/a.png)Text'), 'Text');
      expect(cleanReviewText('![cover](https://x.co/a.png)Text'), 'Text');
      expect(cleanReviewText('<img src="https://x.co/a.png">Text'), 'Text');
      expect(cleanReviewText('~~~img420(https://x.co/a.png)~~~\nText'), 'Text');
    });

    test('drops youtube and webm embeds', () {
      expect(
        cleanReviewText('Watch youtube(https://youtu.be/abc) and webm(https://x.co/a.webm)!'),
        'Watch  and !',
      );
    });

    test('does not treat words ending in "img" as images', () {
      expect(cleanReviewText('svimg(1) stays'), 'svimg(1) stays');
    });

    test('unwraps links, including links with an empty url', () {
      expect(cleanReviewText('See [the wiki](https://x.co/a_b_c) now'), 'See the wiki now');
      expect(cleanReviewText('[**CHARACTERS:**]()'), 'CHARACTERS:');
    });

    test('removes an image wrapped in a link entirely', () {
      expect(cleanReviewText('[img(https://x.co/a.png)](https://x.co)Text'), 'Text');
    });

    test('removes bold and italic markers', () {
      expect(cleanReviewText('__bold__ and **strong**'), 'bold and strong');
      expect(cleanReviewText('___both___ and ***both***'), 'both and both');
      expect(cleanReviewText('_italic_ and *emphasis*'), 'italic and emphasis');
    });

    test('keeps underscores and asterisks that are not emphasis', () {
      expect(cleanReviewText('snake_case_name and 2*3*4'), 'snake_case_name and 2*3*4');
      expect(cleanReviewText('https://x.co/some_path_here'), 'https://x.co/some_path_here');
      expect(cleanReviewText('a _ b * c'), 'a _ b * c');
    });

    test('removes centring and strikethrough markers', () {
      expect(cleanReviewText('~~~Centred~~~'), 'Centred');
      expect(cleanReviewText('his ~~crush~~ assistant'), 'his crush assistant');
    });

    test('removes header markers with or without a space', () {
      expect(cleanReviewText('# Plot (9/10)\nText'), 'Plot (9/10)\nText');
      expect(cleanReviewText('##__The Music__'), 'The Music');
      expect(cleanReviewText('### Third'), 'Third');
    });

    test('cleans the nested markup seen in real reviews', () {
      expect(cleanReviewText('# __~~~HOPE YOU ENJOY!~~~__'), 'HOPE YOU ENJOY!');
      expect(cleanReviewText('# ____The 236 incident____'), 'The 236 incident');
      expect(cleanReviewText('# ~~~___A Timeless Masterpiece___~~~'), 'A Timeless Masterpiece');
      expect(
        cleanReviewText('# [~~~**Heavy Spoilers ahead!**~~~]()'),
        'Heavy Spoilers ahead!',
      );
      expect(cleanReviewText('[**_(MAJOR SPOILER AHEAD)_ STORY:**]()'), '(MAJOR SPOILER AHEAD) STORY:');
      expect(cleanReviewText('>#####___This review contains spoilers.___'), 'This review contains spoilers.');
    });

    test('removes bold markers that wrap onto the next line, but not across paragraphs', () {
      expect(cleanReviewText('~~~__\nOTHER THINGS I DID NOT LIKE__~~~~~~'), 'OTHER THINGS I DID NOT LIKE');
      expect(cleanReviewText('a__b\n\nc__d'), 'a__b\n\nc__d');
    });

    test('replaces spoilers with the placeholder, also across lines', () {
      expect(cleanReviewText('The hero ~!dies!~ at the end'), 'The hero [spoiler] at the end');
      expect(
        cleanReviewText('Before\n~!line one\nline two!~\nAfter', spoilerPlaceholder: '[Spoiler]'),
        'Before\n[Spoiler]\nAfter',
      );
      expect(cleanReviewText('~!a!~ and ~!b!~'), '[spoiler] and [spoiler]');
    });

    test('hides images and links inside spoilers along with the text', () {
      expect(cleanReviewText('~!img(https://x.co/a.png) [who](https://x.co)!~'), '[spoiler]');
    });

    test('drops horizontal rules', () {
      expect(cleanReviewText('Above\n___\nBelow'), 'Above\n\nBelow');
      expect(cleanReviewText('Above\n---\nBelow'), 'Above\n\nBelow');
      expect(cleanReviewText('Above\n* * *\nBelow'), 'Above\n\nBelow');
    });

    test('removes blockquote markers', () {
      expect(cleanReviewText('> quoted\n>_also italic_'), 'quoted\nalso italic');
    });

    test('turns list markers into bullets', () {
      expect(cleanReviewText('- one\n* two\n  + three'), '• one\n• two\n• three');
    });

    test('decodes common HTML entities', () {
      expect(
        cleanReviewText('Tom &amp; Jerry &quot;quoted&quot; it&#39;s &lt;3&nbsp;ok &#8211; &gt;'),
        'Tom & Jerry "quoted" it\'s <3 ok – >',
      );
    });

    test('does not let a decoded entity become markup', () {
      expect(cleanReviewText('&lt;b&gt;literal&lt;/b&gt;'), '<b>literal</b>');
      expect(cleanReviewText('&gt; not a quote'), '> not a quote');
    });

    test('collapses three or more newlines into a blank line and trims', () {
      expect(cleanReviewText('\n\nOne\n\n\n\nTwo\n \n \n\nThree\n\n'), 'One\n\nTwo\n\nThree');
    });

    test('trims spaces left at the edges of lines', () {
      expect(cleanReviewText('<center>Some text</center> more'), 'Some text\nmore');
    });

    test('keeps plain text untouched', () {
      const text = 'Just a normal paragraph.\n\nAnd another one, with punctuation!';
      expect(cleanReviewText(text), text);
    });
  });
}
