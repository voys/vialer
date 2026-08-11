import 'package:flutter_phone_lib/flutter_phone_lib.dart';
import 'package:injectable/injectable.dart';
import 'package:vialer/domain/usecases/use_case.dart';

import '../../../../data/models/user/settings/app_setting.dart';
import '../../../../data/models/user/settings/call_setting.dart';
import '../../../../data/models/user/user.dart';
import '../../user/get_logged_in_user.dart';

@injectable
class PrepareVoipPreferences extends UseCase {
  PrepareVoipPreferences(this._getUser);

  final GetLoggedInUserUseCase _getUser;

  User get user => _getUser();

  Future<Preferences> call() async => Preferences(
    useApplicationProvidedRingtone: !user.settings.get(
      CallSetting.usePhoneRingtone,
    ),
    showCallsInNativeRecents: user.settings.get(
      AppSetting.showCallsInNativeRecents,
    ),
    enableAdvancedLogging: user.settings.get(
      AppSetting.enableAdvancedVoipLogging,
    ),
  );
}
