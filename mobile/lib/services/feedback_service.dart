import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class FeedbackService {
  FeedbackService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<void> submitCitizenFeedback(FeedbackSubmission feedback) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Please sign in before sending feedback.');

    final citizen = await _client.from('citizens').select('id, email').eq('auth_user_id', user.id).maybeSingle();

    final citizenId = (citizen?['id'] as num?)?.toInt();
    final citizenEmail = (citizen?['email'] as String?)?.trim();
    final fallbackEmail = user.email?.trim();
    final fromEmail = (citizenEmail?.isNotEmpty == true ? citizenEmail : fallbackEmail) ?? 'unknown@ukonek.local';

    await _client.from('feedbacks').insert({
      'citizen_id': citizenId,
      'from_email': fromEmail,
      'subject': feedback.subject.trim(),
      'message': feedback.message.trim(),
      'rating': feedback.rating,
    });
  }
}
