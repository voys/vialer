import 'package:dartx/dartx.dart';

import '../../data/models/call_records/call_record.dart';
import '../../data/models/colltacts/contact.dart';
import '../../data/models/user/user.dart';
import '../../domain/usecases/user/get_logged_in_user.dart';

extension AiSummaryCallRecord on CallRecord {
  bool get shouldShowAiSummary => summary != null && !shouldShowAiUpsell;
  bool get shouldShowAiUpsell =>
      !GetLoggedInUserUseCase()().hasSummarizeCallTranscriptionsModule;
}

extension ThirdPartyCallRecord on CallRecord {
  bool get hasThirdPartyNumber => thirdPartyNumber.isNotBlank;

  bool get isAnonymous => thirdPartyNumber.trim().toLowerCase() == 'anonymous';

  Contact? get thirdPartyContact => switch (this) {
    CallRecordWithContact record => record.contact,
    ClientCallRecordWithContact record =>
      isInbound ? record.callerContact : record.destinationContact,
    _ => null,
  };
}
