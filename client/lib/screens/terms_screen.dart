import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../constants/terms_text.dart';
import '../providers/app_state.dart';
import '../utils/legal_links.dart';
import '../widgets/echo_widgets.dart';
import 'entry_screen.dart';

/// Terms and Conditions.
///  - readOnly = false: the gate shown right after sign-up / login. Nobody can use Echo until they accept.
///  - readOnly = true : the same text, opened from Settings, with just a close button.
class TermsScreen extends StatefulWidget {
  final bool readOnly;
  const TermsScreen({super.key, this.readOnly = false});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _agreed = false;
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    if (!_agreed || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final appState = Provider.of<AppState>(context, listen: false);
    final error = await appState.acceptTerms();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    // On success AppState tells the home page, which then replaces this screen with the app.
  }

  void _decline() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Leave Echo?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'You need to accept the Terms and Conditions to use Echo. If you decline, you will be signed out.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Go back', style: TextStyle(color: AppColors.primaryLight)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              final appState = Provider.of<AppState>(context, listen: false);
              appState.logout();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const EntryScreen()),
                (route) => false,
              );
            },
            child: const Text('Decline and sign out', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Widget _paragraph(String text) {
    final bullet = text.startsWith('\u2022');
    return Padding(
      padding: EdgeInsets.only(left: bullet ? 8 : 0, bottom: 7),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 18, 4),
                child: Row(
                  children: [
                    if (widget.readOnly)
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                      )
                    else
                      const SizedBox(width: 10),
                    const IconTile(icon: Icons.gavel_rounded, colors: [Color(0xFF4C7DFF), Color(0xFF7A5CFF)], size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Terms and Conditions',
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 19, fontWeight: FontWeight.w800)),
                          Text('Version ${TermsText.version}  |  Updated ${TermsText.updated}',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!widget.readOnly)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Please read and accept the Terms to start using Echo.',
                      style: TextStyle(color: AppColors.primaryLight, fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),

              // The text
              Expanded(
                child: Scrollbar(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                    children: [
                      GlassCard(
                        borderColor: AppColors.primary,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('The short version',
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            for (final k in TermsText.keyPoints)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Icon(Icons.check_circle_rounded, color: AppColors.success, size: 16),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(k,
                                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.4)),
                                    ),
                                  ],
                                ),
                              ),
                            const Text('This summary is only a guide. The full Terms below are what count.',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (final s in TermsText.sections) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 6),
                          child: Text(s.title,
                              style: const TextStyle(color: AppColors.primaryLight, fontSize: 15, fontWeight: FontWeight.w800)),
                        ),
                        for (final p in s.paragraphs) _paragraph(p),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => openLegalPage(context, TermsText.pageName),
                            child: const Text('Open the Terms in your browser'),
                          ),
                          TextButton(
                            onPressed: () => openLegalPage(context, 'privacy_policy.html'),
                            child: const Text('Read the Privacy Policy'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Accept / decline (not shown when only reading)
              if (!widget.readOnly)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: AppColors.cardBorder.withOpacity(0.6))),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: _busy ? null : () => setState(() => _agreed = !_agreed),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: _agreed,
                                activeColor: AppColors.primary,
                                onChanged: _busy ? null : (v) => setState(() => _agreed = v ?? false),
                              ),
                              const Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(top: 11),
                                  child: Text(
                                    'I am 18 years or older. I have read and I agree to the Terms and Conditions and the Privacy Policy.',
                                    style: TextStyle(color: AppColors.textPrimary, fontSize: 12.5, height: 1.4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                        ),
                      GradientButton(
                        label: 'Accept and continue',
                        trailingIcon: Icons.arrow_forward,
                        busy: _busy,
                        onPressed: _agreed ? _accept : null,
                      ),
                      TextButton(
                        onPressed: _busy ? null : _decline,
                        child: const Text('Decline', style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
