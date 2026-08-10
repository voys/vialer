import 'package:flutter/material.dart';

import '../../../../../data/models/call_records/call_record.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../util/color.dart';
import 'item.dart';

class CallRecordAvatar extends StatelessWidget {
  const CallRecordAvatar(this.callRecord, {super.key});

  final CallRecord callRecord;

  @override
  Widget build(BuildContext context) {
    final label = callRecord.displayLabel;

    return ExcludeSemantics(
      child: Avatar(
        name: label,
        backgroundColor: calculateColorForPhoneNumber(
          context,
          callRecord.thirdPartyNumber,
        ),
        showFallback: label == callRecord.thirdPartyNumber,
        image: callRecord is CallRecordWithContact
            ? (callRecord as CallRecordWithContact).contact?.avatar
            : null,
        fallback: const Text('#'),
      ),
    );
  }
}
