import 'package:flutter/material.dart';

/// Gives the scrolling part of a bottom sheet a surface of its own.
///
/// Row backgrounds (the theme gives every ListTile one), highlights and
/// splashes are painted by the nearest [Material], not by the list. Without
/// this they belong to the sheet itself, so rows that scroll or bounce out
/// of the list keep painting over the sheet's title and square off its
/// rounded corners. With it they are clipped to the list.
class SheetListSurface extends StatelessWidget {
  const SheetListSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(type: MaterialType.transparency, child: child);
}
