import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/event/event_bus.dart';
import '../../dependency_locator.dart';
import 'loggable.dart';

/// Tracks stream subscriptions and cancels them when the cubit is closed, so
/// closed cubits don't keep reacting to events.
///
/// Also makes [emit] safe to call after the cubit has been closed, dropping
/// the state rather than throwing a [StateError]. In-flight async methods
/// can't be cancelled by [close], so they would otherwise crash when
/// resuming after the cubit is gone (e.g. a request completing after the
/// user has logged out).
mixin CubitSubscriptions<State> on BlocBase<State> {
  final _subscriptions = <StreamSubscription<void>>[];

  EventBusObserver get _eventBus => dependencyLocator<EventBusObserver>();

  /// Handles every [T] broadcast on the event bus, automatically cancelled
  /// when the cubit is closed.
  void onEventUntilCubitClosed<T extends EventBusEvent>(
    void Function(T event) handler,
  ) => _subscriptions.add(_eventBus.on<T>(handler));

  /// Listens to [stream], automatically cancelled when the cubit is closed.
  void listenUntilCubitClosed<T>(
    Stream<T> stream,
    void Function(T data) onData,
  ) => _subscriptions.add(stream.listen(onData));

  @override
  void emit(State state) {
    if (isClosed) {
      logger.info('Dropped $runtimeType state emitted after close');
      return;
    }

    super.emit(state);
  }

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await super.close();
  }
}
