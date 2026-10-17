import 'package:anispark/widgets/motion/rounded_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _small = ValueKey('list cover');
const _big = ValueKey('page cover');

/// A list page with a 6px-rounded cover that opens a page with the same
/// cover, 12px-rounded.
Widget _app({bool reduceMotion = false}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: 130,
                        height: 190,
                        child: RoundedHero(
                          tag: 'cover',
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          child: ColoredBox(key: _big, color: Colors.blue),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: const SizedBox(
                width: 50,
                height: 70,
                child: RoundedHero(
                  tag: 'cover',
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  child: ColoredBox(key: _small, color: Colors.red),
                ),
              ),
            ),
          ),
        ),
      ),
    );

/// The radius of the nearest clip around [finder].
double _radiusAround(WidgetTester tester, Finder finder) {
  final clip = tester.widget<ClipRRect>(find.ancestor(of: finder, matching: find.byType(ClipRRect)).first);
  return (clip.borderRadius as BorderRadius).topLeft.x;
}

void main() {
  testWidgets('is only a clip without a tag', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: RoundedHero(tag: null, borderRadius: BorderRadius.all(Radius.circular(10)), child: ColoredBox(key: _small, color: Colors.red)),
    ));

    expect(find.byType(Hero), findsNothing);
    expect(_radiusAround(tester, find.byKey(_small)), 10);
  });

  testWidgets('does not fly when animations are reduced', (tester) async {
    await tester.pumpWidget(_app(reduceMotion: true));

    expect(find.byType(Hero), findsNothing);
    expect(_radiusAround(tester, find.byKey(_small)), 6);
  });

  testWidgets('flies the list cover over the loading page cover, morphing the corners', (tester) async {
    await tester.pumpWidget(_app());
    expect(find.byType(Hero), findsOneWidget);

    await tester.tap(find.byKey(_small));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // In flight: the list's cover on top, the page's cover underneath.
    final stack = tester.widget<Stack>(
      find.ancestor(of: find.byKey(_small), matching: find.byType(Stack)).first,
    );
    expect(stack.children.map((child) => child.key), [_big, _small]);
    final radius = _radiusAround(tester, find.byKey(_small));
    expect(radius, greaterThan(6));
    expect(radius, lessThan(12));

    await tester.pumpAndSettle();

    expect(find.byKey(_small), findsNothing, reason: 'the list page is covered');
    expect(_radiusAround(tester, find.byKey(_big)), 12);
  });

  testWidgets('flies back fading the page cover into the list cover, morphing the corners', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byKey(_small));
    await tester.pumpAndSettle();

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final stack = tester.widget<Stack>(
      find.ancestor(of: find.byKey(_small), matching: find.byType(Stack)).first,
    );
    expect(stack.children.first.key, _small, reason: 'the list cover is underneath');
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: find.byKey(_big), matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, greaterThan(0));
    expect(fade.opacity.value, lessThan(1));
    final radius = _radiusAround(tester, find.byKey(_small));
    expect(radius, greaterThan(6));
    expect(radius, lessThan(12));

    await tester.pumpAndSettle();

    expect(find.byKey(_big), findsNothing);
    expect(_radiusAround(tester, find.byKey(_small)), 6);
  });
}
