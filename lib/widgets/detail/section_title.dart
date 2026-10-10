import 'package:flutter/material.dart';

/// The small grey caps heading of the media detail page's sections.
class DetailSectionTitle extends StatelessWidget {
  const DetailSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.grey,
            letterSpacing: 0.5,
          ),
        ),
      );
}
