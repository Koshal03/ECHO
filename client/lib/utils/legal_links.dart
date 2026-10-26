import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_state.dart';

/// Opens one of the legal pages that the Echo server hosts:
/// 'privacy_policy.html' or 'terms_and_conditions.html'.
Future<void> openLegalPage(BuildContext context, String page) async {
  final base = Provider.of<AppState>(context, listen: false).backendUrl;
  var opened = false;
  try {
    opened = await launchUrl(Uri.parse('$base/$page'), mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the page. Please try again later.')),
    );
  }
}
