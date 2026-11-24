import 'package:pigeon/pigeon.dart';

// Keys of the secrets in secure storage, which Dart and native code share.
const String secureStorageApiTokenKey = 'api_token';
const String secureStorageSipPasswordKey = 'sip_password';

enum OrderBy { givenName, familyName }

class ContactSort {
  OrderBy? orderBy;
}

@HostApi()
// ignore:one_member_abstracts
abstract class ContactSortHostApi {
  ContactSort getSorting();
}

/// Allow logging to be performed natively, this allows us to bypass the
/// conversion from native to Dart and the associated overhead.
@HostApi()
// ignore:one_member_abstracts
abstract class NativeLogging {
  @asyncCallback
  void startNativeRemoteLogging(
    String token,
    String userIdentifier,
    Map<String, String> anonymizationRules,
  );

  void startNativeConsoleLogging();

  void stopNativeRemoteLogging();

  void stopNativeConsoleLogging();
}

@HostApi()
// ignore:one_member_abstracts
abstract class NativeIncomingCallScreen {
  void launch(
    String remotePartyHeading,
    String remotePartySubheading,
    String imageUri,
  );
}

@HostApi()
// ignore:one_member_abstracts
abstract class NativeMetrics {
  void initialize();
}

@HostApi()
abstract class CallScreenBehavior {
  void enable();
  void disable();
}

@HostApi()
// ignore:one_member_abstracts
abstract class Tones {
  void playForDigit(String digit);
}

@HostApi()
abstract class AppUpdates {
  void check();
  void completeAndroidFlexibleUpdate();
}

@FlutterApi()
abstract class AndroidFlexibleUpdateHandler {
  // ignore: avoid_positional_boolean_parameters
  @asyncCallback
  void onUpdateTypeKnown(bool isFlexible);
  @asyncCallback
  void onDownloaded();
}

@HostApi()
// ignore:one_member_abstracts
abstract class CallThrough {
  void startCall(String number);
}

@HostApi()
// ignore: one_member_abstracts
abstract class Contacts {
  @asyncCallback
  void importContacts(String cacheFilePath);
  @asyncCallback
  void importContactAvatars(String avatarDirectoryPath);
}

@HostApi()
abstract class GooglePlayServices {
  bool isAvailable();
}

@HostApi()
abstract class MiddlewareRegistrar {
  void register(String token);
  void unregister(int appAccountId);
}

@FlutterApi()
abstract class NativeToFlutter {
  @asyncCallback
  void launchDialerAndPopulateNumber(String number);
}

@HostApi()
// ignore: one_member_abstracts
abstract class NativeClipboard {
  @asyncCallback
  bool hasPhoneNumber();
}
