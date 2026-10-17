import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/utils/translations.dart';
import 'package:anispark/widgets/genre_filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

String _en(String key) => tr(key, 'English');

void main() {
  Future<void> openSheet(WidgetTester tester, {Set<String> selected = const {}, required void Function(Set<String>) onApply}) async {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => GenreFilterSheet(selected: selected, onApply: onApply),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  test('genre labels are translated, and unknown genres are shown as is', () {
    expect(genreLabel('Sci-Fi', 'Spanish'), tr('search_genre_sci_fi', 'Spanish'));
    expect(genreLabel('Hentai', 'Spanish'), 'Hentai');
    expect(genreLabelKeys, hasLength(18));
  });

  testWidgets('applies the ticked genres when closed', (tester) async {
    Set<String>? applied;
    await openSheet(tester, selected: {'Drama'}, onApply: (genres) => applied = genres);

    await tester.tap(find.text(_en('search_genre_action')));
    await tester.tap(find.text(_en('search_genre_drama')));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(applied, {'Action'});
    expect(find.byType(GenreFilterSheet), findsNothing);
  });

  testWidgets('reset unticks every genre', (tester) async {
    Set<String>? applied;
    await openSheet(tester, selected: {'Drama', 'Horror'}, onApply: (genres) => applied = genres);

    await tester.tap(find.text(_en('search_reset')));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(applied, isEmpty);
  });

  testWidgets('chips have a tap area of at least 44 px', (tester) async {
    await openSheet(tester, onApply: (_) {});

    final chip = find.widgetWithText(FilterOptionChip, _en('search_genre_action'));
    expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
  });
}
