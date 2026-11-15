import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_text.dart';
import '../utils/haptics.dart';
import 'app_sheet.dart';
import 'sheet_list_surface.dart';

/// The most of the screen a list of options takes; past it they scroll.
const _maxHeightFraction = 0.7;

/// A bottom sheet with a title and one row per option, in place of a native
/// dropdown menu so every picker in the app looks and behaves the same way.
Future<void> showOptionSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T option) labelOf,
  required T current,
  required ValueChanged<T> onSelected,
  IconData Function(T option)? iconOf,
}) {
  return showAppSheet<void>(
    context: context,
    maxHeightFraction: _maxHeightFraction,
    builder: (_) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetTitle(title),
            Flexible(
              child: SheetListSurface(
                child: ListView(
                  shrinkWrap: true,
                  children: options.map((opt) {
                    final selected = opt == current;
                    return Builder(builder: (ctx) {
                      final color = selected ? Theme.of(ctx).colorScheme.primary : null;
                      return ListTile(
                        leading: iconOf == null
                            ? null
                            : Icon(iconOf(opt), size: 18, color: color ?? ctx.colors.textSecondary),
                        title: Text(labelOf(opt), style: AppText.body.copyWith(color: color)),
                        trailing: selected ? Icon(Icons.check, size: 18, color: color) : null,
                        onTap: () {
                          selectionHaptic();
                          onSelected(opt);
                          Navigator.pop(context);
                        },
                      );
                    });
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
