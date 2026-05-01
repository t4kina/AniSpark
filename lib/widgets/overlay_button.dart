import 'package:flutter/material.dart';

Widget overlayBtn({
  required IconData icon,
  Color color = Colors.white,
  required VoidCallback? onPressed,
}) =>
    GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
