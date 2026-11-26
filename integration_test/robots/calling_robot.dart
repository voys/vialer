import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_phone_lib/flutter_phone_lib.dart'
    hide AttendedTransferStarted;
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vialer/data/repositories/legacy/storage.dart';
import 'package:vialer/dependency_locator.dart';
import 'package:vialer/presentation/features/call/call_page.dart';
import 'package:vialer/presentation/features/call/widgets/audio_route_picker.dart';
import 'package:vialer/presentation/features/call/widgets/call_button.dart';
import 'package:vialer/presentation/features/call/widgets/call_header_container.dart';
import 'package:vialer/presentation/features/call/widgets/call_transfer.dart';
import 'package:vialer/presentation/features/dialer/dialer_page.dart';
import 'package:vialer/presentation/features/main_page.dart';
import 'package:vialer/presentation/shared/widgets/caller.dart';
import 'package:vialer/presentation/shared/widgets/dial_pad/keypad.dart';
import 'package:vialer/presentation/shared/widgets/dial_pad/widget.dart';

import '../utils/baresip_client.dart';
import '../utils/test_extensions.dart';
import 'integration_test_robot.dart';

class CallingRobot extends IntegrationTestRobot {
  CallingRobot(super.tester, this.config) {
    _suppressPromptsThatInterruptCalls();
  }

  static const _incomingCallTimeout = Duration(seconds: 120);

  final TestConfiguration config;

  /// The outgoing number picker would open before the call is placed, and the
  /// call rating survey randomly after it ends. Neither is what these tests
  /// are about, so both are kept from showing.
  void _suppressPromptsThatInterruptCalls() {
    dependencyLocator<StorageRepository>()
      ..doNotShowOutgoingNumberSelector = true
      ..lastCallRatingAskedTime = DateTime.now();
  }

  /// The dialer is a tab on iOS, and a page opened from a floating button on
  /// Android.
  Future<void> openDialer() async {
    if (Platform.isIOS) {
      await tester.tap(
        find.descendant(
          of: find.byKey(MainPage.keys.navigationBar),
          matching: find.text(tester.msg.main.dialer.menu.title),
        ),
      );
    } else {
      await tester.tap(find.byType(FloatingActionButton));
    }
    await tester.pumpAndSettle();

    await tester.pumpUntil(
      () => _callerState is CanCall,
      reason:
          'The dialer should allow calling, check that the app has the phone '
          'and microphone permissions',
    );

    expect(find.byType(DialerPage), findsOneWidget);
  }

  Future<void> enterPhoneNumber(String phoneNumber) async {
    for (final char in phoneNumber.characters) {
      if (char == '+') {
        await _longPressKeypadButton('0');
      } else {
        await _tapKeypadButton(char);
      }
    }
  }

  Future<void> tapCallButton() async {
    await tester.tap(
      find.descendant(
        of: find.byType(DialPad),
        matching: find.byType(CallButton),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> waitForCallToConnect() async {
    await tester.pumpUntilFound(
      find.byType(CallPage),
      reason: 'CallPage should appear after starting a call',
      settle: false,
    );

    await tester.pumpUntilGone(
      find.text(tester.msg.main.call.ongoing.state.calling),
      reason: 'The call should connect',
      settle: false,
    );
  }

  /// Waits for the app to start ringing for an incoming call.
  ///
  /// A ringing incoming call is shown by the native `IncomingCallActivity`,
  /// on top of the Flutter app, so there is no widget to find and we assert
  /// on the call state instead. Until that screen goes away again the app
  /// draws no frames, so nothing may pump in the meantime.
  ///
  /// Stops waiting once [caller] reports its call ended, since nothing can
  /// ring after that.
  Future<void> waitForIncomingCallToRing({
    required BaresipClient caller,
  }) async {
    await tester.waitUntilWithoutPumping(
      () => _callerState is Ringing || caller.hasSeenCallClosed,
      timeout: _incomingCallTimeout,
      reason:
          'The app should ring for the call placed by baresip. Nothing came in '
          'within ${_incomingCallTimeout.inSeconds}s. '
          'Check that baresip registered and that it dialled a number that '
          'routes to the app account of the logged in test user '
          '(see ~/.baresip/baresip.log).',
    );

    if (_callerState is! Ringing) {
      throw TestFailure(
        "baresip's call ended before the app rang, with: "
        '${caller.callClosedReason}. The PBX could not reach the app, so '
        'check that the test user is available and rings in this app, and '
        'that the device receives pushes.',
      );
    }
  }

  /// Answers the ringing call.
  ///
  /// The answer button on the incoming call screen doesn't answer the call
  /// itself, it broadcasts an intent, so we broadcast that same intent. The
  /// screen closes itself once the call stops ringing.
  Future<void> answerIncomingCall() => _broadcastIncomingCallAction('ANSWER');

  /// Declines the ringing call by broadcasting the intent the decline button
  /// on the incoming call screen sends.
  Future<void> declineIncomingCall() => _broadcastIncomingCallAction('DECLINE');

  Future<void> _broadcastIncomingCallAction(String action) async {
    final packageName = (await PackageInfo.fromPlatform()).packageName;
    await AndroidIntent(
      action: action,
      package: packageName,
      componentName:
          'org.openvoipalliance.androidphoneintegration.service.NotificationButtonReceiver',
    ).sendBroadcast();
  }

  Future<void> waitForDeclinedCallToEnd() =>
      _waitForRingingToStop(because: 'the app declined it');

  /// For a call the caller gave up on before it was answered.
  Future<void> waitForMissedCallToEnd() =>
      _waitForRingingToStop(because: 'the caller hung up');

  Future<void> _waitForRingingToStop({required String because}) async {
    await tester.waitUntilWithoutPumping(
      () => !_callerState.isInCall,
      reason: 'The ringing call should end once $because',
    );
    await tester.waitUntilAppIsInFront();
    await tester.pump();

    expect(
      find.byType(CallPage),
      findsNothing,
      reason: 'The call screen should never appear for a call nobody answered',
    );
  }

  Future<void> waitForAnsweredCallToConnect() async {
    await tester.waitUntilWithoutPumping(
      () => _activeCall?.state == CallState.connected,
      reason: 'The answered call should connect',
    );
    await tester.waitUntilAppIsInFront();

    await tester.pumpUntilFound(
      find.byType(CallPage),
      reason: 'CallPage should appear after answering an incoming call',
      settle: false,
    );
  }

  void verifyCallIsIncoming() {
    expect(
      _activeCall?.direction.isInbound,
      isTrue,
      reason: 'The call placed by baresip should be an incoming call',
    );
  }

  CallerState get _callerState =>
      tester.element(find.byType(Navigator).first).read<CallerCubit>().state;

  Call? get _activeCall {
    final state = _callerState;
    return state is CallProcessState ? state.voipCall : null;
  }

  Future<void> verifyCallDuration() async {
    if (config.skipTestingCallMediaEstablished) {
      _verifyCallDurationIsZero();
    } else {
      await _verifyCallDurationIsIncreasing();
    }
  }

  Future<void> _verifyCallDurationIsIncreasing() async {
    final initialDuration = _currentCallDuration;

    await tester.pump(const Duration(seconds: 2));

    expect(
      _currentCallDuration,
      isNot(initialDuration),
      reason: 'Call duration should increase while connected',
    );
  }

  void _verifyCallDurationIsZero() {
    expect(
      _activeCall?.duration,
      0,
      reason:
          'On the iOS simulator the call connects but media does not '
          'establish, so the duration stays at 0',
    );
  }

  /// The duration is the last line of the call header.
  String get _currentCallDuration {
    final textFinder = find.descendant(
      of: find.byType(CallHeaderContainer),
      matching: find.byType(Text),
    );
    return tester.widget<Text>(textFinder.last).data ?? '';
  }

  Future<void> toggleMuteOnAndOff() => _toggleCallActionButton(
    tester.msg.main.call.ongoing.actions.mute,
    isActive: () =>
        _callerState is CallProcessState &&
        (_callerState as CallProcessState).isVoipCallMuted,
  );

  Future<void> toggleHoldOnAndOff() async {
    await _putCallOnHold();
    await _resumeCall();
  }

  Future<void> _putCallOnHold() => _setCallAction(
    tester.msg.main.call.ongoing.actions.hold,
    isActive: () => _activeCall?.isOnHold ?? false,
    active: true,
  );

  Future<void> _resumeCall() => _setCallAction(
    tester.msg.main.call.ongoing.actions.hold,
    isActive: () => _activeCall?.isOnHold ?? false,
    active: false,
  );

  /// Taps a call action button (e.g. mute or hold), verifies it becomes active,
  /// then taps it again and verifies it becomes inactive.
  Future<void> _toggleCallActionButton(
    String label, {
    required bool Function() isActive,
  }) async {
    await _setCallAction(label, isActive: isActive, active: true);
    await _setCallAction(label, isActive: isActive, active: false);
  }

  Future<void> _setCallAction(
    String label, {
    required bool Function() isActive,
    required bool active,
  }) async {
    _verifyCallActionIsActive(label, isActive: !active);

    await _tapCallActionButton(label);
    await _waitForCallAction(label, isActive: isActive, expected: active);
    _verifyCallActionIsActive(label, isActive: active);
  }

  Future<void> _tapCallActionButton(String label) async {
    await tester.tap(
      find.descendant(
        of: _callActionButton(label),
        matching: find.byType(InkResponse),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> _waitForCallAction(
    String label, {
    required bool Function() isActive,
    required bool expected,
  }) => tester.pumpUntil(
    () => isActive() == expected,
    reason: 'The call should ${expected ? 'be' : 'no longer be'} $label',
  );

  /// The button's semantic hint ends with whether it is on or off, which is
  /// what the button shows as well.
  void _verifyCallActionIsActive(String label, {required bool isActive}) {
    final hint = tester
        .widget<Semantics>(_callActionButton(label))
        .properties
        .hint;
    final status = isActive ? tester.msg.generic.on : tester.msg.generic.off;

    expect(
      hint?.endsWith(status),
      isTrue,
      reason: 'The $label button should be ${isActive ? 'active' : 'inactive'}',
    );
  }

  Finder _callActionButton(String label) => find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        (widget.properties.hint?.startsWith('$label.') ?? false),
  );

  /// The incoming call screen covers the app while ringing, so this must not
  /// pump.
  /// Sends [digits] as DTMF through the in-call keypad, then closes it.
  Future<void> sendDtmf(String digits) async {
    await _tapCallActionButton(
      tester.msg.main.call.ongoing.actions.keypad.label,
    );

    final onCallPage = find.byType(CallPage);
    for (final digit in digits.characters) {
      await tester.tap(_keypadButton(digit, within: onCallPage));
      await tester.pumpAndSettle();
    }

    await tester.tap(
      find.descendant(
        of: onCallPage,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is FaIcon && widget.icon == FontAwesomeIcons.xmark.data,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Switches the call to the speaker and back. With a Bluetooth device
  /// connected the button opens a picker instead of toggling.
  Future<void> toggleSpeakerOnAndOff() async {
    await _routeAudioTo(
      AudioRoute.speaker,
      label: tester.msg.main.call.ongoing.actions.audioRoute.speaker,
    );
    await _routeAudioTo(
      AudioRoute.phone,
      label: tester.msg.main.call.ongoing.actions.audioRoute.phone,
    );
  }

  Future<void> _routeAudioTo(AudioRoute route, {required String label}) async {
    final hasBluetooth =
        _audioState?.availableRoutes.contains(AudioRoute.bluetooth) ?? false;

    await tester.tap(_audioRouteButton);
    await tester.pumpAndSettle();

    if (hasBluetooth) {
      await tester.tap(
        find.descendant(
          of: find.byType(AudioRoutePicker),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    await tester.pumpUntil(
      () => _audioState?.currentRoute == route,
      reason: 'The call audio should be routed to the $route',
      settle: false,
    );
  }

  AudioState? get _audioState {
    final state = _callerState;
    return state is CallProcessState ? state.audioState : null;
  }

  /// Its icon and label change with the current route, but it is the only
  /// action button showing one of these icons.
  Finder get _audioRouteButton => find.ancestor(
    of: find.byWidgetPredicate(
      (widget) =>
          widget is FaIcon &&
          (widget.icon == FontAwesomeIcons.volume.data ||
              widget.icon == FontAwesomeIcons.bluetooth.data ||
              widget.icon == FontAwesomeIcons.phone.data),
    ),
    matching: find.byType(InkResponse),
  );

  /// Does an attended transfer of the current call to [number]: the call is
  /// put on hold, [number] is called, and once it answers both are merged so
  /// the app drops out.
  Future<void> transferTo(String number) async {
    await _tapCallActionButton(
      tester.msg.main.call.ongoing.actions.transfer.label,
    );
    await tester.pumpUntilFound(
      find.byType(CallTransfer),
      reason: 'The transfer keypad should open',
    );

    final onTransferPage = find.byType(CallTransfer);
    for (final char in number.characters) {
      if (char == '+') {
        await tester.longPress(_keypadButton('0', within: onTransferPage));
      } else {
        await tester.tap(_keypadButton(char, within: onTransferPage));
      }
      await tester.pumpAndSettle();
    }

    await tester.tap(
      find.descendant(of: onTransferPage, matching: find.byType(CallButton)),
    );
    await tester.pump();

    await tester.pumpUntil(
      () =>
          _callerState is AttendedTransferStarted &&
          _activeCall?.state == CallState.connected,
      timeout: const Duration(seconds: 60),
      reason: 'The transfer target $number should answer',
      settle: false,
    );

    await _tapCallActionButton(tester.msg.main.call.ongoing.actions.merge);

    await tester.pumpUntil(
      () => !_callerState.isInCall,
      reason: 'The app should drop out of the call once it is merged',
      settle: false,
    );
  }

  Future<void> ringFor(Duration duration) => Future.delayed(duration);

  Future<void> waitFor(Duration duration) => tester.pumpFor(duration);

  Future<void> tapHangUpButton() async {
    final hangUpHint = tester.msg.main.call.ongoing.hangUp;
    await tester.tap(
      find.descendant(
        of: find.byType(CallPage),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CallButton && widget.semanticsHint == hangUpHint,
        ),
      ),
    );
    await tester.pump();
  }

  /// The call screen stays up briefly to show that the call ended.
  Future<void> verifyCallScreenIsDismissed() => tester.pumpUntilGone(
    find.byType(CallPage),
    reason: 'The call screen should be dismissed after hanging up',
  );

  Future<void> _tapKeypadButton(String digit) async {
    await tester.tap(_keypadButton(digit));
    await tester.pumpAndSettle();
  }

  Future<void> _longPressKeypadButton(String digit) async {
    await tester.longPress(_keypadButton(digit));
    await tester.pumpAndSettle();
  }

  Finder _keypadButton(String digit, {Finder? within}) {
    final button = find.byWidgetPredicate(
      (widget) => widget is KeypadValueButton && widget.primaryValue == digit,
    );
    return within == null
        ? button
        : find.descendant(of: within, matching: button);
  }
}
