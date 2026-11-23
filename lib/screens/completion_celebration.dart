import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../theme/app_layout.dart';
import '../theme/app_motion.dart';
import '../theme/app_text.dart';
import '../utils/haptics.dart';
import '../utils/translations.dart' show tr, trf;
import '../widgets/app_button.dart';
import '../widgets/app_image.dart';
import '../widgets/app_sheet.dart';
import '../widgets/blurred_backdrop.dart';
import '../widgets/motion/pressable.dart';
import '../widgets/motion/staggered_entrance.dart';

/// Opens the [CompletionCelebration] of a series or manga over the page,
/// and resolves once it is closed (completed or not).
Future<void> showCompletionCelebration(
  BuildContext context, {
  required String title,
  required String? coverUrl,
  required double? averageScore,
  required double initialScore,
  required bool isManga,
  required Future<bool> Function(double score) onComplete,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: AppMotion.of(context, AppMotion.long),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: CurvedAnimation(parent: animation, curve: AppMotion.enter), child: child),
    pageBuilder: (_, _, _) => CompletionCelebration(
      title: title,
      coverUrl: coverUrl,
      averageScore: averageScore,
      initialScore: initialScore,
      isManga: isManga,
      onComplete: onComplete,
    ),
  );
}

/// The moment a series is finished: its cover pops in at the centre, a
/// tick lands on its corner and one burst of confetti in the accent colour
/// leaves from behind it; under it, the final score and the button that
/// marks it completed.
///
/// [onComplete] saves the completion with the chosen score and resolves to
/// whether it went through. The page closes when it did and stays, saying
/// so, when it didn't.
class CompletionCelebration extends StatefulWidget {
  const CompletionCelebration({
    super.key,
    required this.title,
    required this.coverUrl,
    required this.averageScore,
    required this.initialScore,
    required this.isManga,
    required this.onComplete,
  });

  final String title;
  final String? coverUrl;

  /// AniList's average, out of 100.
  final double? averageScore;
  final double initialScore;
  final bool isManga;
  final Future<bool> Function(double score) onComplete;

  static const coverSize = Size(176, 250);

  @override
  State<CompletionCelebration> createState() => _CompletionCelebrationState();
}

class _CompletionCelebrationState extends State<CompletionCelebration> with SingleTickerProviderStateMixin {
  static const _coverRadius = BorderRadius.all(Radius.circular(16));
  static const _badgeSize = 44.0;

  // The cover pops first; the tick lands on it as it settles.
  static const _coverPop = Interval(0, 0.6, curve: Curves.easeOutBack);
  static const _coverFade = Interval(0, 0.25);
  static const _badgePop = Interval(0.5, 1, curve: Curves.easeOutBack);

  late final AnimationController _entrance =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  late final Animation<double> _coverScale =
      Tween(begin: 0.86, end: 1.0).animate(CurvedAnimation(parent: _entrance, curve: _coverPop));
  late final Animation<double> _coverOpacity = CurvedAnimation(parent: _entrance, curve: _coverFade);
  late final Animation<double> _badgeScale = CurvedAnimation(parent: _entrance, curve: _badgePop);
  // One short burst: a few pieces, not a shower.
  final _confetti = ConfettiController(duration: const Duration(milliseconds: 250));
  bool _started = false;
  late double _score = widget.initialScore;
  bool _completing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reduced(context)) {
      _entrance.value = 1;
      return;
    }
    _entrance.forward();
    _confetti.play();
    successHaptic();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    setState(() => _completing = true);
    final ok = await widget.onComplete(_score);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      return;
    }
    // Stay open so the change can be retried instead of lost.
    setState(() => _completing = false);
    final lang = context.read<SettingsProvider>().language;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('save_failed', lang))));
  }

  void _openScorePicker() {
    showAppSheet<void>(
      context: context,
      builder: (_) => _ScorePickerSheet(
        initialScore: _score,
        onUpdate: (score) {
          setState(() => _score = score);
          Navigator.pop(context);
        },
      ),
    );
  }

  /// The accent, a lighter accent and white: confetti that belongs to the
  /// app instead of a party-shop mix.
  List<Color> _confettiColors(Color accent) => [accent, Color.lerp(accent, Colors.white, 0.45)!, Colors.white];

  Widget _stage(Color accent) {
    final coverUrl = widget.coverUrl;
    final badge = ScaleTransition(
      scale: _badgeScale,
      child: Container(
        width: _badgeSize,
        height: _badgeSize,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black, width: 3),
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 26),
      ),
    );
    return SizedBox.fromSize(
      size: CompletionCelebration.coverSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Behind the cover, so the pieces come out from under its edges.
          ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.5,
            numberOfParticles: 8,
            minBlastForce: 6,
            maxBlastForce: 22,
            gravity: 0.22,
            minimumSize: const Size(6, 4),
            maximumSize: const Size(11, 7),
            colors: _confettiColors(accent),
          ),
          if (coverUrl == null)
            badge
          else ...[
            Positioned.fill(
              child: FadeTransition(
                opacity: _coverOpacity,
                child: ScaleTransition(
                  scale: _coverScale,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: _coverRadius,
                      // The cover glows in the accent.
                      boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 48, spreadRadius: 2)],
                    ),
                    child: ClipRRect(
                      borderRadius: _coverRadius,
                      child: AppImage(url: coverUrl, cacheWidth: 360),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(right: -_badgeSize / 3, bottom: -_badgeSize / 3, child: badge),
          ],
        ],
      ),
    );
  }

  Widget _rating(String lang) {
    final averageScore = widget.averageScore;
    return Column(
      children: [
        Text(
          tr(widget.isManga ? 'list_final_rating_manga' : 'list_final_rating_series', lang),
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: Colors.white.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: AppSpace.md),
        Pressable(
          onTap: _openScorePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Text(
              _score > 0 ? _score.toStringAsFixed(1) : tr('list_not_scored', lang),
              style: AppText.headline.copyWith(color: Colors.white),
            ),
          ),
        ),
        if (averageScore != null) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFC107)),
              const SizedBox(width: AppSpace.xs),
              Text(
                trf('list_average_rating', lang, {'score': (averageScore / 10).toStringAsFixed(1)}),
                style: AppText.micro.copyWith(letterSpacing: 0.5, color: Colors.white.withValues(alpha: 0.4)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final accent = Theme.of(context).colorScheme.primary;
    final coverUrl = widget.coverUrl;

    // Back is blocked while saving so the list can't be swiped mid-request.
    return PopScope(
      canPop: !_completing,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (coverUrl != null) ...[
              Positioned.fill(child: BlurredBackdrop(url: coverUrl, decodeWidth: 160)),
              const Positioned.fill(child: ColoredBox(color: Color(0x9E000000))),
            ],
            SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xs, right: AppSpace.xs),
                      child: IconButton(
                        tooltip: tr('close', lang),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 22),
                      ),
                    ),
                  ),
                  const Spacer(),
                  StaggeredEntrance(
                    index: 1,
                    child: Text(
                      tr('list_congrats_finished', lang),
                      textAlign: TextAlign.center,
                      style: AppText.subhead.copyWith(color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  _stage(accent),
                  const SizedBox(height: 28),
                  StaggeredEntrance(
                    index: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxl),
                      child: Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.title.copyWith(color: Colors.white, height: 1.2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  StaggeredEntrance(index: 3, child: _rating(lang)),
                  const Spacer(),
                  StaggeredEntrance(
                    index: 4,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, 20),
                      child: AppButton(
                        label: tr(widget.isManga ? 'list_complete_manga' : 'list_complete_series', lang),
                        large: true,
                        expand: true,
                        busy: _completing,
                        onPressed: _complete,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScorePickerSheet extends StatefulWidget {
  final double initialScore;
  final void Function(double) onUpdate;

  const _ScorePickerSheet({required this.initialScore, required this.onUpdate});

  @override
  State<_ScorePickerSheet> createState() => _ScorePickerSheetState();
}

class _ScorePickerSheetState extends State<_ScorePickerSheet> {
  late double _score;
  late final TextEditingController _ctrl;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _score = widget.initialScore;
    _ctrl = TextEditingController(text: _fmt(_score));
    _focusNode.addListener(_onFocusLost);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusLost);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(double v) => v == 0 ? '0' : v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

  void _onFocusLost() {
    if (!_focusNode.hasFocus) _applyText();
  }

  void _applyText() {
    final parsed = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    final clamped = (parsed ?? _score).clamp(0.0, 10.0);
    setState(() => _score = clamped);
    _ctrl.text = _fmt(clamped);
  }

  void _adjust(double delta) {
    _focusNode.unfocus();
    final next = (_score + delta).clamp(0.0, 10.0);
    setState(() => _score = next);
    _ctrl.text = _fmt(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lang = context.watch<SettingsProvider>().language;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('list_score', lang),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Minus
              Pressable(
                onTap: () => _adjust(-0.5),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.remove, size: 26, color: cs.onSurface),
                ),
              ),
              const SizedBox(width: 16),
              // Score — editable field
              Container(
                width: 120,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focusNode,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 18),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _applyText(),
                  onEditingComplete: _applyText,
                ),
              ),
              const SizedBox(width: 16),
              // Plus
              Pressable(
                onTap: () => _adjust(0.5),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add, size: 26, color: cs.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          AppButton(
            label: tr('list_update', lang),
            large: true,
            expand: true,
            onPressed: () {
              _applyText();
              widget.onUpdate(_score);
            },
          ),
        ],
      ),
    );
  }
}
