import 'package:gleap_sdk/gleap_sdk.dart';
import 'package:gleap_sdk/models/gleap_user_property_model/gleap_user_property_model.dart';

import '../../use_case.dart';
import '../../user/get_brand.dart';
import '../../user/get_logged_in_user.dart';
import 'initialize_gleap.dart';

class IdentifyGleapUser extends UseCase {
  final _initializeGleap = InitializeGleap();
  final _getBrand = GetBrand();
  final _getUser = GetLoggedInUserUseCase();

  Future<void> call() async {
    if (!_initializeGleap.isAvailable) return;

    await _initializeGleap();

    final user = _getUser();

    try {
      await Gleap.identifyContact(
        userId: user.uuid,
        userProperties: GleapUserProperty(
          name: user.fullName,
          email: user.email,
          companyName: user.client.name,
          companyId: user.client.uuid,
          customData: {
            'brand': _getBrand().identifier,
            'clientId': user.client.uuid,
          },
        ),
      );
    } on Exception catch (exception) {
      logger.warning('Could not identify Gleap user', exception);
    }
  }
}
