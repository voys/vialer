import 'dart:async';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vialer/presentation/resources/localizations.dart';

import '../../../../../../data/models/calling/outgoing_number/outgoing_number.dart';
import '../../../../../../data/models/user/settings/call_setting.dart';
import '../../../../../../data/models/user/user.dart';
import '../../../../../data/repositories/voipgrid/user_permissions.dart';
import '../../../call/widgets/outgoing_number_prompt/item.dart';
import 'category/widget.dart';
import 'dialog/base/show_setting_tile_alert_dialog.dart';
import 'dialog/edit_outgoing_number_dialog.dart';
import 'widget.dart';

class OutgoingNumberTile extends StatelessWidget {
  OutgoingNumberTile(
    this.user, {
    super.key,
    this.enabled = true,
    this.recentOutgoingNumbers = const Iterable<OutgoingNumber>.empty(),
  }) : _outgoingNumber = user.settings.get(_key);
  final User user;

  final OutgoingNumber _outgoingNumber;
  final Iterable<OutgoingNumber> recentOutgoingNumbers;
  final bool enabled;

  static const _key = CallSetting.outgoingNumber;

  bool get _hasPermission =>
      user.hasPermission(Permission.canChangeOutgoingNumber);

  @override
  Widget build(BuildContext context) {
    return SettingTileCategory(
      icon: FontAwesomeIcons.phoneArrowRight,
      titleText:
          context.msg.main.settings.list.accountInfo.businessNumber.title,
      bottomBorder: false,
      children: [
        SettingTile(
          description: Text(
            context
                .msg
                .main
                .settings
                .list
                .accountInfo
                .businessNumber
                .description,
          ),
          childFillWidth: true,
          onTap: _hasPermission
              ? () => _launchEditOutgoingNumberDialog(context)
              : null,
          child: Row(
            children: [
              Expanded(
                child: OutgoingNumberInfo(
                  item: user.settings.get(CallSetting.outgoingNumber),
                  textStyle: const TextStyle(fontSize: 16),
                  subtitleTextStyle: const TextStyle(fontSize: 12),
                ),
              ),
              if (_hasPermission)
                const FaIcon(
                  FontAwesomeIcons.pen,
                  size: 18,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _launchEditOutgoingNumberDialog(BuildContext context) async {
    await showSettingTileAlertDialogAndSaveOnCompletion<OutgoingNumber>(
      context: context,
      settingKey: _key,
      builder: (context) => EditOutgoingNumberDialog(
        initialValue: _outgoingNumber,
        user: user,
      ),
    );
  }
}
