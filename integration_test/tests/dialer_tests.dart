import 'package:vialer/data/models/relations/colleagues/colleague.dart';

import '../robots/dialer_robot.dart';
import '../utils/test_extensions.dart';

/// Only enters numbers, the call button is never pressed.
Future<void> runDialerTests(IntegrationTestContext context) async {
  final robot = DialerRobot(context.tester);

  // Read before opening the dialer, because the Android dialer page only
  // picks up the colleagues known at the moment it opens.
  final colleague = await robot.waitForAColleagueToSearchFor();

  await robot.openDialer();
  await robot.clearAnyPrefilledNumber();

  await _userCanEnterAndDeleteDigits(robot);
  await _userCanEnterAPlusByLongPressingZero(robot);
  await _userCanFindAColleagueWithT9(robot, colleague);
  await _userCanEnterTheNumberOnTheClipboard(robot);

  await robot.closeDialer();
}

Future<void> _userCanEnterAndDeleteDigits(DialerRobot robot) async {
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
