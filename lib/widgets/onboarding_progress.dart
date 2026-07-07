import 'package:flutter/material.dart';

import '../core/matchpay_design_tokens.dart';

/// Indicador de paso del onboarding (intro + deporte).
class OnboardingProgress extends StatelessWidget {
  final String stepLabel;
  final int current;
  final int total;
  final Color accent;

  const OnboardingProgress({
    super.key,
    required this.stepLabel,
    required this.current,
    required this.total,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          stepLabel,
          style: MatchPayTokens.sectionLabelStyle(),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(total, (i) {
            final step = i + 1;
            final active = step <= current;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: step == current ? 28 : 10,
              height: 8,
              decoration: BoxDecoration(
                color: active ? accent : MatchPayTokens.borderSubtle,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }
}
