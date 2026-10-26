import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class ReportBlockDialog extends StatefulWidget {
  final String strangerId;
  final String strangerName;
  final Function(String category, String description) onReport;
  final VoidCallback onBlock;

  const ReportBlockDialog({
    super.key,
    required this.strangerId,
    required this.strangerName,
    required this.onReport,
    required this.onBlock,
  });

  @override
  State<ReportBlockDialog> createState() => _ReportBlockDialogState();
}

class _ReportBlockDialogState extends State<ReportBlockDialog> {
  String selectedCategory = 'Harassment or Bullying';
  final TextEditingController _descController = TextEditingController();

  final List<String> categories = [
    'Harassment or Bullying',
    'Inappropriate / Explicit Audio',
    'Hate Speech or Threats',
    'Scam or Fraud',
    'Spam or Advertising',
    'Underage User',
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Report & Block ${widget.strangerName}',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select a reason for your report:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: selectedCategory,
              dropdownColor: AppColors.surfaceElevated,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              items: categories.map((cat) {
                return DropdownMenuItem(value: cat, child: Text(cat));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => selectedCategory = val);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              maxLines: 3,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Additional details (optional)...',
                hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.6)),
                filled: true,
                fillColor: AppColors.surfaceElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Blocking will immediately prevent this user from ever being matched with you again.',
              style: TextStyle(color: AppColors.danger, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            widget.onBlock();
            widget.onReport(selectedCategory, _descController.text);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('User reported and permanently blocked.'),
                backgroundColor: AppColors.surfaceElevated,
              ),
            );
          },
          child: const Text('Report & Block', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
