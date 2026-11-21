import 'package:anispark/widgets/profile/profile_tint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _banner = 'https://example.com/banner.png';
const _avatar = 'https://example.com/avatar.png';
const _red = Color(0xFFD2334C);

void main() {
  late List<String> asked;

  setUp(() {
    asked = [];
    ProfileTint.forget();
    ProfileTint.resolver = (url) async {
      asked.add(url);
      return _red;
    };
  });

  tearDown(() => ProfileTint.resolver = (_) async => null);

  test('the tint is a deep shade of the picture\'s colour, dark enough for white text', () {
    final tint = HSLColor.fromColor(profileTintFrom(_red));

    expect(tint.hue, closeTo(HSLColor.fromColor(_red).hue, 1));
    expect(tint.lightness, lessThan(0.2));
    expect(profileTintFrom(_red).computeLuminance(), lessThan(0.05));
  });

  test('a picture is looked at once, then its tint is remembered', () async {
    final first = await ProfileTint.of(_banner);
    final second = await ProfileTint.of(_banner);

    expect(first, profileTintFrom(_red));
    expect(second, first);
    expect(asked, [_banner]);
  });

  Future<void> pumpZone(WidgetTester tester, {String? banner, String? avatar}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light, scaffoldBackgroundColor: const Color(0xFFD8D8DC)),
      home: Scaffold(
        body: CustomScrollView(slivers: [
          ProfileTintZone(
            bannerUrl: banner,
            avatarUrl: avatar,
            slivers: const [
              SliverToBoxAdapter(child: SizedBox(height: 300, child: Text('header'))),
              SliverToBoxAdapter(child: Text('FAVORITE ANIME')),
            ],
          ),
          const SliverToBoxAdapter(child: Text('FAVORITE CHARACTERS')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Color zoneColour(WidgetTester tester) =>
      (tester.widget<DecoratedSliver>(find.byType(DecoratedSliver)).decoration as BoxDecoration).color!;

  testWidgets('the header and what follows it sit on the banner\'s colour, which then melts into the page',
      (tester) async {
    await pumpZone(tester, banner: _banner, avatar: _avatar);

    expect(asked, [_banner], reason: 'the banner, before the picture');
    expect(zoneColour(tester), profileTintFrom(_red));

    final inside = DefaultTextStyle.of(tester.element(find.text('FAVORITE ANIME'))).style.color!;
    expect(inside.computeLuminance(), greaterThan(0.6), reason: 'light text on the dark colour, even in light mode');
    final outside = DefaultTextStyle.of(tester.element(find.text('FAVORITE CHARACTERS'))).style.color;
    expect(outside, isNot(inside), reason: 'the page beyond keeps its own text');

    final fade = tester.widget<DecoratedBox>(find.byKey(const ValueKey('profile-tint-fade')));
    final colours = (fade.decoration as BoxDecoration).gradient!.colors;
    expect(colours.first, profileTintFrom(_red));
    expect(colours.last, const Color(0xFFD8D8DC));
  });

  testWidgets('without a banner the picture gives the colour; without either, a quiet dark', (tester) async {
    await pumpZone(tester, avatar: _avatar);
    expect(asked, [_avatar]);
    expect(zoneColour(tester), profileTintFrom(_red));

    ProfileTint.forget();
    asked.clear();
    await pumpZone(tester);
    expect(asked, isEmpty);
    expect(zoneColour(tester), profileTintFallback);
  });

  testWidgets('when the colour can not be found, the quiet dark stays', (tester) async {
    ProfileTint.resolver = (_) async => null;

    await pumpZone(tester, banner: _banner);

    expect(zoneColour(tester), profileTintFallback);
  });
}
