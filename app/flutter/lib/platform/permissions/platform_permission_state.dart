/// Platform permission state used by future capability adapters.
///
/// Phase 0 does not request any permission. The enum exists so adapters and UI
/// can distinguish denial from absence when permission handling begins.
enum PlatformPermissionState {
  /// Permission has not been requested.
  notRequested,

  /// The user granted access.
  granted,

  /// The user denied access for this session.
  denied,

  /// The operating system will not prompt again; the user must open settings.
  permanentlyDenied,

  /// The permission is not applicable to this platform.
  notApplicable,
}
