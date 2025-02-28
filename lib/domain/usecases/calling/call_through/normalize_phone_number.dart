import 'package:flutter_libphonenumber/flutter_libphonenumber.dart';
import 'package:injectable/injectable.dart';
import 'package:vialer/domain/usecases/use_case.dart';

@injectable
class NormalizePhoneNumber extends UseCase {
  Future<String?> call({
    required String number,
    required String? isoCode,
  }) async {
    if (isoCode == null) {
      final parsed = await parse(number);
      return parsed['e164'] as String?;
    }
    final regions = await getAllSupportedRegions();
    final country = regions[isoCode.toUpperCase()];
    if (country == null) return null;
    final result = await getFormattedParseResult(number, country);
    return result?.e164;
  }
}
