import 'package:anispark/theme/app_motion.dart';
import 'package:anispark/widgets/app_image.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://example.com/cover.jpg';

void main() {
  Widget app(Widget child, {bool reduceMotion = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(body: Center(child: child)),
        ),
      );

  CachedNetworkImage image(WidgetTester tester) => tester.widget(find.byType(CachedNetworkImage));

  Color surface(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(AppImage))).colorScheme.surfaceContainerHighest;

  Finder fillOf(Finder appImage) => find.descendant(of: appImage, matching: find.byType(ColoredBox));

  testWidgets('decodes at the given width and fades in quickly over the surface colour', (tester) async {
    await tester.pumpWidget(app(const AppImage(url: _url, cacheWidth: 160, width: 80, height: 115)));

    expect(image(tester).imageUrl, _url);
    expect(image(tester).memCacheWidth, 160);
    expect(image(tester).fit, BoxFit.cover);
    expect(image(tester).fadeInDuration, AppMotion.short);
    expect(image(tester).fadeOutDuration, Duration.zero, reason: 'the placeholder never lingers over the image');
    expect(image(tester).placeholder, isNotNull, reason: 'without one, the image would pop in instead of fading');

    final fill = fillOf(find.byType(AppImage));
    expect(tester.widget<ColoredBox>(fill).color, surface(tester));
    expect(tester.getSize(fill), const Size(80, 115), reason: 'the box has its size before the image arrives');
  });

  testWidgets('appears at once when motion is reduced', (tester) async {
    await tester.pumpWidget(app(const AppImage(url: _url, cacheWidth: 160), reduceMotion: true));

    expect(image(tester).fadeInDuration, Duration.zero);
  });

  testWidgets('without a url it is the surface colour and its placeholder', (tester) async {
    for (final url in [null, '']) {
      await tester.pumpWidget(app(AppImage(
        url: url,
        cacheWidth: 88,
        width: 44,
        height: 44,
        placeholder: const Icon(Icons.person),
      )));

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(tester.getSize(fillOf(find.byType(AppImage))), const Size(44, 44));
      expect(find.byIcon(Icons.person), findsOneWidget);
    }
  });

  testWidgets('fills the box it is given when it has no size of its own', (tester) async {
    await tester.pumpWidget(app(const SizedBox(width: 120, height: 180, child: AppImage(url: null, cacheWidth: 240))));

    expect(tester.getSize(fillOf(find.byType(AppImage))), const Size(120, 180));
  });

  testWidgets('layered over something else, it paints nothing until it arrives', (tester) async {
    await tester.pumpWidget(app(const SizedBox(
      width: 120,
      height: 180,
      child: AppImage(url: _url, cacheWidth: 240, fill: false),
    )));

    expect(fillOf(find.byType(AppImage)), findsNothing);
    expect(image(tester).placeholder, isNotNull, reason: 'it still fades in');
  });

  testWidgets('passes on how the image is fitted, aligned and tinted', (tester) async {
    await tester.pumpWidget(app(const AppImage(
      url: _url,
      cacheWidth: 400,
      fit: BoxFit.contain,
      alignment: Alignment.topCenter,
      fadeIn: Duration.zero,
      color: Color(0x80FFFFFF),
      colorBlendMode: BlendMode.modulate,
    )));

    expect(image(tester).fit, BoxFit.contain);
    expect(image(tester).alignment, Alignment.topCenter);
    expect(image(tester).fadeInDuration, Duration.zero);
    expect(image(tester).color, const Color(0x80FFFFFF));
    expect(image(tester).colorBlendMode, BlendMode.modulate);
  });
}
