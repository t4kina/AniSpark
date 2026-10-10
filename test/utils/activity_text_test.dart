import 'package:anispark/utils/activity_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cleanActivityText', () {
    test('returns an empty string for null or empty text', () {
      expect(cleanActivityText(null), '');
      expect(cleanActivityText(''), '');
    });

    test('leaves plain text untouched', () {
      expect(cleanActivityText('Just finished Frieren, what a ride'),
          'Just finished Frieren, what a ride');
    });

    test('drops image and video embeds in every size form', () {
      const text = 'Look img220(https://i.imgur.com/a.png) and '
          'img(https://x.y/b.gif) or IMG50%(https://x.y/c.jpg) '
          'webm(https://x.y/d.webm) youtube(dQw4w9WgXcQ) done';

      expect(cleanActivityText(text), 'Look and or done');
    });

    test('hides spoilers behind the default label', () {
      expect(cleanActivityText('Wow ~!he dies!~ at the end'),
          'Wow [spoiler] at the end');
    });

    test('uses the given spoiler label and hides multi-line spoilers with '
        'their images', () {
      const text = 'Before ~!line one\nimg220(https://x.y/p.png)\nline two!~ after';

      expect(cleanActivityText(text, spoilerLabel: '[spoiler oculto]'),
          'Before [spoiler oculto] after');
    });

    test('never rewrites the spoiler label with later rules', () {
      expect(cleanActivityText('~!x!~(lol)'), '[spoiler](lol)');
      expect(cleanActivityText('~!x!~', spoilerLabel: '__hidden__'), '__hidden__');
    });

    test('hides every spoiler separately', () {
      expect(cleanActivityText('~!a!~ and ~!b!~'), '[spoiler] and [spoiler]');
    });

    test('turns <br> variants into line breaks', () {
      expect(cleanActivityText('one<br>two<br/>three<BR />four'),
          'one\ntwo\nthree\nfour');
    });

    test('keeps the text of markdown and HTML links', () {
      expect(cleanActivityText('See [my list](https://anilist.co/user/x)'),
          'See my list');
      expect(cleanActivityText('See <a href="https://anilist.co">AniList</a>!'),
          'See AniList!');
    });

    test('keeps bare URLs as they are', () {
      expect(cleanActivityText('https://anilist.co/anime/1'),
          'https://anilist.co/anime/1');
    });

    test('drops markdown images entirely', () {
      expect(cleanActivityText('Cover: ![alt](https://x.y/c.png)'), 'Cover:');
    });

    test('removes bold, italic, strikethrough and centering marks', () {
      expect(cleanActivityText('__bold__ **strong** _it_ *em* ~~old~~ ~~~mid~~~'),
          'bold strong it em old mid');
    });

    test('does not treat underscores inside words as italics', () {
      expect(cleanActivityText('my_user_name and snake_case'),
          'my_user_name and snake_case');
      expect(cleanActivityText('2 * 3 * 4'), '2 * 3 * 4');
    });

    test('strips known HTML tags but keeps comparisons and hearts', () {
      expect(cleanActivityText('<center><b>Hi</b></center> a < b > c <3'),
          'Hi a < b > c <3');
    });

    test('strips headings, quotes, rules and code marks', () {
      const text = '# Title\n> quoted\n---\n```\ncode\n```\nuse `x`';

      expect(cleanActivityText(text), 'Title\nquoted\n\ncode\n\nuse x');
    });

    test('decodes HTML entities', () {
      expect(cleanActivityText('Tom &amp; Jerry &quot;hi&quot; &#39;yo&#039; '
              '&lt;3 &#x2764; &amp;lt;'),
          'Tom & Jerry "hi" \'yo\' <3 ❤ &lt;');
    });

    test('collapses blank lines and extra spaces and trims', () {
      expect(cleanActivityText('  a   b  \n\n\n\n c  '), 'a b\n\nc');
    });

    test('a post made only of an image becomes empty', () {
      expect(cleanActivityText('img220(https://x.y/a.png)'), '');
    });
  });

  group('relativeTime', () {
    final now = DateTime(2026, 10, 10, 12);
    int secondsAgo(Duration d) => now.subtract(d).millisecondsSinceEpoch ~/ 1000;

    test('shows minutes under an hour', () {
      expect(relativeTime(secondsAgo(const Duration(minutes: 5)), 'English', now: now),
          '5m ago');
    });

    test('shows hours under a day', () {
      expect(relativeTime(secondsAgo(const Duration(hours: 3)), 'English', now: now),
          '3h ago');
    });

    test('shows days after that', () {
      expect(relativeTime(secondsAgo(const Duration(days: 2, hours: 1)), 'English', now: now),
          '2d ago');
    });

    test('reads a timestamp in the future as zero minutes ago', () {
      expect(relativeTime(secondsAgo(const Duration(minutes: -3)), 'English', now: now),
          '0m ago');
    });
  });
}
