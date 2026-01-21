import 'package:chopper/chopper.dart' hide JsonConverter;
import 'package:injectable/injectable.dart';

import '../../../../domain/usecases/user/get_brand.dart';
import '../../util.dart';

part 'availability_status_service.chopper.dart';

@ChopperApi()
@singleton
abstract class UserAvailabilityService extends ChopperService {
  @factoryMethod
  static UserAvailabilityService create() {
    final brand = GetBrand()();

    return _$UserAvailabilityService(
      ChopperClient(
        baseUrl: brand.availabilityServiceUrl,
        converter: JsonConverter(),
        interceptors: [
          const AuthorizationInterceptor(onlyModernAuth: true),
        ],
      ),
    );
  }

  @GET(path: 'clients/{clientUuid}/users/{userUuid}/status')
  Future<Response<Map<String, dynamic>>> getAvailabilityStatus({
    @Path() required String clientUuid,
    @Path() required String userUuid,
  });

  @POST(path: 'clients/{clientUuid}/users/{userUuid}/status')
  Future<Response<Map<String, dynamic>>> changeAvailabilityStatus(
    @Body() Map<String, dynamic> body, {
    @Path() required String clientUuid,
    @Path() required String userUuid,
  });
}
