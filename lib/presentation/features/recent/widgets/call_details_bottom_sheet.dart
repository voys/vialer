import 'dart:io';

import 'package:duration/duration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:vialer/presentation/resources/theme.dart';

import '../../../../../data/models/call_records/call_record.dart';
import '../../../resources/localizations.dart';
import 'call_record_avatar.dart';
import 'item.dart';

class CallDetailsBottomSheet extends StatelessWidget {
  const CallDetailsBottomSheet({required this.callRecord, super.key});

  final CallRecord callRecord;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = 24 + MediaQuery.of(context).viewInsets.bottom;
    final subtitleColor = context.brand.theme.colors.grey4;
    final strings = context.msg.main.recent.list.item.popupMenu;
    final callParties = callRecord.callPartyRows(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CallHeader(
          callRecord: callRecord,
          hasCallParties: callParties.isNotEmpty,
        ),
        if (callParties.isNotEmpty)
          _CallPartySection(callParties: callParties),
        if (callRecord.summary != null)
          _AiSummarySection(
            summary: callRecord.summary!,
            title: strings.aiCallSummary.title,
            doesNotExist: strings.aiCallSummary.doesNotExist,
          ),
        Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 12,
            bottom: bottomPadding,
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              strings.callDetails.callId(callRecord.id),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: subtitleColor),
            ),
          ),
        ),
      ],
    );
  }
}

class _CallHeader extends StatelessWidget {
  const _CallHeader({
    required this.callRecord,
    required this.hasCallParties,
  });

  final CallRecord callRecord;
  final bool hasCallParties;

  @override
  Widget build(BuildContext context) {
    final subtitleColor = context.brand.theme.colors.grey4;
    final subtitleStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: subtitleColor);
    final strings = context.msg.main.recent.list.item.popupMenu;
    final displayLabel = callRecord.displayLabel;
    final number = callRecord.thirdPartyNumber;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: hasCallParties ? 12 : 16,
      ),
      child: Row(
        children: [
          CallRecordAvatar(callRecord),
          const Gap(16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.callDetails.callWith(displayLabel),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (displayLabel != number) ...[
                  const Gap(2),
                  Text(number, style: subtitleStyle),
                ],
                const Gap(4),
                Text(callRecord.callMetadata, style: subtitleStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallPartySection extends StatelessWidget {
  const _CallPartySection({required this.callParties});

  final List<_CallPartyRowData> callParties;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in callParties) ...[
            _CallPartyRow(label: row.label, parties: row.parties),
            if (row != callParties.last) const Gap(8),
          ],
        ],
      ),
    );
  }
}

class _AiSummarySection extends StatelessWidget {
  const _AiSummarySection({
    required this.summary,
    required this.title,
    required this.doesNotExist,
  });

  final String summary;
  final String title;
  final String doesNotExist;

  @override
  Widget build(BuildContext context) {
    final subtitleColor = context.brand.theme.colors.grey4;

    return Flexible(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.brand.theme.colors.grey3,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    FaIcon(
                      FontAwesomeIcons.solidSparkles,
                      size: 18,
                      color: subtitleColor,
                    ),
                    const Gap(8),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    if (summary.isNotEmpty)
                      GestureDetector(
                        onTap: () =>
                            Clipboard.setData(ClipboardData(text: summary)),
                        child: const FaIcon(FontAwesomeIcons.copy, size: 20),
                      ),
                  ],
                ),
              ),
              const Gap(8),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    summary.isEmpty ? doesNotExist : summary,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallPartyRowData {
  const _CallPartyRowData({required this.label, required this.parties});
  final String label;
  final List<CallParty> parties;
}

class _CallPartyRow extends StatelessWidget {
  const _CallPartyRow({required this.label, required this.parties});

  final String label;
  final List<CallParty> parties;

  String _partyText(CallParty party) =>
      party.hasName ? '${party.name!} (${party.number})' : party.number;

  @override
  Widget build(BuildContext context) {
    final subtitleColor = context.brand.theme.colors.grey4;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: subtitleColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Gap(8),
        Expanded(
          child: Text(
            parties.map(_partyText).join(' & '),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: subtitleColor),
          ),
        ),
      ],
    );
  }
}

extension on CallRecord {
  List<_CallPartyRowData> callPartyRows(BuildContext context) {
    final strings = context.msg.main.recent.list.item.popupMenu;

    if (renderType == CallRecordRenderType.internalCall) {
      return [
        _CallPartyRowData(
          label: strings.internal.title,
          parties: [caller, destination],
        ),
      ];
    }

    if (renderType == CallRecordRenderType.other) {
      return [
        if (isInbound)
          _CallPartyRowData(label: strings.from, parties: [caller]),
        if (answeredElsewhere && isInbound)
          _CallPartyRowData(label: strings.answered, parties: [destination]),
      ];
    }

    return [];
  }

  String get callMetadata {
    final localDate = this.date.toLocal();
    final formattedDate = DateFormat.yMd(Platform.localeName).format(localDate);
    final formattedTime = DateFormat.Hm().format(localDate);
    final formattedDuration = prettyDuration(
      duration,
      abbreviated: true,
      delimiter: ' ',
      spacer: '',
    );
    return '$formattedDate • $formattedTime - $formattedDuration';
  }
}
