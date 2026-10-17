import 'package:flutter/material.dart';
import '../utils/haptics.dart';

/// A rounded bottom sheet with a drag handle, a title and one row per
/// option — the same picker style Settings uses (see `_showPicker` there),
/// in place of a native dropdown menu so every picker in the app looks and
/// behaves the same way.
Future<void> showOptionSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T option) labelOf,
  required T current,
  required ValueChanged<T> onSelected,
  IconData Function(T option)? iconOf,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: options.map((opt) {
                  final selected = opt == current;
                  return Builder(builder: (ctx) {
                    final color = selected ? Theme.of(ctx).colorScheme.primary : null;
                    return ListTile(
                      leading: iconOf == null
                          ? null
                          : Icon(iconOf(opt), size: 18, color: color ?? Colors.grey),
                      title: Text(labelOf(opt), style: TextStyle(color: color, fontSize: 14)),
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
          ],
        ),
      ),
    ),
  );
}
