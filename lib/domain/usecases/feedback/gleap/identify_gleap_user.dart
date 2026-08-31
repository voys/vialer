import 'package:gleap_sdk/gleap_sdk.dart';
import 'package:gleap_sdk/models/gleap_user_property_model/gleap_user_property_model.dart';

import '../../../../data/models/user/user.dart';
import '../../use_case.dart';
import '../../user/get_brand.dart';
import 'gleap_state.dart';

class IdentifyGleapUser extends UseCase {
  Future<void> call(User user) async {
    if (!GleapState.isInitialized) return;

    try {
      await Gleap.identifyContact(
        userId: user.uuid,
        userProperties: GleapUserProperty(
          name: user.fullName,
          email: user.email,
          companyName: user.client.name,
          companyId: user.client.uuid,
          customData: {
            'brand': GetBrand()().identifier,
            'clientId': user.client.uuid,
          },
        ),
      );
    } on Exception catch (exception) {
      logger.warning('Could not identify Gleap user', exception);
    }
  }
}
