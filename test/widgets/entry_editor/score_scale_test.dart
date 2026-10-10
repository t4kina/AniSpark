import 'package:anispark/utils/score_utils.dart';
import 'package:anispark/widgets/entry_editor/score_scale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('picks the scale of each AniList score format, defaulting to decimals', () {
    expect(ScoreScale.of('POINT_100').kind, ScoreKind.number);
    expect(ScoreScale.of('POINT_100').max, 100);
    expect(ScoreScale.of('POINT_10').max, 10);
    expect(ScoreScale.of('POINT_10').decimals, 0);
    expect(ScoreScale.of('POINT_10_DECIMAL').decimals, 1);
    expect(ScoreScale.of('POINT_5').kind, ScoreKind.stars);
    expect(ScoreScale.of('POINT_3').kind, ScoreKind.faces);
    expect(ScoreScale.of(null), ScoreScale.of('POINT_10_DECIMAL'));
    expect(ScoreScale.of('SOMETHING_NEW'), ScoreScale.of('POINT_10_DECIMAL'));
  });

  test('100-point scores are whole raw points', () {
    final scale = ScoreScale.of('POINT_100');

    expect(scale.toUnits(7.5), 75);
    expect(toRawScore(scale.fromUnits(73)), 73);
    expect(scale.step, 1);
  });

  test('decimal scores keep one decimal and step by halves', () {
    final scale = ScoreScale.of('POINT_10_DECIMAL');

    expect(scale.toUnits(7.3), 7.3);
    expect(scale.fromUnits(8.4), 8.4);
    expect(toRawScore(scale.fromUnits(8.4)), 84);
    expect(scale.step, 0.5);
  });

  test('10-point scores are whole numbers', () {
    final scale = ScoreScale.of('POINT_10');

    expect(scale.toUnits(7.0), 7);
    expect(toRawScore(scale.fromUnits(9)), 90);
  });

  test('stars are 20 raw points each and read like formatScore', () {
    final scale = ScoreScale.of('POINT_5');

    expect(scale.toUnits(6.0), 3);
    expect(scale.toUnits(0), 0);
    expect(toRawScore(scale.fromUnits(4)), 80);
    expect(scale.max, 5);
  });

  test('faces are written as the values AniList stores for them', () {
    final scale = ScoreScale.of('POINT_3');

    expect([for (var face = 0; face <= 3; face++) toRawScore(scale.fromUnits(face))], [0, 35, 60, 85]);
    expect(scale.toUnits(3.5), 1);
    expect(scale.toUnits(6.0), 2);
    expect(scale.toUnits(8.5), 3);
    expect(scale.toUnits(0), 0);
  });

  test('every unit round-trips for every format', () {
    for (final format in ['POINT_100', 'POINT_10_DECIMAL', 'POINT_10', 'POINT_5', 'POINT_3']) {
      final scale = ScoreScale.of(format);
      final stepsPerUnit = scale.decimals == 1 ? 10 : 1;
      for (var i = 0; i <= scale.max * stepsPerUnit; i++) {
        final units = i / stepsPerUnit;
        expect(scale.toUnits(scale.fromUnits(units)), units, reason: '$format $units');
      }
    }
  });
}
