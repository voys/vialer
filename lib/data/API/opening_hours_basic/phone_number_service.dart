import 'package:chopper/chopper.dart' hide JsonConverter;
import 'package:injectable/injectable.dart';

import '../../../domain/usecases/user/get_brand.dart';
import '../util.dart';

part 'phone_number_service.chopper.dart';

@ChopperApi()
@singleton
abstract class PhoneNumberService extends ChopperService {
  @factoryMethod
  static PhoneNumberService create() => _$PhoneNumberService(
        ChopperClient(
          baseUrl: Uri.parse(GetBrand()().phoneNumberValidationUrl.toString()),
          converter: JsonConverter(),
          interceptors: [
            const AuthorizationInterceptor(onlyModernAuth: true),
            ...globalInterceptors,
          ],
        ),
      );

  @GET(path: 'normalise/{number}')
  Future<Response<Map<String, dynamic>>> validate(
    @Path('number') String number, {
    @Query('accept_extension') bool acceptExtension = true,
  });
}
