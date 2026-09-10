class FeedbackSubmission {
  final String subject;
  final String message;
  final int? rating;

  const FeedbackSubmission({
    required this.subject,
    required this.message,
    this.rating,
  });
}
