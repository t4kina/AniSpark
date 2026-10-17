import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/widgets/anime_card.dart';
import 'package:anispark/widgets/motion/rounded_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_auth_service.dart';

Map<String, dynamic> _media(int id, String title, {int? score}) => {
      'id': id,
      'title': {'english': title},
      'coverImage': {'large': null},
      'averageScore': ?score,
    };

void main() {
  testWidgets('covers line up whatever the title length or a missing score', (tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(create: (_) => FakeAuthService()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final media in [
                _media(1, 'ONE PIECE', score: 87),
                _media(2, 'The Laid-Off Cheat-Granting Mage Enjoys a Leisurely Life', score: 73),
                _media(3, 'Unscored'),
              ])
                SizedBox(width: 110, height: 220, child: AnimeCard(animeData: media)),
            ],
          ),
        ),
      ),
    ));

    final covers = tester.widgetList(find.byType(RoundedHero)).map((hero) => tester.getSize(find.byWidget(hero))).toList();
    expect(covers, hasLength(3));
    expect(covers.map((size) => size.height).toSet(), hasLength(1), reason: 'every cover is the same height');
  });
}
