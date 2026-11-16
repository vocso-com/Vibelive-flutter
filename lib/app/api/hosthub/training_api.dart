import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'training_models.dart';

/// `/host-onboarding/*` (docs/host_onboarding.md): the training setup for
/// the signed-in user, and their video and quiz results.
abstract final class HostTrainingApi {
  /// The setup with this user's progress. An older backend (404) means none.
  static Future<HostTrainingConfig> fetch() async {
    final Object? body;
    try {
      body = await ApiClient.get('/host-onboarding/config');
    } on ApiException catch (e) {
      if (e.statusCode == 404) return HostTrainingConfig.none;
      rethrow;
    }
    return HostTrainingConfig.from(body);
  }

  /// The video step was finished ([completed]), skipped, or left for the
  /// next step. [seconds]: how far it got.
  static Future<TrainingProgress> watched(
    String stepId, {
    required int seconds,
    bool completed = false,
    bool skipped = false,
  }) async {
    final body = await ApiClient.post(
      '/host-onboarding/steps/${Uri.encodeComponent(stepId)}/watched',
      data: {'seconds': seconds, 'completed': completed, 'skipped': skipped},
    );
    return TrainingProgress.from(body is Map ? body['progress'] : null);
  }

  /// One quiz attempt: `{questionId: [optionId, ...]}`, graded by the server.
  static Future<QuizResult> submitQuiz(
    String stepId,
    Map<String, List<String>> answers,
  ) async {
    final body = await ApiClient.post(
      '/host-onboarding/steps/${Uri.encodeComponent(stepId)}/quiz',
      data: {'answers': answers},
    );
    return QuizResult.from(body);
  }
}
