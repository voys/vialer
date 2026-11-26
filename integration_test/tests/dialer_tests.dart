import 'package:vialer/data/models/relations/colleagues/colleague.dart';

import '../robots/dialer_robot.dart';
import '../utils/test_extensions.dart';
import '../utils/test_log.dart';

/// Only enters numbers, the call button is never pressed.
Future<void> runDialerTests(IntegrationTestContext context) async {
  final robot = DialerRobot(context.tester);

  TestLog.group('🔢', 'Dialer');

  // Read before opening the dialer, because the Android dialer page only
  // picks up the colleagues known at the moment it opens.
  TestLog.step('⏳', 'Waiting for a colleague to search for with T9');
  final colleague = await robot.waitForAColleagueToSearchFor();

  await robot.openDialer();
  await robot.clearAnyPrefilledNumber();

  await TestLog.test(
    'User can enter and delete digits',
    () => _userCanEnterAndDeleteDigits(robot),
  );
  await TestLog.test(
    'User can enter a plus by long pressing zero',
    () => _userCanEnterAPlusByLongPressingZero(robot),
  );
  await TestLog.test(
    'User can find a colleague with T9',
    () => _userCanFindAColleagueWithT9(robot, colleague),
  );
  await TestLog.test(
    'User can enter the number on the clipboard',
    () => _userCanEnterTheNumberOnTheClipboard(robot),
  );

  await robot.closeDialer();
}

Future<void> _userCanEnterAndDeleteDigits(DialerRobot robot) async {
  TestLog.detail('Digits', '0123456789*#');
  await robot.enterDigits('0123456789*#');
  robot.verifyEnteredNumber('0123456789*#');

  await robot.deleteLastDigit();
  robot.verifyEnteredNumber('0123456789*');

  await robot.deleteAllDigits();
  robot.verifyEnteredNumber('');
}

Future<void> _userCanEnterAPlusByLongPressingZero(DialerRobot robot) async {
  await robot.enterPlusByLongPressingZero();
  await robot.enterDigits('31');
  robot.verifyEnteredNumber('+31');

  await robot.deleteAllDigits();
}

Future<void> _userCanFindAColleagueWithT9(
  DialerRobot robot,
  Colleague colleague,
) async {
  TestLog.detail('Colleague', colleague.name);
  TestLog.detail("Colleague's number", colleague.number);

  await robot.waitForT9SearchToKnow(colleague);

  await robot.enterT9DigitsForNameOf(colleague);
  await robot.verifyColleagueIsSuggested(colleague);

  await robot.tapSuggestedColleague(colleague);
  robot.verifyEnteredNumber(colleague.number!);

  await robot.deleteAllDigits();
}

/// A number from the range reserved for fiction, so it can never reach anyone
/// even if it were dialled.
const _clipboardNumber = '+44 20 7946 0123';

/// The dialer drops spaces and turns the leading `+` into `00`.
const _clipboardNumberAsEntered = '00442079460123';

Future<void> _userCanEnterTheNumberOnTheClipboard(DialerRobot robot) async {
  TestLog.detail('Number on the clipboard', _clipboardNumber);
  TestLog.detail('Expected to be entered as', _clipboardNumberAsEntered);

  try {
    await robot.copyToClipboard(_clipboardNumber);
    await robot.returnToAppAndWaitForClipboardSuggestion();

    await robot.tapClipboardSuggestion();
    await robot.verifyClipboardNumberIsEntered(_clipboardNumberAsEntered);
  } finally {
    await robot.clearClipboard();
  }

  await robot.deleteAllDigits();
}
