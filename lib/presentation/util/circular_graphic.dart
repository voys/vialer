import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vialer/presentation/resources/theme.dart';

class CircularGraphic extends StatelessWidget {
  const CircularGraphic(this.icon, {super.key});

  final FaIconData icon;

  @override
  Widget build(BuildContext context) {
    final outerCircleColor = context.brand.theme.colors.primaryLight.withValues(
      alpha: 0.4,
    );

    return Center(
      child: Material(
        shape: const CircleBorder(),
        color: outerCircleColor,
        elevation: 2,
        shadowColor: context.brand.theme.colors.primary.withValues(alpha: 0),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Material(
            shape: const CircleBorder(),
            color: outerCircleColor.withValues(alpha: 1),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FaIcon(
                icon,
                size: 40,
                color: context.brand.theme.colors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
