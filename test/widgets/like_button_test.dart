import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/widgets/motion/like_burst.dart';
import 'package:anispark/widgets/motion/pop_on_change.dart';
import 'package:anispark/widgets/social/social_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// A like button that toggles itself, like the feed does optimistically.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _liked = false;
  int _count = 3;

  @override
  Widget build(BuildContext context) => LikeButton(
        isLiked: _liked,
        count: _count,
        onPressed: () => setState(() {
          _liked = !_liked;
          _count += _liked ? 1 : -1;
        }),
      );
}

double _heartScale(WidgetTester tester) => tester
    .widget<ScaleTransition>(
      find.descendant(of: find.byType(PopOnChange), matching: find.byType(ScaleTransition)),
    )
    .scale
    .value;

/// The painter of the burst around the heart.
final _burst = find.descendant(of: find.byType(LikeBurst), matching: find.byType(CustomPaint)).first;

void main() {
  late List<String> haptics;

  setUp(() => haptics = []);

  Future<void> pumpHost(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: const MaterialApp(home: Scaffold(body: Center(child: _Host()))),
    ));
  }

  testWidgets('liking pops the heart, taps lightly and rolls the count up', (tester) async {
    await pumpHost(tester);
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byType(LikeButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(_heartScale(tester), greaterThan(1), reason: 'the heart is mid-pop');
    expect(_burst, paints..circle(style: PaintingStyle.stroke)..circle(style: PaintingStyle.fill),
        reason: 'a ring opens around it and sparks fly off');
    expect(find.text('4'), findsOneWidget, reason: 'the new count is rolling in');
    expect(haptics, ['HapticFeedbackType.lightImpact']);

    await tester.pumpAndSettle();
    expect(_heartScale(tester), 1);
    expect(_burst, isNot(paints..circle()), reason: 'the burst has gone');
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsNothing, reason: 'the old count rolled away');
  });

  testWidgets('unliking rolls the count back without a pop or a haptic', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.byType(LikeButton));
    await tester.pumpAndSettle();
    haptics.clear();

    await tester.tap(find.byType(LikeButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(_heartScale(tester), 1);
    expect(_burst, isNot(paints..circle()), reason: 'no burst for taking a like back');
    expect(haptics, isEmpty);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsNothing);
  });

  testWidgets('the burst moves nothing around the heart', (tester) async {
    await pumpHost(tester);
    final before = tester.getRect(find.byType(LikeButton));
    final heart = tester.getRect(find.byType(Icon));

    await tester.tap(find.byType(LikeButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(tester.getRect(find.byType(LikeButton)), before);
    expect(tester.getRect(find.byType(LikeBurst)).size, heart.size, reason: 'it takes no room of its own');
    await tester.pumpAndSettle();
  });

  testWidgets('there is no burst when motion is reduced', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: Center(child: _Host())),
        ),
      ),
    ));

    await tester.tap(find.byType(LikeButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(_burst, isNot(paints..circle()));
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
