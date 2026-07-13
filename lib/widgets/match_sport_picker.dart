import 'package:flutter/material.dart';

import '../core/sport_type.dart';
import '../l10n/matchpay_strings.dart';
import 'sport_chip_picker.dart';

/// Selector del deporte de un partido/convocatoria (no la preferencia global).
class MatchSportPicker extends StatelessWidget {
  final SportType value;
  final ValueChanged<SportType>? onChanged;
  final bool enabled;

  const MatchSportPicker({
    super.key,
    required this.value,
    this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.tr('matchSportLabel'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        SportChipPicker(
          value: value,
          onChanged: onChanged,
          enabled: enabled,
        ),
      ],
    );
  }
}
