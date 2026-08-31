import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart';
import 'package:vialer/domain/usecases/onboarding/logout_on_incomplete_onboarding.dart';
import 'package:vialer/domain/usecases/user/settings/import_legacy_settings.dart';
import 'package:vialer/presentation/util/global_bloc_provider.dart';
import 'package:vialer/presentation/util/screen_reader.dart';

import '../data/models/event/event_bus.dart';
import '../data/repositories/env.dart';
import '../data/repositories/error_tracking/error_tracking_repository.dart';
import '../dependency_locator.dart';
import '../domain/usecases/authentication/user_was_logged_out.dart';
import '../domain/usecases/call_records/client/purge_local_call_records.dart';
import '../domain/usecases/calling/voip/apply_destination_migration.dart';
import '../domain/usecases/event/register_event_listeners.dart';
import '../domain/usecases/feedback/gleap/initialize_gleap.dart';
import '../domain/usecases/metrics/initialize_metric_collection.dart';
import '../domain/usecases/metrics/periodically_identify_for_tracking.dart';
import '../domain/usecases/onboarding/apply_onboarding_migration.dart';
import '../domain/usecases/onboarding/should_onboard.dart';
import '../domain/usecases/remote_logging/enable_console_logging.dart';
import '../domain/usecases/remote_logging/enable_remote_logging_if_needed.dart';
import '../domain/usecases/user/get_stored_user.dart';
import '../domain/usecases/user/set_is_using_screen_reader.dart';
import '../domain/usecases/user/settings/disable_advanced_voip_logging.dart';
import 'features/main_page.dart';
import 'resources/localizations.dart';
import 'resources/theme.dart';
import 'routes.dart';
import 'shared/widgets/brand_provider/widget.dart';
import 'shared/widgets/build_error.dart';
import 'util/debug.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  initializeTimeZones();

  await initializeDependencies();
  await ImportLegacySettings()();

  ApplyOnboardingMigration()();
  unawaited(InitializeMetricCollection()());
  unawaited(InitializeGleap()());
  RegisterDomainEventListenersUseCase()();
  unawaited(EnableConsoleLoggingUseCase()());
  unawaited(EnableRemoteLoggingIfNeededUseCase()());
  MigrateDestinationObjectToIdentifier()();

  // Disable this whenever the app launches so we aren't letting users keep
  // this enabled indefinitely.
  unawaited(DisableAdvancedVoipLogging()());

  final errorTrackingRepository = dependencyLocator<ErrorTrackingRepository>();
  final dsn = dependencyLocator<EnvRepository>().errorTrackingDsn;
  final user = GetStoredUserUseCase()();

  unawaited(PeriodicallyIdentifyForTracking()());
  RemoveLegacyClientCallRecordsFile()();

  if (dsn.isEmpty) {
    runApp(const App());
  } else {
    await errorTrackingRepository.run(() => runApp(const App()), dsn, user);
  }
}

class App extends StatefulWidget {
  const App({super.key});

  static void navigateTo(MainPageTab tab) =>
      MainPage.keys.page.currentState!.navigateTo(tab);

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  final EventBusObserver _eventBus = dependencyLocator<EventBusObserver>();

  final _setIsUsingScreenReader = SetIsUsingScreenReader();

  @override
  void initState() {
    super.initState();
    _listenForEvents();
    LogoutOnIncompleteOnboarding()();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _setIsUsingScreenReader(context.isUsingScreenReader);
  }

  String get _initialRoute =>
      ShouldOnboard()() ? Routes.onboarding : Routes.main;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: BrandProvider(
        child: Builder(
          builder: (context) {
            return GlobalBlocProvider(
              navigatorKey: _navigatorKey,
              child: MaterialApp(
                navigatorKey: _navigatorKey,
                title: context.brand.appName,
                theme: context.brand.theme.themeData,
                initialRoute: _initialRoute,
                routes: Routes.mapped,
                localizationsDelegates: const [
                  VialerLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: VialerLocalizations.locales.map(Locale.new),
                // We get a route of `/` when opening the app from an intent
                // when the app has been killed. We will essentially catch this
                // unregistered route and redirect to [initialRoute].
                onUnknownRoute: (requestedRoute) {
                  // This prevents anything from being rebuilt when the app
                  // is already running.
                  if (requestedRoute.name != '/') return null;

                  return MaterialPageRoute(
                    builder: (context) => Routes.mapped[_initialRoute]!(
                      context,
                    ),
                    // Directly specifying settings will ensure the route
                    // doesn't get rebuilt again.
                    settings: RouteSettings(name: _initialRoute),
                  );
                },
                builder: (context, child) {
                  if (!inDebugMode) {
                    ErrorWidget.builder = (_) => const BuildError();
                  }

                  return child!;
                },
              ),
            );
          },
        ),
      ),
    );
  }

  /// Listen for any app-level events, these events should require a "global"
  /// response. For example, the user should be forced back to the onboarding
  /// screen whenever they are logged out.
  void _listenForEvents() => _eventBus.on<UserWasLoggedOutEvent>((event) {
    final context = _navigatorKey.currentContext;

    if (context == null) return;

    late Route<dynamic> currentRoute;

    Navigator.popUntil(context, (route) {
      currentRoute = route;
      return route.settings.name == Routes.onboarding;
    });

    // We check if we're already at the onboarding page, otherwise
    // a GlobalKey is used twice. It's possible to be logged out
    // while we're still onboarding. This will happen if the user starts
    // the app but didn't finish onboarding last time.
    if (currentRoute.settings.name == Routes.onboarding) return;

    unawaited(
      Navigator.pushNamedAndRemoveUntil(
        context,
        Routes.onboarding,
        (r) => false,
      ),
    );
  });
}
