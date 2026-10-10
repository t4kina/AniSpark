import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/affinity.dart';
import '../../utils/translations.dart';

const _strongColor = Color(0xFF4CAF50);
const _moderateColor = Color(0xFF8BC34A);
const _weakColor = Color(0xFFFFA726);
const _oppositeColor = Color(0xFFEF5350);

/// The color of an affinity [tier]; grey when there is no percentage.
Color affinityTierColor(AffinityTier? tier) => switch (tier) {
      AffinityTier.strong => _strongColor,
      AffinityTier.moderate => _moderateColor,
      AffinityTier.weak => _weakColor,
      AffinityTier.opposite => _oppositeColor,
      null => Colors.grey,
    };

/// The color of the gap (0–100) between two scores of the same title.
Color scoreGapColor(double gap) => switch (gap) {
      <= 10 => _strongColor,
      <= 25 => _weakColor,
      _ => _oppositeColor,
    };

/// Describes [affinity] in words: how similar the tastes are, or why there
/// is no percentage.
String affinityHeadline(Affinity affinity, String lang) => tr(
      switch (affinity.tier) {
        AffinityTier.strong => 'affinity_tier_strong',
        AffinityTier.moderate => 'affinity_tier_moderate',
        AffinityTier.weak => 'affinity_tier_weak',
        AffinityTier.opposite => 'affinity_tier_opposite',
        null => affinity.outcome == AffinityOutcome.uniformScores
            ? 'affinity_uniform_scores'
            : 'affinity_not_enough',
      },
      lang,
    );

/// "N titles in common".
String titlesInCommonText(int count, String lang) => trf(
      count == 1 ? 'affinity_titles_in_common_one' : 'affinity_titles_in_common_many',
      lang,
      {'n': count},
    );

/// The affinity [percent] inside a ring filled up to it (empty when
/// negative), or a dash when there is no percentage. Fills in on first show.
class AffinityRing extends StatelessWidget {
  const AffinityRing({super.key, required this.percent, required this.color, this.size = 52});

  final int? percent;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final percent = this.percent;
    final track = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    final numberStyle = TextStyle(
      fontSize: size * 0.3,
      fontWeight: FontWeight.w800,
      color: percent == null ? Colors.grey : color,
      height: 1,
    );
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: (percent ?? 0).clamp(0, 100) / 100),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, fill, child) => CustomPaint(
          painter: _RingPainter(fill: fill, color: color, track: track, strokeWidth: size * 0.09),
          child: child,
        ),
        child: Padding(
          padding: EdgeInsets.all(size * 0.16),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(
              percent == null
                  ? TextSpan(text: '–', style: numberStyle)
                  : TextSpan(
                      text: '$percent',
                      style: numberStyle,
                      children: [
                        TextSpan(
                          text: '%',
                          style: numberStyle.copyWith(fontSize: size * 0.17, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fill,
    required this.color,
    required this.track,
    required this.strokeWidth,
  });

  final double fill;
  final Color color;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).deflate(strokeWidth / 2);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = track;
    canvas.drawArc(bounds, 0, math.pi * 2, false, trackPaint);
    if (fill <= 0) return;
    final fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(bounds, -math.pi / 2, math.pi * 2 * fill, false, fillPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fill != fill || old.color != color || old.track != track || old.strokeWidth != strokeWidth;
}
