enum PermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  undetermined,

  /// A limited permissions means the user has granted access to a specific set
  /// of records. This is most commonly used for photos but can also be used for
  /// contacts (at least on iOS).
  ///
  /// This should be treated as much as possible as a granted permission, but
  /// we may want to display alternative UI to inform the user why they may
  /// not have access to all records.
  limited;

  bool get wasGranted =>
      this == PermissionStatus.granted || this == PermissionStatus.limited;

  bool get wasDenied => !wasGranted;
}
