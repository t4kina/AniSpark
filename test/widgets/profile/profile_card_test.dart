import 'package:anispark/widgets/blurred_backdrop.dart';
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

  testWidgets('sits on the person\'s banner when they have one', (tester) async {
    await pumpCard(tester, banner: _banner);

    expect(networkImages(tester), [_banner]);
    expect(find.byType(BlurredBackdrop), findsNothing);
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
}
