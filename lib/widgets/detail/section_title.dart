import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';

/// The small grey caps heading above a section of a detail page.
class DetailSectionTitle extends StatelessWidget {
  const DetailSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(text, style: AppText.overline.copyWith(color: context.colors.textSecondary)),
      );
}
