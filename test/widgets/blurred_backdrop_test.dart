import 'package:anispark/widgets/blurred_backdrop.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('blurs a small decode of the image behind a soft veil', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(width: 400, height: 200, child: BlurredBackdrop(url: 'https://img.example/cover.jpg')),
    ));

    final image = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(image.imageUrl, 'https://img.example/cover.jpg');
    expect(image.memCacheWidth, BlurredBackdrop.decodeWidth);
    expect(find.ancestor(of: find.byType(CachedNetworkImage), matching: find.byType(ImageFiltered)), findsOneWidget);
  });
}
