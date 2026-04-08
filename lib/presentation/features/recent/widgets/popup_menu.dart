import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:vialer/presentation/resources/localizations.dart';
import 'package:vialer/presentation/resources/theme.dart';

import '../../../../../data/models/call_records/call_record.dart';
import '../../../../../domain/util/call_record_extensions.dart';

class RecentItemPopupMenu extends StatelessWidget {
  const RecentItemPopupMenu({
    required this.callRecord,
    required this.onPopupMenuItemPress,
    super.key,
  });

  final CallRecord callRecord;
  final void Function(RecentCallMenuAction action) onPopupMenuItemPress;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<RecentCallMenuAction>(
      onSelected: onPopupMenuItemPress,
      itemBuilder: (context) => [
        PopupMenuItem<RecentCallMenuAction>(
          value: RecentCallMenuAction.callDetails,
          child: ListTile(
            leading: Container(
              width: 24,
              alignment: Alignment.center,
              child: const FaIcon(FontAwesomeIcons.waveformLines, size: 20),
            ),
            title: Row(
              spacing: 6,
              children: [
                Text(
                  context.msg.main.recent.list.item.popupMenu.callDetails.title,
                ),
                if (callRecord.shouldShowAiSummary)
                  const FaIcon(FontAwesomeIcons.solidSparkles, size: 12),
              ],
            ),
          ),
        ),
        PopupMenuItem<RecentCallMenuAction>(
          value: RecentCallMenuAction.copy,
          child: ListTile(
            leading: Container(
              width: 24,
              alignment: Alignment.center,
              child: const FaIcon(FontAwesomeIcons.copy, size: 20),
            ),
            title: Text(context.msg.main.recent.list.item.popupMenu.copy),
          ),
        ),
        PopupMenuItem<RecentCallMenuAction>(
          value: RecentCallMenuAction.call,
          child: ListTile(
            leading: Container(
              width: 24,
              alignment: Alignment.center,
              child: const FaIcon(FontAwesomeIcons.phone, size: 20),
            ),
            title: Text(context.msg.main.recent.list.item.popupMenu.call),
          ),
        ),
      ],
      icon: FaIcon(
        FontAwesomeIcons.ellipsisVertical,
        color: context.brand.theme.colors.grey1,
        size: 16,
      ),
    );
  }
}


enum RecentCallMenuAction { copy, call, callDetails, none }

