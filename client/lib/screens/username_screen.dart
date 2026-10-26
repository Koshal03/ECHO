import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../constants/app_colors.dart';
import 'home_dashboard.dart';

class UsernameScreen extends StatefulWidget {
  /// True when arriving from Google Sign-In (a new Google account choosing its username).
  final bool viaGoogle;

  /// True when arriving from Email sign-in (a new, already verified email choosing its username).
  final bool viaEmailOtp;
  final String? suggestedName;
  const UsernameScreen({super.key, this.viaGoogle = false, this.viaEmailOtp = false, this.suggestedName});

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();

  bool _isChecking = false;
  bool _isAvailable = false;
  String _statusMessage = '';
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    final name = widget.suggestedName;
    if (widget.viaGoogle && name != null && name.isNotEmpty) _displayNameController.text = name;
  }

  Future<void> _checkAvailability(String val) async {
    if (val.trim().length < 4) {
      setState(() {
        _isAvailable = false;
        _statusMessage = 'Username must be at least 4 characters.';
        _suggestions = [];
      });
      return;
    }

    setState(() => _isChecking = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final res = await appState.checkUsernameAvailability(val.trim());

    if (mounted) {
      setState(() {
        _isChecking = false;
        _isAvailable = res['valid'] == true;
        _statusMessage = res['message'] ?? '';
        _suggestions = List<String>.from(res['suggestions'] ?? []);
      });
    }
  }

  Future<void> _submitRegistration() async {
    final username = _usernameController.text.trim();
    final displayName = _displayNameController.text.trim().isNotEmpty 
        ? _displayNameController.text.trim() 
        : username;

    if (!_isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_statusMessage.isNotEmpty ? _statusMessage : 'Please choose an available username'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    final res = widget.viaGoogle
        ? await appState.completeGoogleSignUp(username: username, displayName: displayName)
        : widget.viaEmailOtp
            ? await appState.completeOtpSignUp(username: username, displayName: displayName)
            : await appState.registerPermanentUser(username: username, displayName: displayName);

    if (!mounted) return;
    if (res['success'] == true) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeDashboard()),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message']?.toString() ?? 'Could not create the account.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Create Profile', style: TextStyle(color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose your unique username',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '4–20 characters, letters, numbers, and underscore only. Your email/phone is never shared.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 24),

              // Username Field
              TextField(
                controller: _usernameController,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
                onChanged: (val) => _checkAvailability(val),
                decoration: InputDecoration(
                  prefixText: '@',
                  prefixStyle: const TextStyle(color: AppColors.accent, fontSize: 18),
                  labelText: 'Username',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  suffixIcon: _isChecking
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : (_usernameController.text.length >= 4
                          ? Icon(
                              _isAvailable ? Icons.check_circle : Icons.cancel,
                              color: _isAvailable ? AppColors.success : AppColors.danger,
                            )
                          : null),
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              if (_statusMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _statusMessage,
                  style: TextStyle(
                    color: _isAvailable ? AppColors.success : AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              // Suggested alternatives if taken
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Suggestions available:',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: _suggestions.map((sug) {
                    return ActionChip(
                      backgroundColor: AppColors.surfaceElevated,
                      label: Text('@$sug', style: const TextStyle(color: AppColors.accent, fontSize: 12)),
                      onPressed: () {
                        _usernameController.text = sug;
                        _checkAvailability(sug);
                      },
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 20),

              // Display Name Field
              TextField(
                controller: _displayNameController,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'Display Name (optional)',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  hintText: 'e.g. John Doe',
                  hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 36),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _submitRegistration,
                  child: const Text('Complete & Start Talking', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
