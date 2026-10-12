import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// A long text cut to [collapsedLines] lines, with a "read more" / "show
/// less" toggle once it's longer than [toggleThreshold] characters.
class ExpandableText extends StatefulWidget {
  const ExpandableText({
    super.key,
    required this.text,
    required this.expandLabel,
    required this.collapseLabel,
    this.collapsedLines = 4,
    this.toggleThreshold = 200,
  });

  final String text;
  final String expandLabel;
  final String collapseLabel;
  final int collapsedLines;
  final int toggleThreshold;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 13.5, height: 1.55, color: cs.onSurface.withValues(alpha: 0.8));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedCrossFade(
          duration: AppMotion.of(context, AppMotion.medium),
          firstCurve: AppMotion.exit,
          secondCurve: AppMotion.enter,
          sizeCurve: AppMotion.standard,
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: Text(
            widget.text,
            maxLines: widget.collapsedLines,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
          secondChild: Text(widget.text, style: style),
        ),
        if (widget.text.length > widget.toggleThreshold)
          // Padded to a 44px touch target.
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    _expanded ? widget.collapseLabel : widget.expandLabel,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
