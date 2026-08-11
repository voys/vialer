import 'package:dartx/dartx.dart';
import 'package:vialer/data/models/user/user.dart';
import 'package:vialer/data/repositories/calling/voip/destination_repository.dart';
import 'package:vialer/dependency_locator.dart';

import '../../../../repositories/user/details/user_details.dart';
import '../../../calling/voip/destination.dart';
import '../../client.dart';
import '../../settings/call_setting.dart';
import '../user_refresh_task_performer.dart';

class RefreshUserDetails extends UserRefreshTaskPerformer {
  const RefreshUserDetails();
  UserDetailsRepository get _userDetails =>
      dependencyLocator<UserDetailsRepository>();

  DestinationRepository get _destinations =>
      dependencyLocator<DestinationRepository>();

  @override
  Future<UserMutator> performUserRefreshTask(User user) async {
    final userDetails = await _userDetails.getUserDetails();

    if (userDetails == null) return unmutatedUser;

    _storeSelectedDestinationId(userDetails);

    return (User user) {
      _updateDestinationList(userDetails);
      _updateUseMobileNumberAsFallback(userDetails);
      _updateSelectedDestination(userDetails);

      return user.copyWith(
        webphoneAccountId: () => userDetails.webphone?.voipAccount?.id,
        client: user.client.copyWith(
          enabledModules: _enabledModules(userDetails),
        ),
      );
    };
  }

  void _storeSelectedDestinationId(UserDetails userDetails) {
    final selectedDestinationId = userDetails.selectedDestination?.id;

    if (selectedDestinationId != null) {
      _destinations.selectedUserDestinationId = selectedDestinationId.toInt();
    }
  }

  void _updateSelectedDestination(UserDetails userDetails) => updateSetting(
    CallSetting.destination,
    (userDetails.selectedDestination?.asDestination() ??
            const Destination.notAvailable())
        .identifier,
  );

  void _updateDestinationList(UserDetails userDetails) =>
      _destinations.updateDestinations(userDetails.availableDestinations);

  void _updateUseMobileNumberAsFallback(UserDetails userDetails) =>
      updateSetting(
        CallSetting.useMobileNumberAsFallback,
        userDetails.app?.useMobileNumberAsFallback ?? false,
      );

  List<Module> _enabledModules(UserDetails userDetails) {
    final modules = userDetails.client?.modules;
    if (modules == null) return [];

    return [
      if (modules.callrecording) Module.callRecording,
      if (modules.intelligence?.transcribeCallrecordings == true)
        Module.transcribeCallRecordings,
      if (modules.intelligence?.summarizeCallTranscriptions == true)
        Module.summarizeCallTranscriptions,
    ];
  }
}
