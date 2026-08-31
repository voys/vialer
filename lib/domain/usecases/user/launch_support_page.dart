import 'dart:async';

import 'package:url_launcher/url_launcher_string.dart';
import 'package:vialer/data/models/user/brand.dart';
import 'package:vialer/data/repositories/onboarding/country_repository.dart';
import 'package:vialer/presentation/features/onboarding/controllers/mobile_number/country_field/cubit.dart';

import '../../../data/repositories/metrics/metrics.dart';
import '../../../dependency_locator.dart';
import '../feedback/gleap/open_gleap_feedback_form.dart';
import '../use_case.dart';
import 'get_brand.dart';

class LaunchSupportPage extends UseCase {
  late final _getBrand = GetBrand();
  late final _metricsRepository = dependencyLocator<MetricsRepository>();
  late final _countryRepository = dependencyLocator<CountryRepository>();
  late final _openGleapFeedbackForm = OpenGleapFeedbackForm();

  bool get isAvailable =>
      _getBrand().hasSupportUrl || _openGleapFeedbackForm.isAvailable;

  void call() => unawaited(_call());

  Future<void> _call() async {
    final brand = _getBrand();

    if (_openGleapFeedbackForm.isAvailable) {
      await _openGleapFeedbackForm();
      return;
    }

    if (!brand.hasSupportUrl) {
      throw Exception('${brand.appName} has no support URL configured');
    }

    final countries = await _countryRepository.getCountries();

    final country = await countries.getPreferredCurrentCountry();

    final url = brand.supportUrlForCountry(country.isoCode);

    if (url == null) {
      throw Exception('${brand.appName} has no support URL configured');
    }

    await launchUrlString(url.toString());

    _metricsRepository.track('support-page-launched', {'url': url.toString()});
  }
}

extension on Brand {
  Uri? supportUrlForCountry(String isoCode) {
    if (isoCode != 'NL') return supportUrl;

    if (supportUrlNL == null) return supportUrl;

    return supportUrlNL;
  }
}
