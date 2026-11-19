import 'package:anispark/widgets/blurred_backdrop.dart';
import 'package:anispark/widgets/profile/avatar_viewer.dart';
import 'package:anispark/widgets/profile/profile_card.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _avatar = 'https://img.example/avatar.jpg';
const _banner = 'https://img.example/banner.jpg';

const _animeStats = {
  'count': 321,
  'meanScore': 78.4,
  'episodesWatched': 4567,
  'minutesWatched': 17856,
  'genres': [
    {'genre': 'Drama', 'count': 3},
    {'genre': 'Action', 'count': 9},
  ],
};
const _mangaStats = {'count': 12, 'meanScore': 0, 'chaptersRead': 890, 'volumesRead': 34};

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    String? banner,
    String? avatar = _avatar,
    String? scoreFormat,
    ValueChanged<String>? onCountTap,
    double width = 800,
  }) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProfileCard(
            name: 'Faye',
            lang: 'en',
            avatarUrl: avatar,
            bannerUrl: banner,
            animeStats: _animeStats,
            mangaStats: _mangaStats,
            scoreFormat: scoreFormat,
            onCountTap: onCountTap,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Iterable<String> networkImages(WidgetTester tester) =>
      tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)).map((image) => image.imageUrl);

  testWidgets('the banner dissolves into the page over a long, gentle stretch below everything', (tester) async {
    await pumpCard(tester);

    final page = Theme.of(tester.element(find.byType(ProfileCard))).scaffoldBackgroundColor;
    final fadeFinder = find.byWidgetPredicate((widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        ((widget.decoration as BoxDecoration).gradient?.colors.last == page));
    expect(fadeFinder, findsOneWidget);
    final fade = tester.getRect(fadeFinder);
    final card = tester.getRect(find.byType(ProfileCard));
    expect(fade.bottom, card.bottom);
    expect(fade.height, greaterThanOrEqualTo(100), reason: 'long, not a line');

    final alphas = (tester.widget<DecoratedBox>(fadeFinder).decoration as BoxDecoration).gradient!.colors.map((c) => c.a).toList();
    expect(alphas.first, 0);
    expect(alphas.last, 1);
    expect(alphas.length, greaterThanOrEqualTo(8));
    expect(alphas[1], lessThan(0.05), reason: 'starts softly');
    expect(alphas[alphas.length - 2], greaterThan(0.95), reason: 'ends softly, with no edge');

    final textBottoms = [
      for (final text in find.descendant(of: find.byType(ProfileCard), matching: find.byType(Text)).evaluate())
        tester.getRect(find.byElementPredicate((element) => element == text)).bottom,
    ];
    expect(textBottoms.reduce((a, b) => a > b ? a : b), lessThan(fade.top + fade.height * 0.4),
        reason: 'what is written stays over the banner, not over the fade');
  });

  testWidgets('sits on the person\'s banner when they have one', (tester) async {
    await pumpCard(tester, banner: _banner);

    expect(networkImages(tester), [_banner]);
    expect(find.byType(BlurredBackdrop), findsNothing);
  });

  testWidgets('the banner runs edge to edge from the top, not as a card', (tester) async {
    await pumpCard(tester, banner: _banner);

    final banner = tester.getRect(find.byType(CachedNetworkImage));
    expect(banner.left, 0);
    expect(banner.right, 800);
    expect(banner.top, 0);
    expect(find.ancestor(of: find.byType(CachedNetworkImage), matching: find.byType(ClipRRect)), findsNothing,
        reason: 'no rounded card corners');
  });

  testWidgets('without a banner, sits on their avatar blurred into colour', (tester) async {
    await pumpCard(tester);

    expect(tester.widget<BlurredBackdrop>(find.byType(BlurredBackdrop)).url, _avatar);
    expect(networkImages(tester), isNot(contains(_banner)));
  });

  testWidgets('without banner or avatar, falls back to the accent', (tester) async {
    await pumpCard(tester, avatar: null);

    expect(find.byType(BlurredBackdrop), findsNothing);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text('Faye'), findsOneWidget);
  });

  testWidgets('names the genre they have the most of', (tester) async {
    await pumpCard(tester);

    expect(find.text('Action fan'), findsOneWidget);
  });

  testWidgets('shows the anime stats, and the manga ones once toggled', (tester) async {
    await pumpCard(tester);

    for (final value in ['7.8', '4567', '12.4']) {
      expect(find.text(value), findsOneWidget, reason: value);
    }

    await tester.tap(find.text('Manga'));
    await tester.pumpAndSettle();

    for (final value in ['890', '34', '—']) {
      expect(find.text(value), findsOneWidget, reason: value);
    }
    expect(find.text('4567'), findsNothing);
  });

  testWidgets('shows the mean score in the viewer\'s score format', (tester) async {
    await pumpCard(tester, scoreFormat: 'POINT_100');

    expect(find.text('78'), findsOneWidget);
    expect(find.text('7.8'), findsNothing);
  });

  testWidgets('every stat label stays on one line, even on a narrow phone', (tester) async {
    await pumpCard(tester, width: 320);

    final labels = ['Mean score', 'Episodes', 'Days'];
    final heights = [for (final label in labels) tester.getSize(find.text(label)).height];
    expect(heights.toSet(), hasLength(1), reason: 'a wrapped label is taller: $heights');
    final tops = [for (final label in labels) tester.getTopLeft(find.text(label)).dy];
    expect(tops.toSet(), hasLength(1), reason: 'the labels line up: $tops');
  });

  testWidgets('the anime and manga counts open their lists', (tester) async {
    final tapped = <String>[];
    await pumpCard(tester, onCountTap: tapped.add);

    await tester.tap(find.text('12 manga'));
    await tester.tap(find.text('321 anime'));

    expect(tapped, ['MANGA', 'ANIME']);
  });

  testWidgets('a tap on the avatar opens it large, and a tap closes it', (tester) async {
    await pumpCard(tester);

    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();

    expect(find.byType(AvatarViewer), findsOneWidget);
    final image = tester.widget<CachedNetworkImage>(
      find.descendant(of: find.byType(AvatarViewer), matching: find.byType(CachedNetworkImage)),
    );
    expect(image.imageUrl, _avatar);
    expect(
      tester.getSize(find.descendant(of: find.byType(AvatarViewer), matching: find.byType(CachedNetworkImage))).width,
      greaterThan(ProfileCard.avatarSize * 4),
      reason: 'as large as the screen allows',
    );

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(AvatarViewer), findsNothing);
  });

  testWidgets('without a picture there is nothing to open', (tester) async {
    await pumpCard(tester, avatar: null);

    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();
    expect(find.byType(AvatarViewer), findsNothing);
  });
}
