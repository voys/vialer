import 'package:flutter/material.dart';

import '../../../../../data/models/call_records/call_record.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../util/color.dart';
import '../../../util/contact.dart';
import 'item.dart';

class CallRecordAvatar extends StatelessWidget {
  const CallRecordAvatar(this.callRecord, {super.key});

  final CallRecord callRecord;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Avatar(
        name: callRecord.displayLabel,
        backgroundColor: calculateColorForPhoneNumber(
          context,
          callRecord.thirdPartyNumber,
        ),
        showFallback: callRecord is CallRecordWithContact &&
            (callRecord as CallRecordWithContact).contact?.displayName == null,
        image: callRecord is CallRecordWithContact
            ? (callRecord as CallRecordWithContact).contact?.avatar
            : null,
        fallback: const Text('#'),
      ),
    );
  }
}
