import '../../../../core/network/api_exception.dart';
import 'host_steps.dart';
import 'validation.dart';

/// Maps a rejected submit (Strapi `ValidationError` with
/// `error.details.errors[].path`) to the onboarding step that owns the field,
/// so the flow can send the user back there with the message.
abstract final class HostSubmitErrors {
  static const _fieldSteps = <String, HostStep>{
    'handler': HostStep.basic,
    'name': HostStep.basic,
    'gender': HostStep.basic,
    'language': HostStep.basic,
    'state': HostStep.basic,
    'district': HostStep.basic,
    'mobile': HostStep.basic,
    'host_profile_images': HostStep.photos,
    'profilePic': HostStep.photos,
    'image': HostStep.photos,
    'selections': HostStep.interests,
    'tagline': HostStep.tagline,
    'descriptions': HostStep.bio,
    'rates': HostStep.rates,
    'voiceCallRate': HostStep.rates,
    'videoCallRate': HostStep.rates,
    'schedule': HostStep.availability,
    'callAnyTime': HostStep.availability,
    'vocationMode': HostStep.availability,
  };

  /// First rejected field the server named (`handler`, `tagline`, …).
  static String? _field(ApiException e) {
    final body = e.data;
    if (body is! Map) return null;
    final error = body['error'];
    final details = error is Map ? error['details'] : null;
    final errors = details is Map ? details['errors'] : null;
    if (errors is! List) return null;
    for (final item in errors) {
      final path = item is Map ? item['path'] : null;
      if (path is List) {
        for (final part in path) {
          final key = '$part';
          if (_fieldSteps.containsKey(key)) return key;
        }
      }
    }
    return null;
  }

  /// The account already has a host profile (409 `HOST_PROFILE_EXISTS`): the
  /// server refused a second one, which would have taken the account off it.
  static bool isProfileExists(ApiException e) {
    if (e.statusCode != 409) return false;
    final body = e.data;
    final error = body is Map ? body['error'] : null;
    final details = error is Map ? error['details'] : null;
    return details is Map && details['code'] == 'HOST_PROFILE_EXISTS';
  }

  /// The step to go back to, or null when the error isn't about a field.
  static HostStep? stepFor(ApiException e) {
    final field = _field(e);
    return field == null ? null : _fieldSteps[field];
  }

  /// What the step shows above Continue.
  static HostIssue noticeFor(ApiException e, HostStep step) {
    if (_field(e) == 'handler') {
      return (key: 'hostflow:errors.handle_taken', variables: null);
    }
    return (
      key: 'hostflow:errors.server',
      variables: {'message': e.serverMessage ?? ''},
    );
  }
}
