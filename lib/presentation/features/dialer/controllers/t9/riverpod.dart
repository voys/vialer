import 'dart:async';
import 'dart:io';

import 'package:dartx/dartx.dart';
import 'package:diacritic/diacritic.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vialer/presentation/features/dialer/controllers/t9/state.dart';
import 'package:vialer/presentation/util/extensions.dart';

import '../../../../../../data/models/call_records/item.dart';
import '../../../../../../data/models/colltacts/colltact.dart';
import '../../../../../../data/models/colltacts/t9_colltact.dart';
import '../../../../../../data/models/event/event_bus.dart';
import '../../../../../../data/models/relations/colleagues/colleague.dart';
import '../../../../../../data/models/relations/events/colleague_list_did_change.dart';
import '../../../../../../data/models/user/permissions/permission.dart';
import '../../../../../../data/models/user/permissions/permission_status.dart';
import '../../../../../../domain/usecases/colltacts/get_contacts.dart';
import '../../../../../../domain/usecases/colltacts/shared_contacts/get_shared_contacts.dart';
import '../../../../../../domain/usecases/relations/colleagues/get_cached_colleagues.dart';
import '../../../../../../domain/usecases/user/get_permission_status.dart';
import '../../../../../dependency_locator.dart';

part 'riverpod.g.dart';

@Riverpod(keepAlive: true)
class T9Colltacts extends _$T9Colltacts {
  final _getContacts = GetContactsUseCase();
  final _getColleagues = GetCachedColleagues();
  final _getSharedContacts = dependencyLocator<GetSharedContactsUseCase>();
  final _getPermissionStatus = GetPermissionStatusUseCase();

  _T9SearchIndex? _searchIndex;
  int _latestFilterRequest = 0;
  int _latestLoad = 0;

  /// Name and number of every colleague in [_searchIndex], the only parts of
  /// a colleague T9 searches in.
  Set<(String, String?)>? _indexedColleagues;

  @override
  T9ColltactsState build() {
    final subscription = dependencyLocator<EventBusObserver>()
        .on<ColleagueListDidChangeEvent>(_onColleaguesChanged);
    ref.onDispose(subscription.cancel);

    return const T9ColltactsState.loading();
  }

  /// Colleagues arrive over the websocket, which can be after the dialer was
  /// built (it's a tab on iOS, built right after login), so the index has to
  /// follow along. The list is broadcast again on every availability change,
  /// so only rebuild when something T9 searches in changed.
  void _onColleaguesChanged(ColleagueListDidChangeEvent event) {
    final indexedColleagues = _indexedColleagues;
    if (indexedColleagues == null) return;

    if (setEquals(event.colleagues.searchable, indexedColleagues)) return;

    unawaited(_loadColltacts());
  }

  Future<void> loadColltactsIfAllowed() async {
    final status = await _getPermissionStatus(permission: Permission.contacts);

    if (status.wasGranted) {
      _loadColltacts();
    } else {
      state = T9ColltactsState.noPermission(
        dontAskAgain:
            status == PermissionStatus.permanentlyDenied ||
            (Platform.isIOS && status == PermissionStatus.denied),
      );
    }
  }

  Future<void> _loadColltacts() async {
    if (state is NoPermission) return;

    if (state is! ColltactsLoaded) {
      state = const T9ColltactsState.loading();
    }

    final load = ++_latestLoad;

    final contacts = await _getContacts(latest: false);
    final colleagues = await _getColleagues();
    final sharedContacts = await _getSharedContacts();

    _indexedColleagues = colleagues.searchable;

    final colltacts = [
      ...contacts.map(Colltact.contact),
      ...colleagues.map(Colltact.colleague),
      ...sharedContacts.map(Colltact.sharedContact),
    ];

    _T9SearchIndex? searchIndex;
    try {
      searchIndex = await compute(_buildSearchIndex, colltacts);
    } finally {
      // A load started after this one read fresher data, so this one must
      // not overwrite its results.
      if (load == _latestLoad) {
        _searchIndex = searchIndex;
        // Searches started before this load would otherwise overwrite the
        // fresh state with stale results once they complete.
        _latestFilterRequest++;
        // Show the colltacts even when indexing failed, instead of loading
        // forever.
        state = T9ColltactsState.loaded(colltacts, []);
      }
    }
  }

  Future<void> filter(String input) async {
    final request = ++_latestFilterRequest;

    // Necessary for auto cast.
    final state = this.state;

    if (state is NoPermission) return;

    if (state is ColltactsLoaded) {
      if (input.isEmpty) {
        this.state = T9ColltactsState.loaded(
          state.colltacts,
          [],
        );
        return;
      }

      final index = _searchIndex;
      if (index == null) return;

      // Only the search strings are sent to the isolate and only indices
      // come back, so the main thread doesn't copy all colltacts per key press.
      final matches = await compute(
        _findMatches,
        _FindMatchesRequest(
          names: index.names,
          numbers: index.numbers,
          regex: _getT9Regex(input),
        ),
      );

      // A newer key press has started its own search in the meantime.
      if (request != _latestFilterRequest) return;

      this.state = T9ColltactsState.loaded(
        state.colltacts,
        [for (final i in matches) index.entries[i]],
      );
    }
  }

  RegExp _getT9Regex(String input) {
    // Construct a regular expression that matches the digits (mapped to
    // characters) from the start of each word (aka first name and last name)
    // or digits everywhere in the phone number, ignoring white spaces.

    // For example, input 275 will match with regex:
    // (\b[abc][pqrs][jkl]|2[^0-9]*7[^0-9]*5[^0-9]*)

    final keyMap = {
      '1': '',
      '2': 'abc',
      '3': 'def',
      '4': 'ghi',
      '5': 'jkl',
      '6': 'mno',
      '7': 'pqrs',
      '8': 'tuv',
      '9': 'wxyz',
      '0': '',
    };

    // Ignore all characters except those allowed in a phone number. Also remove
    // the first 0 so we can properly match it against numbers with country
    // codes.
    final inputPhoneNumber = input
        .formatForPhoneNumberQuery()
        .replaceAll(RegExp('[^0-9]'), '')
        .replaceAllMapped(RegExp('.'), (m) => '${m[0]}[^0-9]*');

    // Ignore 0 and 1 for the name matching, they don't map to a character.
    var inputName = input.replaceAll(RegExp('[^2-9]'), '');
    if (inputName.isEmpty) {
      return RegExp(inputPhoneNumber, caseSensitive: false);
    }

    inputName = inputName.replaceAllMapped(
      RegExp('.'),
      (m) => '[${keyMap[m[0]]}]',
    );

    return RegExp('(\\b$inputName|$inputPhoneNumber)', caseSensitive: false);
  }
}

/// Maps each colltact with multiple phone numbers to multiple t9 colltacts
/// with a single phone number, and prepares the strings to search in. For a
/// large amount of colltacts this is heavy so it's designed to run in an
/// isolate, once per load.
_T9SearchIndex _buildSearchIndex(List<Colltact> colltacts) {
  final entries = colltacts
      .map(
        (colltact) => colltact.when(
          colleague: (colleague) => [
            T9Colltact(
              colltact: colltact,
              relevantPhoneNumber: Item(
                label: '',
                value: colleague.number ?? '',
              ),
            ),
          ],
          contact: (contact) => contact.phoneNumbers.map(
            (number) => T9Colltact(
              colltact: colltact,
              relevantPhoneNumber: number,
            ),
          ),
          sharedContact: (sharedContact) => sharedContact.phoneNumbers.map(
            (number) => T9Colltact(
              colltact: colltact,
              relevantPhoneNumber: Item(
                label: '',
                value: number.phoneNumberFlat,
              ),
            ),
          ),
        ),
      )
      .flatten()
      .distinct()
      .toList();

  return _T9SearchIndex(
    entries: entries,
    names: entries.map((t9) => t9.nameForT9Search).toList(),
    numbers: entries.map((t9) => t9.relevantPhoneNumber.value).toList(),
  );
}

/// Returns the indices of the entries whose name or number matches the regex.
List<int> _findMatches(_FindMatchesRequest request) => [
  for (var i = 0; i < request.names.length; i++)
    if (request.names[i].contains(request.regex) ||
        request.numbers[i].contains(request.regex))
      i,
];

class _T9SearchIndex {
  const _T9SearchIndex({
    required this.entries,
    required this.names,
    required this.numbers,
  });

  final List<T9Colltact> entries;
  final List<String> names;
  final List<String> numbers;
}

class _FindMatchesRequest {
  const _FindMatchesRequest({
    required this.names,
    required this.numbers,
    required this.regex,
  });

  final List<String> names;
  final List<String> numbers;
  final RegExp regex;
}

extension on T9Colltact {
  String get nameForT9Search => removeDiacritics(colltact.name).replaceAll(
    // Removing any of the characters a user can't input into the dialer or
    // that doesn't have a valid T9 mapping.
    RegExp('[^a-zA-Z0-9#+*]'),
    '',
  );
}

extension on Iterable<Colleague> {
  Set<(String, String?)> get searchable => {
    for (final colleague in this) (colleague.name, colleague.number),
  };
}
