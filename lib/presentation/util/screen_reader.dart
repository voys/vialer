import 'package:material_ui/material_ui.dart';

extension Accessibility on BuildContext {
  bool get isUsingScreenReader => MediaQuery.of(this).accessibleNavigation;
}
