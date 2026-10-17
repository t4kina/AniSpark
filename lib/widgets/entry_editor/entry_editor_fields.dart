import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_motion.dart';
import '../../utils/translations.dart';
import '../motion/animated_count.dart';
import '../motion/pop_on_change.dart';
import '../../utils/fuzzy_date.dart' show formatFuzzyDate;
import 'entry_draft.dart';
import 'score_scale.dart';

const _tapTarget = 44.0;
const _fieldRadius = 10.0;

// Counts without a known total (episodes of an airing show, rewatches…)
// still need an upper bound for typed values.
const _noTotalMax = 99999;

/// The small grey caption above each editor field.
class EditorLabel extends StatelessWidget {
  const EditorLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );
}

/// Stands in for a field whose current value the editor doesn't know (e.g.
/// it opened from data cached before the field was fetched), so it can't
/// be edited or overwritten by mistake.
class UnknownValue extends StatelessWidget {
  const UnknownValue({super.key});

  @override
  Widget build(BuildContext context) => Container(
        height: _tapTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(_fieldRadius),
        ),
        child: const Text('—', style: TextStyle(color: Colors.grey)),
      );
}

/// A number with − and + buttons that can also be typed. Values are kept
/// between 0 and [max] (when known); [decimals] is 0 or 1. A value changed
/// from outside the field (the buttons, a status change) rolls in like an
/// [AnimatedCount]; typed values just appear.
class NumberStepper extends StatefulWidget {
  const NumberStepper({
    super.key,
    required this.value,
    required this.onChanged,
    required this.lang,
    this.max,
    this.step = 1,
    this.decimals = 0,
    this.suffix,
  });

  final num value;
  final ValueChanged<num> onChanged;
  final String lang;
  final num? max;
  final num step;
  final int decimals;
  final String? suffix;

  @override
  State<NumberStepper> createState() => _NumberStepperState();
}

class _NumberStepperState extends State<NumberStepper> {
  static const _valueStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.bold);

  // The end of a single-line field's text keeps room for the caret (its
  // 2px width plus a 1px gap), so centred text sits half of this left of
  // the middle; the rolling copy is laid out the same way.
  static const _caretRoom = 3.0;

  late final TextEditingController _controller = TextEditingController(text: _format(widget.value));
  final _focusNode = FocusNode();

  // While a new value rolls in, the field's own text is hidden and a twin
  // decorator draws the rolling number in exactly the same place.
  bool _rolling = false;
  Timer? _rollEnd;

  num get _max => widget.max ?? _noTotalMax;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(NumberStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An empty field stands for 0 while the user is typing.
    if ((_parse(_controller.text) ?? 0) != widget.value) _setText(_format(widget.value));
    // Typing already shows the new value; anything else rolls it in.
    if (widget.value != oldWidget.value && !_focusNode.hasFocus) _roll();
  }

  @override
  void dispose() {
    _rollEnd?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Shows the rolling copy for as long as [AnimatedCount] rolls (called
  /// from [didUpdateWidget], so the build that follows picks it up).
  void _roll() {
    final duration = AppMotion.of(context, AppMotion.short);
    if (duration == Duration.zero) return;
    _rollEnd?.cancel();
    _rolling = true;
    _rollEnd = Timer(duration, () {
      if (mounted) setState(() => _rolling = false);
    });
  }

  /// The value in the steps [AnimatedCount] counts (tenths with a decimal).
  int get _units => widget.decimals == 0 ? widget.value.round() : (widget.value * 10).round();

  String _formatUnits(int units) => _format(widget.decimals == 0 ? units : units / 10);

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _setText(_format(widget.value));
  }

  void _setText(String text) {
    if (_controller.text == text) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  num _round(num value) => widget.decimals == 0 ? value.round() : (value * 10).round() / 10;

  num _clamp(num value) => value.clamp(0, _max);

  String _format(num value) => widget.decimals == 0 || value % 1 == 0
      ? '${value.round()}'
      : value.toStringAsFixed(widget.decimals);

  num? _parse(String text) {
    final parsed = num.tryParse(text.replaceAll(',', '.'));
    return parsed == null ? null : _round(parsed);
  }

  void _onTextChanged(String text) {
    final typed = _parse(text) ?? 0;
    final value = _clamp(typed);
    if (value != typed) _setText(_format(value));
    if (value != widget.value) widget.onChanged(value);
  }

  void _bump(num delta) {
    final value = _clamp(_round(widget.value + delta));
    if (value != widget.value) widget.onChanged(value);
  }

  InputDecoration _decoration(ColorScheme cs, {required bool forRollingCopy}) => InputDecoration(
        isDense: true,
        // The copy only draws the number: the field below paints the rest.
        filled: !forRollingCopy,
        fillColor: cs.surfaceContainerHighest,
        suffixText: widget.suffix,
        suffixStyle: TextStyle(color: forRollingCopy ? Colors.transparent : Colors.grey, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_fieldRadius),
          borderSide: BorderSide.none,
        ),
      );

  /// The number rolling in, laid out by a decorator configured like the
  /// field's so it lands exactly on the field's own text.
  Widget _rollingCopy(ColorScheme cs) {
    // A TextField draws its text in bodyLarge merged with its style.
    final style = Theme.of(context).textTheme.bodyLarge!.merge(_valueStyle);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Visibility.maintain(
          visible: _rolling,
          child: InputDecorator(
            decoration: _decoration(cs, forRollingCopy: true),
            baseStyle: _valueStyle,
            textAlign: TextAlign.center,
            child: Padding(
              padding: const EdgeInsets.only(right: _caretRoom),
              child: Center(
                heightFactor: 1,
                child: AnimatedCount(value: _units, format: _formatUnits, style: style),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        _StepButton(
          icon: Icons.remove,
          tooltip: tr('editor_decrease', widget.lang),
          onPressed: widget.value > 0 ? () => _bump(-widget.step) : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Stack(
            children: [
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.numberWithOptions(decimal: widget.decimals > 0),
                inputFormatters: [
                  if (widget.decimals > 0) const _OneDecimalFormatter() else FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                style: _rolling ? _valueStyle.copyWith(color: Colors.transparent) : _valueStyle,
                decoration: _decoration(cs, forRollingCopy: false),
                onChanged: _onTextChanged,
              ),
              Positioned.fill(child: _rollingCopy(cs)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _StepButton(
          icon: Icons.add,
          tooltip: tr('editor_increase', widget.lang),
          onPressed: widget.value < _max ? () => _bump(widget.step) : null,
        ),
      ],
    );
  }
}

/// Lets through numbers with at most one decimal ("7", "7.5", "7,5").
class _OneDecimalFormatter extends TextInputFormatter {
  const _OneDecimalFormatter();

  static final _pattern = RegExp(r'^\d{0,3}([.,]\d?)?$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      _pattern.hasMatch(newValue.text) ? newValue : oldValue;
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final box = Theme.of(context).colorScheme.surfaceContainerHighest;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      constraints: const BoxConstraints.tightFor(width: _tapTarget, height: _tapTarget),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: box,
        // A button that can't step (e.g. − at 0) keeps its box, dimmed, so
        // the row stays balanced.
        disabledBackgroundColor: box.withValues(alpha: box.a * 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_fieldRadius)),
      ),
    );
  }
}

/// The score in the user's own format: a number (100 or 10 points, with or
/// without decimals), 5 stars or 3 faces. [score] is on the 0–10 scale;
/// tapping the selected star or face again clears the score.
class ScoreInput extends StatelessWidget {
  const ScoreInput({
    super.key,
    required this.scale,
    required this.score,
    required this.onChanged,
    required this.lang,
  });

  final ScoreScale scale;
  final double score;
  final ValueChanged<double> onChanged;
  final String lang;

  static const _faces = [
    Icons.sentiment_dissatisfied_rounded,
    Icons.sentiment_neutral_rounded,
    Icons.sentiment_satisfied_alt_rounded,
  ];
  static const _faceKeys = ['editor_face_sad', 'editor_face_neutral', 'editor_face_happy'];

  static bool _isTrue(Object? selected) => selected == true;

  @override
  Widget build(BuildContext context) {
    final units = scale.toUnits(score);
    final cs = Theme.of(context).colorScheme;
    void toggle(int value) => onChanged(scale.fromUnits(value == units ? 0 : value));
    return switch (scale.kind) {
      ScoreKind.number => NumberStepper(
          value: units,
          max: scale.max,
          step: scale.step,
          decimals: scale.decimals,
          suffix: '/ ${scale.max}',
          lang: lang,
          onChanged: (value) => onChanged(scale.fromUnits(value)),
        ),
      ScoreKind.stars => Row(
          children: [
            for (var star = 1; star <= scale.max; star++)
              IconButton(
                key: ValueKey('entry-editor-star-$star'),
                tooltip: trf('editor_stars_n', lang, {'n': star}),
                isSelected: star <= units,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => toggle(star),
                // The star that becomes the score pops.
                icon: PopOnChange(
                  value: star == units,
                  when: _isTrue,
                  child: Icon(
                    star <= units ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 32,
                    color: star <= units ? const Color(0xFFFFC107) : Colors.grey,
                  ),
                ),
              ),
          ],
        ),
      ScoreKind.faces => Row(
          children: [
            for (var face = 1; face <= scale.max; face++) ...[
              IconButton(
                key: ValueKey('entry-editor-face-$face'),
                tooltip: tr(_faceKeys[face - 1], lang),
                isSelected: face == units,
                constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
                style: IconButton.styleFrom(
                  backgroundColor: face == units ? cs.primary.withValues(alpha: 0.15) : null,
                ),
                onPressed: () => toggle(face),
                icon: PopOnChange(
                  value: face == units,
                  when: _isTrue,
                  child: Icon(_faces[face - 1], size: 32, color: face == units ? cs.primary : Colors.grey),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
    };
  }
}

/// A list entry date with a picker and a clear button. A disabled field
/// shows that the date isn't known.
class EntryDateField extends StatelessWidget {
  const EntryDateField({
    super.key,
    required this.label,
    required this.date,
    required this.lang,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final FuzzyDate date;
  final String lang;
  final ValueChanged<FuzzyDate> onChanged;
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final first = DateTime(1900);
    final last = DateTime(now.year + 1, 12, 31);
    final current = date.toDateTime() ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : (current.isAfter(last) ? last : current),
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) onChanged(FuzzyDate.fromDateTime(picked));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final empty = date.isEmpty;
    final text = !enabled ? '—' : (empty ? tr('editor_add_date', lang) : formatFuzzyDate(date, lang));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EditorLabel(label),
        Material(
          color: cs.surfaceContainerHighest.withValues(alpha: enabled ? 1 : 0.5),
          borderRadius: BorderRadius.circular(_fieldRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(_fieldRadius),
            onTap: enabled ? () => _pick(context) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _tapTarget + 4),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.event_outlined, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: empty || !enabled ? Colors.grey : null),
                    ),
                  ),
                  if (enabled && !empty)
                    IconButton(
                      tooltip: tr('clear', lang),
                      onPressed: () => onChanged(FuzzyDate.empty),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      constraints: const BoxConstraints.tightFor(width: _tapTarget, height: _tapTarget),
                      padding: EdgeInsets.zero,
                    )
                  else
                    const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// An on/off setting with a short explanation; disabled when [onChanged] is
/// null (the current value isn't known).
class EntrySwitchRow extends StatelessWidget {
  const EntrySwitchRow({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontSize: 14)),
        subtitle: Text(hint, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        value: value,
        onChanged: onChanged,
      );
}
