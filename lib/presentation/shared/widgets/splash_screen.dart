import 'package:material_ui/material_ui.dart';

import '../../resources/theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({
    this.iconColor = Colors.white,
    this.gradient,
    super.key,
  });

  final Color iconColor;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient ?? context.brand.theme.splashScreenGradient,
      ),
      child: Center(
        child: Icon(
          context.brand.theme.logo,
          size: 64,
          color: iconColor,
        ),
      ),
    );
  }
}
