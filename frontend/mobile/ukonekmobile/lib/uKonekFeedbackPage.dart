import 'package:flutter/material.dart';
import 'services/api_service.dart';

// ── Medical/Dental Green Design tokens ────────────────────────────────
class _C {
  static const primary    = Color(0xFF1B5E20);   // Deep Forest Green
  static const primaryMid = Color(0xFF28A745);   // Vibrant Health Green
  static const accent     = Color(0xFF20C997);   // Mint Accent
  static const bg         = Color(0xFFF8FCF9);   // Mint-tinted Background
  static const surface    = Colors.white;
  static const textDark   = Color(0xFF1B2E1E);   // Dark Forest Charcoal
  static const textMuted  = Color(0xFF637367);   // Muted Sage
  static const divider    = Color(0xFFE2E9E3);   // Light Mist Divider
  static const success    = Color(0xFF28A745);
  static const warning    = Color(0xFFF59E0B);
  static const shadow     = Color(0x0A000000);
}

class uKonekFeedbackPage extends StatefulWidget {
  const uKonekFeedbackPage({super.key});

  @override
  State<uKonekFeedbackPage> createState() => _uKonekFeedbackPageState();
}

class _uKonekFeedbackPageState extends State<uKonekFeedbackPage> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();

  bool _isSubmitting = false;
  int _selectedRating = 5;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      await ApiService.submitCitizenFeedback(
        FeedbackSubmission(
          subject: _subjectController.text,
          message: _messageController.text,
          rating: _selectedRating,
        ),
      );

      if (!mounted) return;
      _showSuccessDialog();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Feedback Sent', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Thank you! Your feedback helps us improve our dental services.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Return to previous page
            },
            child: const Text('GREAT', style: TextStyle(color: _C.primaryMid, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFormCard(),
                    const SizedBox(height: 24),
                    _buildRatingSection(),
                    const SizedBox(height: 32),
                    _buildSubmitButton(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_C.primary, _C.primaryMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Patient Feedback',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.4)),
                    SizedBox(height: 2),
                    Text('Share your clinic experience', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How was your visit?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _C.textDark)),
          const SizedBox(height: 18),
          TextFormField(
            controller: _subjectController,
            textInputAction: TextInputAction.next,
            maxLength: 120,
            style: const TextStyle(fontSize: 14, color: _C.textDark),
            decoration: _inputDecoration('Subject (e.g. Dental Service, Waiting Time)'),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return 'Subject is required';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _messageController,
            maxLines: 5,
            maxLength: 1000,
            style: const TextStyle(fontSize: 14, color: _C.textDark),
            decoration: _inputDecoration('Write your detailed feedback here...'),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return 'Message is required';
              if (text.length < 10) return 'Please add a bit more detail';
              return null;
            },
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _C.textMuted, fontSize: 13),
      filled: true,
      fillColor: _C.bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.all(16),
    );
  }

  Widget _buildRatingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text('Rate your experience', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _C.textDark)),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(5, (index) {
            final rating = index + 1;
            final isSelected = _selectedRating == rating;
            return GestureDetector(
              onTap: () => setState(() => _selectedRating = rating),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 58, height: 58,
                decoration: BoxDecoration(
                  color: isSelected ? _C.primaryMid : _C.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [BoxShadow(color: _C.shadow, blurRadius: 10, offset: Offset(0, 4))],
                  border: Border.all(color: isSelected ? _C.primaryMid : _C.divider, width: 2),
                ),
                child: Center(
                  child: Text(
                    '$rating',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : _C.textDark,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitFeedback,
        style: ElevatedButton.styleFrom(
          backgroundColor: _C.primaryMid,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          disabledBackgroundColor: _C.divider,
        ),
        child: _isSubmitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('SUBMIT FEEDBACK', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ),
    );
  }
}