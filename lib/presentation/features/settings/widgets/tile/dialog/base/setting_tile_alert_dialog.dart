import 'package:gap/gap.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vialer/presentation/resources/localizations.dart';
import 'package:vialer/presentation/resources/theme.dart';

class SettingTileAlertDialog<T> extends StatelessWidget {
  const SettingTileAlertDialog({
    required this.title,
    required this.content,
    required this.currentValue,
    super.key,
    this.description,
    this.showCancelButton = true,
    this.showSaveButton = true,
    this.canSave = true,
  });

  final String title;
  final String? description;
  final Widget content;
  final T? currentValue;
  final bool showCancelButton;
  final bool showSaveButton;

  /// Whether the [currentValue] can be saved, this will keep showing the save
  /// button but in a disabled state.
  final bool canSave;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Semantics(
        header: true,
        child: Text(title),
      ),
      content: SizedBox(
        width: 500,
        child: Semantics(
          explicitChildNodes: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (description != null) ...[
                Text(description!),
                const Gap(20),
              ],
              content,
            ],
          ),
        ),
      ),
      actions: [
        if (showCancelButton) const _CancelButton(),
        if (showSaveButton)
          _SaveButton(
            isEnabled: canSave,
            value: currentValue,
          ),
      ],
    );
  }
}

class _SaveButton<T> extends StatelessWidget {
  const _SaveButton({required this.isEnabled, super.key, this.value});

  final bool isEnabled;
  final T? value;

  bool get _shouldAllowSaving => isEnabled && value != null;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      child: Text(
        context.msg.main.contacts.sharedContacts.form.saveContactButtonTitle,
      ),
      onPressed: _shouldAllowSaving
          ? () => Navigator.of(context).pop(value)
          : null,
      style: TextButton.styleFrom(
        disabledForegroundColor: context.brand.theme.colors.grey1,
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton();

  @override
  Widget build(BuildContext context) {
    return TextButton(
      child: Text(context.msg.generic.button.cancel),
      onPressed: () => Navigator.of(context).pop(),
    );
  }
}
