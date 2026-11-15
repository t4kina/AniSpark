import 'package:flutter/material.dart';

import '../theme/app_layout.dart';
import '../theme/app_text.dart';

/// Opens the app's bottom sheet: one surface, one corner radius and one
/// handle, whatever it holds.
///
/// It is as tall as what [builder] returns, up to [maxHeightFraction] of the
/// screen, and never goes under the status bar. Content that scrolls takes
/// the room it is left (see `SheetListSurface` for lists); content that
/// grows when dragged is a `DraggableScrollableSheet` with `expand: false`.
///
/// The handle is already there: [builder] starts with a [SheetTitle], or
/// with its own content.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxHeightFraction = 1,
}) {
  assert(maxHeightFraction > 0 && maxHeightFraction <= 1);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
    constraints: maxHeightFraction < 1
        ? BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * maxHeightFraction)
        : null,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetHandle(),
        Flexible(child: builder(sheetContext)),
      ],
    ),
  );
}

/// The short bar at the top of a sheet that says it can be dragged away.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  static const _size = Size(36, 4);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Center(
        child: Container(
          width: _size.width,
          height: _size.height,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
            borderRadius: AppRadius.pillAll,
          ),
        ),
      ),
    );
  }
}

/// What a sheet is for, under its handle.
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.md),
      child: Text(text, textAlign: TextAlign.center, style: AppText.headline),
    );
  }
}
