import 'dart:async';

import 'package:chopper/chopper.dart' hide JsonConverter;
import 'package:injectable/injectable.dart';

import '../../../domain/usecases/voipgrid/get_voipgrid_base_url.dart';
import '../../models/user/user.dart';
import '../util.dart';

part 'voipgrid_service.chopper.dart';

@ChopperApi(baseUrl: '/api/')
@singleton
abstract class VoipgridService extends ChopperService {
  @factoryMethod
  static VoipgridService create() {
    final getVoipgridBaseUrl = GetVoipgridBaseUrlUseCase();

    return _$VoipgridService(
      ChopperClient(
        baseUrl: Uri.parse(getVoipgridBaseUrl()),
        converter: JsonConverter(),
        interceptors: [
          TrailingSlashRequestInterceptor(),
          const AuthorizationInterceptor(
            forcedLegacyAuthPaths: [
              'v2/password',
            ],
          ),
          UnauthorizedResponseInterceptor(),
          RateLimitReachedInterceptor(),
          ...globalInterceptors,
        ],
      ),
    );
  }

  static VoipgridService createInIsolate({
    required User user,
    required String baseUrl,
  }) {
    return _$VoipgridService(
      ChopperClient(
        baseUrl: Uri.parse(baseUrl),
        converter: JsonConverter(),
        interceptors: [
          TrailingSlashRequestInterceptor(),
          AuthorizationInterceptor(user: user),
        ],
      ),
    );
  }

  @POST(path: 'permission/apitoken')
  Future<Response<Map<String, dynamic>>> getToken(
    @Body() Map<String, dynamic> body,
  );

  @GET(path: 'permission/systemuser/profile')
  Future<Response<Map<String, dynamic>>> getSystemUser({
    @Header('Authorization') String? authorization,
  });

  @POST(path: 'permission/password_reset')
  Future<Response<Map<String, dynamic>>> requestNewPassword(
    @Body() Map<String, dynamic> body,
  );

  @GET(path: 'v2/call/personalized')
  Future<Response<List<dynamic>>> getPersonalCalls({
    @Query('answered') bool? answered,
    @Query('timezone') String? timezone,
    @Query('from.type') String? fromType,
    @Query('to.type') String? toType,
    @Query('page') int pageNumber = 1,
    @Query('per_page') int perPage = 20,
  });

  @GET(path: 'v2/call/non-personalized')
  Future<Response<List<dynamic>>> getCalls({
    @Query('answered') bool? answered,
    @Query('timezone') String? timezone,
    @Query('page') int pageNumber = 1,
    @Query('per_page') int perPage = 20,
  });

  @GET(path: 'v2/callthrough')
  Future<Response<Map<String, dynamic>>> callthrough({
    @Query('destination') required String destination,
  });

  @PUT(path: 'v2/password')
  Future<Response<Map<String, dynamic>>> password(
    @Body() Map<String, dynamic> body,
  );

  @GET(path: 'autologin/token')
  Future<Response<Map<String, dynamic>>> getAutoLoginToken();

  @GET(path: 'userdestination')
  Future<Response<Map<String, dynamic>>> getAvailability();

  @PUT(path: 'selecteduserdestination/{id}')
  Future<Response<Map<String, dynamic>>> setAvailability(
    @Path() String id,
    @Body() Map<String, dynamic> body,
  );

  @GET(path: 'phoneaccount/basic/phoneaccount/{id}')
  Future<Response<Map<String, dynamic>>> getPhoneAccount(@Path() String id);

  @GET(path: 'mobile/profile')
  Future<Response<Map<String, dynamic>>> getMobileProfile();

  @GET(path: 'webphone/user/selected_account')
  Future<Response<Map<String, dynamic>>> getWebphoneSelectedAccount();

  @PUT(path: 'mobile/profile')
  Future<Response<Map<String, dynamic>>> updateMobileProfile(
    @Body() Map<String, dynamic> body,
  );

  @PUT(path: 'permission/mobile_number')
  Future<Response<Map<String, dynamic>>> changeMobileNumber(
    @Body() Map<String, dynamic> body,
  );

  @GET(path: 'v2/vialer/middlewares')
  Future<Response<Map<String, dynamic>>> getMiddleware();

  @GET(path: 'cdr/record')
  Future<Response<Map<String, dynamic>>> getClientCalls({
    @Query('limit') int limit = 20,
    @Query('offset') int offset = 0,
    @Query('call_date__gt') String? from,
    @Query('call_date__lt') String? to,
  });

  @GET(path: 'v2/clients/{clientId}/users/{userId}')
  Future<Response<Map<String, dynamic>>> getUserSettings({
    @Path() required String clientId,
    @Path() required String userId,
  });

  @GET(path: 'v2/user/details')
  Future<Response<Map<String, dynamic>>> getUserDetails();

  @PATCH(path: 'v2/clients/{clientId}/users/{userId}')
  Future<Response<Map<String, dynamic>>> updateUserSettings({
    @Path() required String clientId,
    @Path() required String userId,
    @Body() required Map<String, dynamic> body,
  });

  @GET(
    path: 'v2/clients/{clientUuid}/callerid_numbers',
    headers: {'Accept': 'application/json;version=2'},
  )
  Future<Response<Map<String, dynamic>>> getClientBusinessNumbers({
    @Path() required String clientUuid,
    @Query('page') int page = 1,
    @Query('per_page') int perPage = 500,
  });

  @PATCH(path: 'v2/clients/{clientId}/voip_accounts/{voipAccountId}')
  Future<Response<Map<String, dynamic>>> updateVoipAccount(
    @Path() String clientId,
    @Path() String voipAccountId,
    @Body() Map<String, dynamic> data,
  );

  @GET(path: 'v2/clients/{clientId}/voicemails')
  Future<Response<Map<String, dynamic>>> getVoicemailAccounts(
    @Path() String clientId, {
    @Query() int page = 1,
    @Query('per_page') int perPage = 500,
  });

  @GET(path: 'v2/users/auth-context')
  Future<Response<Map<String, dynamic>>> getVoipgridPermissions();

  @GET(path: 'v2/clients/{clientId}/users')
  Future<Response<List<dynamic>>> getUsers(
    @Path() String clientId, {
    @Query() int page = 1,
    @Query('per_page') int perPage = 500,
  });

  @GET(path: 'v2/clients/{clientId}/voip_accounts')
  Future<Response<List<dynamic>>> getUnconnectedVoipAccounts(
    @Path() String clientId, {
    @Query() int page = 1,
    @Query('per_page') int perPage = 500,
    @Query('filter_accounts') String filter = 'without_connected_users',
  });
}
