import 'package:flutter/material.dart';
import '../models/batai.dart';

/// Small status badge used by the batai list and detail screens.
class BataiStatusChip extends StatelessWidget {
  final BataiStatus status;
  const BataiStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      BataiStatus.active => Colors.green.shade700,
      BataiStatus.settled => Colors.blue.shade700,
      BataiStatus.cancelled => Colors.grey.shade600,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        bataiStatusUrdu(status),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
