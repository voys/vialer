import 'package:vialer/data/models/user/settings/app_setting.dart';
import 'package:vialer/domain/usecases/use_case.dart';
import 'package:vialer/domain/usecases/user/get_stored_user.dart';
import 'package:vialer/domain/usecases/user/settings/change_setting.dart';

class DisableAdvancedVoipLogging extends UseCase {
  late final _getCurrentUser = GetStoredUserUseCase();

  Future<void> call() async {
    if (_getCurrentUser() == null) return;

    await ChangeSettingUseCase()(
      AppSetting.enableAdvancedVoipLogging,
      false,
      track: false,
    );
  }
}
