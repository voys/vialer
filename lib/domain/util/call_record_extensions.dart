import '../../data/models/call_records/call_record.dart';
import '../../data/models/user/user.dart';
import '../../domain/usecases/user/get_logged_in_user.dart';

extension AiSummaryCallRecord on CallRecord {
  bool get shouldShowAiSummary => summary != null && !shouldShowAiUpsell;
  bool get shouldShowAiUpsell =>
      !GetLoggedInUserUseCase()().hasSummarizeCallTranscriptionsModule;
}
