import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vialer/data/models/colltacts/colltact.dart';
import 'package:vialer/data/models/colltacts/t9_colltact.dart';
import 'package:vialer/data/models/relations/colleagues/colleague.dart';
import 'package:vialer/data/repositories/relations/colleagues/colleagues_repository.dart';
import 'package:vialer/dependency_locator.dart';
import 'package:vialer/presentation/features/dialer/controllers/t9/riverpod.dart';
import 'package:vialer/presentation/features/dialer/controllers/t9/state.dart'
    show ColltactsLoaded;
import 'package:vialer/presentation/features/dialer/dialer_page.dart';
import 'package:vialer/presentation/features/dialer/widgets/t9/widget.dart';
import 'package:vialer/presentation/features/main_page.dart';
import 'package:vialer/presentation/shared/widgets/dial_pad/key_input.dart';
import 'package:vialer/presentation/shared/widgets/dial_pad/keypad.dart';

import '../utils/test_extensions.dart';
import 'integration_test_robot.dart';

class DialerRobot extends IntegrationTestRobot {
  DialerRobot(super.tester);

  static const _colleaguesTimeout = Duration(seconds: 60);

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

    await tester.pumpUntilHittable(
      find.byType(KeyInput),
      reason: 'The dialer should open',
    );
    expect(find.byType(DialerPage), findsOneWidget);
  }

  /// There is no back button on the Android dialer page, so the system back
  /// is used, as a user would.
  Future<void> closeDialer() async {
    if (Platform.isIOS) {
      await tester.navigateToContactsTab();
    } else {
      await tester.binding.handlePopRoute();
      await tester.pumpUntilGone(
        find.byType(DialerPage),
        reason: 'Going back should close the dialer',
      );
    }

    ensureOnHomeScreen();
  }

  String get enteredNumber => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byType(KeyInput),
          matching: find.byType(EditableText),
        ),
      )
      .controller
      .text;

  void verifyEnteredNumber(String expected) {
    expect(
      enteredNumber,
      expected,
      reason: 'The dialer should show the number that was entered',
    );
  }

  Future<void> enterDigits(String digits) async {
    for (final digit in digits.characters) {
      await tester.tap(_keypadButton(digit));
      await tester.pumpAndSettle();
    }
  }

  Future<void> enterPlusByLongPressingZero() async {
    await tester.longPress(_keypadButton('0'));
    await tester.pumpAndSettle();
  }

  Future<void> deleteLastDigit() async {
    await tester.tap(_deleteButton);
    await tester.pumpAndSettle();
  }

  Future<void> deleteAllDigits() async {
    await tester.longPress(_deleteButton);
    await tester.pumpAndSettle();
  }

  /// The dialer can open with the last dialled number already filled in.
  Future<void> clearAnyPrefilledNumber() async {
    if (enteredNumber.isNotEmpty) await deleteAllDigits();
    verifyEnteredNumber('');
  }

  Finder _keypadButton(String value) => find.byWidgetPredicate(
    (widget) => widget is KeypadValueButton && widget.primaryValue == value,
  );

  Finder get _deleteButton => find.descendant(
    of: find.byType(KeyInput),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.hint == tester.msg.main.dialer.button.delete.hint,
    ),
  );

  /// Colleagues arrive over the WebSocket some time after logging in, and the
  /// dialer only picks up the ones that are known when it opens.
  Future<Colleague> waitForAColleagueToSearchFor() async {
    Colleague? colleague;

    await tester.pumpUntil(
      () => (colleague = _findColleagueToSearchFor()) != null,
      timeout: _colleaguesTimeout,
      reason:
          'A colleague with a phone number and a name starting with at least '
          '3 plain letters should be known within '
          '${_colleaguesTimeout.inSeconds}s, to search for with T9',
    );

    return colleague!;
  }

  Colleague? _findColleagueToSearchFor() {
    for (final colleague
        in dependencyLocator<ColleaguesRepository>().getColleaguesFromCache()) {
      final number = colleague.number;
      if (number == null || number.trim().isEmpty) continue;
      if (_t9LettersOf(colleague.name).length >= 3) return colleague;
    }
    return null;
  }

  /// On iOS the dialer tab is built right after logging in, often before
  /// colleagues arrive over the websocket, so this also checks the search
  /// picks them up once they do.
  Future<void> waitForT9SearchToKnow(Colleague colleague) => tester.pumpUntil(
    () => _t9Colltacts.any((colltact) => _isColleague(colltact, colleague)),
    reason: 'The T9 search should include ${colleague.name}',
  );

  /// Types the keys that match the start of the colleague's name, the way T9
  /// matches names.
  Future<void> enterT9DigitsForNameOf(Colleague colleague) =>
      enterDigits(_t9LettersOf(colleague.name).map(_t9DigitFor).join());

  Future<void> verifyColleagueIsSuggested(Colleague colleague) async {
    await tester.pumpUntil(
      () => _t9Suggestions.any(
        (suggestion) => _isColleague(suggestion.colltact, colleague),
      ),
      reason: 'Typing the T9 digits should suggest ${colleague.name}',
    );

    await tester.scrollUntilVisible(
      _suggestionFor(colleague),
      50,
      scrollable: find
          .descendant(
            of: find.byType(T9ColltactsListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }

  Future<void> tapSuggestedColleague(Colleague colleague) async {
    await tester.tap(_suggestionFor(colleague));
    await tester.pumpAndSettle();
  }

  /// Matched on number as well, since a contact on the device can have the
  /// same name.
  Finder _suggestionFor(Colleague colleague) => find
      .descendant(
        of: find.byType(T9ColltactsListView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ListTile &&
              widget.title is Text &&
              (widget.title! as Text).data == colleague.name &&
              widget.subtitle is Text &&
              (widget.subtitle! as Text).data == colleague.number,
        ),
      )
      .first;

  ProviderContainer get _t9Container => ProviderScope.containerOf(
    tester.element(find.byType(DialerPage)),
    listen: false,
  );

  ColltactsLoaded? get _t9State {
    final state = _t9Container.read(t9ColltactsProvider);
    return state is ColltactsLoaded ? state : null;
  }

  List<Colltact> get _t9Colltacts => _t9State?.colltacts ?? const [];

  List<T9Colltact> get _t9Suggestions =>
      _t9State?.filteredColltacts ?? const [];

  bool _isColleague(Colltact colltact, Colleague colleague) =>
      colltact is ColltactColleague && colltact.colleague.id == colleague.id;

  /// T9 matches names with everything but letters and digits left out, so
  /// only the plain letters at the start of the name are used.
  List<String> _t9LettersOf(String name) {
    final letters = <String>[];
    for (final char in name.characters) {
      if (char == ' ') continue;
      if (!RegExp(r'^[a-zA-Z]$').hasMatch(char)) break;
      letters.add(char);
      if (letters.length == 6) break;
    }
    return letters;
  }

  String _t9DigitFor(String letter) => _t9Keys.entries
      .firstWhere((entry) => entry.value.contains(letter.toLowerCase()))
      .key;

  static const _t9Keys = {
    '2': 'abc',
    '3': 'def',
    '4': 'ghi',
    '5': 'jkl',
    '6': 'mno',
    '7': 'pqrs',
    '8': 'tuv',
    '9': 'wxyz',
  };

  Future<void> copyToClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  Future<void> clearClipboard() =>
      Clipboard.setData(const ClipboardData(text: ''));

  /// The dialer checks the clipboard when the app comes back to the front, as
  /// it would after copying a number elsewhere. The OS classifies the copied
  /// text in the background, so the check is repeated until it has.
  Future<void> returnToAppAndWaitForClipboardSuggestion() async {
    const timeout = Duration(seconds: 30);
    var elapsed = Duration.zero;

    while (!tester.any(_clipboardSuggestion)) {
      if (elapsed >= timeout) {
        throw TestFailure(
          'The dialer should suggest the phone number on the clipboard within '
          '${timeout.inSeconds}s',
        );
      }
      await _simulateReturningToTheApp();
      await tester.pumpFor(const Duration(seconds: 1));
      elapsed += const Duration(seconds: 1);
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapClipboardSuggestion() async {
    await tester.tap(_clipboardSuggestion);
    await tester.pumpAndSettle();
  }

  Future<void> verifyClipboardNumberIsEntered(String expected) =>
      tester.pumpUntil(
        () => enteredNumber == expected,
        reason: 'Tapping the suggestion should enter $expected',
      );

  Finder get _clipboardSuggestion =>
      find.text(tester.msg.main.dialer.clipboard.copyPhoneNumber.title);

  /// Briefly makes the app inactive, which keeps it drawing frames, unlike
  /// actually sending it to the background.
  Future<void> _simulateReturningToTheApp() async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            SystemChannels.lifecycle.name,
            SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
            (_) {},
          );
    }
  }
}
