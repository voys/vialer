import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';

class SuggestionChip extends StatelessWidget {
  const SuggestionChip({
    required this.icon,
    required this.label,
    required this.onSelected,
    super.key,
  });
  final FaIconData icon;
  final String label;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FaIcon(
            icon,
            size: 18,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: Theme.of(context).primaryColor),
          ),
        ],
      ),
      backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.4),
      shape: StadiumBorder(
        side: BorderSide(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.4),
          width: 0,
        ),
      ),
      onPressed: onSelected,
    );
  }
}
