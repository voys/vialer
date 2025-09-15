import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:injectable/injectable.dart';

import '../../../models/user/connectivity/connectivity_type.dart';

@singleton
class ConnectivityRepository {
  Future<ConnectivityType> get currentType {
    return Connectivity()
        .checkConnectivity()
        .then((results) => results.toDomainEntity());
  }

  Stream<ConnectivityType> get statusStream {
    return Connectivity()
        .onConnectivityChanged
        .map((results) => results.toDomainEntity());
  }
}

extension ConnectivityTypeMapper on List<ConnectivityResult> {
  ConnectivityType toDomainEntity() {
    if (contains(ConnectivityResult.mobile)) {
      return ConnectivityType.mobile;
    }
    if (contains(ConnectivityResult.ethernet) ||
        contains(ConnectivityResult.wifi) ||
        contains(ConnectivityResult.vpn) ||
        contains(ConnectivityResult.other)) {
      return ConnectivityType.wifi;
    }
    return ConnectivityType.none;
  }
}
