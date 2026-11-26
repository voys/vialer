import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void mockPermissionsForIOS() {
  if (!Platform.isIOS) return;

  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  const granted = 1;
  const serviceEnabled = 1;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'checkPermissionStatus':
            return granted;
          case 'requestPermissions':
            final permissions = (call.arguments as List).cast<int>();
            return {for (final permission in permissions) permission: granted};
          case 'checkServiceStatus':
            return serviceEnabled;
          case 'shouldShowRequestPermissionRationale':
            return false;
          case 'openAppSettings':
            return true;
          default:
            return null;
        }
      });
}
