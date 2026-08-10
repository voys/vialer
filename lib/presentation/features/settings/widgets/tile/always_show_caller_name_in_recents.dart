import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import '../../../../../../data/models/user/settings/app_setting.dart';
import '../../../../../../data/models/user/user.dart';
import '../../../../resources/localizations.dart';
import 'value.dart';
import 'widget.dart';

class AlwaysShowCallerNameInRecentsTile extends StatelessWidget {
  const AlwaysShowCallerNameInRecentsTile(this.user, {super.key});

  final User user;

  @override
  Widget build(BuildContext context) {
    return SettingTile(
      label: Text(
        context.msg.main.settings.list.recents.alwaysShowCallerName.title,
      ),
      description: Text(
        context.msg.main.settings.list.recents.alwaysShowCallerName.description,
      ),
      child: BoolSettingValue(
        user.settings,
        AppSetting.alwaysShowCallerNameInRecents,
      ),
    );
  }
}
