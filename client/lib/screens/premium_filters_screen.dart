import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/match_prefs.dart';
import '../providers/app_state.dart';
import '../widgets/echo_widgets.dart';
import '../widgets/gift_widgets.dart';
import 'coin_store_screen.dart';

/// Premium Matching: tell Echo which languages you speak, what you are into and (optionally)
/// which region you prefer. Saving your profile is free; using it as a filter is a one-time unlock.
/// Availability varies and a match is never guaranteed.
class PremiumFiltersScreen extends StatefulWidget {
  const PremiumFiltersScreen({super.key});

  @override
  State<PremiumFiltersScreen> createState() => _PremiumFiltersScreenState();
}

class _PremiumFiltersScreenState extends State<PremiumFiltersScreen> {
  static const int _maxLanguages = 5;
  static const int _maxInterests = 8;

  MatchPrefs _draft = const MatchPrefs();
  bool _draftReady = false;

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    appState.loadMatchPrefs().then((_) {
      if (!mounted) return;
      setState(() {
        _draft = appState.matchPrefs;
        _draftReady = true;
      });
    });
  }

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? AppColors.danger : AppColors.surfaceElevated),
    );
  }

  void _toggle(List<String> list, String id, int max, void Function(List<String>) assign, String what) {
    final next = List<String>.of(list);
    if (next.contains(id)) {
      next.remove(id);
    } else if (next.length >= max) {
      _toast('You can choose up to $max $what.');
      return;
    } else {
      next.add(id);
    }
    setState(() => assign(next));
  }

  Future<void> _save(AppState appState) async {
    final error = await appState.saveMatchPrefs(_draft);
    if (!mounted) return;
    _toast(error ?? 'Preferences saved.', error: error != null);
  }

  Future<void> _unlock(AppState appState) async {
    final cost = appState.filterUnlockCost;
    final balance = appState.currentUser?.coins ?? 0;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Unlock advanced filters', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        content: Text(
          balance >= cost
              ? 'This is a one-time unlock for $cost coins.\nBalance after: ${balance - cost} coins.\n\nAvailability varies, and a match is not guaranteed.'
              : 'You need $cost coins. Your balance is $balance coins.',
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(balance >= cost ? 'Unlock' : 'Get coins'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    if (balance < cost) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const CoinStoreScreen()));
      return;
    }
    final error = await appState.unlockFilters();
    if (!mounted) return;
    if (error != null) {
      _toast(error, error: true);
      return;
    }
    final saveError = await appState.saveMatchPrefs(_draft); // keep what the person already chose
    if (!mounted) return;
    _toast(saveError ?? 'Advanced filters unlocked.', error: saveError != null);
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isGuest = appState.currentUser?.isGuest ?? true;
    final balance = appState.currentUser?.coins ?? 0;
    final unlocked = appState.filtersUnlocked;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: const Icon(Icons.chevron_left_rounded, color: AppColors.textPrimary, size: 26),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Premium Matching',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
                    ),
                    GiftCoinPill(
                      coins: balance,
                      showPlus: true,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoinStoreScreen())),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 54, top: 2, bottom: 10),
                  child: Text('Find conversations that fit you.', style: TextStyle(color: AppColors.primaryLight, fontSize: 12)),
                ),
                Expanded(child: _body(appState, isGuest, unlocked)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppState appState, bool isGuest, bool unlocked) {
    if (isGuest) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Sign up with a username to choose your languages and interests.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.4)),
        ),
      );
    }
    if ((appState.matchPrefsLoading && !_draftReady) || (!_draftReady && !appState.matchPrefsFailed)) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (appState.matchPrefsFailed && appState.languageOptions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load your preferences.', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => appState.loadMatchPrefs().then((_) {
                if (mounted) setState(() {
                  _draft = appState.matchPrefs;
                  _draftReady = true;
                });
              }),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              GlassCard(
                padding: const EdgeInsets.all(14),
                radius: 16,
                child: Row(
                  children: [
                    Icon(unlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                        color: unlocked ? AppColors.success : AppColors.coinGold, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        unlocked
                            ? 'Advanced filters are unlocked. Language and region are strict; interests give priority.'
                            : 'Saving your profile is free. Unlock advanced filters (${appState.filterUnlockCost} coins, one time) to search with it.',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _heading('Languages', 'Up to $_maxLanguages. People you meet must speak one of these.'),
              _chips(appState.languageOptions, _draft.languages, (id) => _toggle(_draft.languages, id, _maxLanguages, (v) => _draft = _draft.copyWith(languages: v), 'languages')),
              const SizedBox(height: 16),
              _heading('Interests', 'Up to $_maxInterests. Shared interests are matched first.'),
              _chips(appState.interestOptions, _draft.interests, (id) => _toggle(_draft.interests, id, _maxInterests, (v) => _draft = _draft.copyWith(interests: v), 'interests')),
              const SizedBox(height: 16),
              _heading('Region', 'Only the country is used. Your exact location is never shared.'),
              _regionPicker(appState),
              const SizedBox(height: 8),
              if (unlocked)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.accent,
                  title: const Text('Use filters when searching', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Turn off to match randomly again.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  value: _draft.filtersOn,
                  onChanged: (v) => setState(() => _draft = _draft.copyWith(filtersOn: v)),
                ),
              const SizedBox(height: 4),
              const Text(
                'Availability varies, and a match is not guaranteed. If nobody fits, you can search without filters at any time.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.4),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _actionButton(appState, unlocked),
      ],
    );
  }

  Widget _heading(String title, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(hint, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      );

  Widget _chips(List<MatchOption> options, List<String> selected, void Function(String id) onTap) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          InkWell(
            onTap: () => onTap(o.id),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                gradient: selected.contains(o.id) ? AppColors.brandGradient : null,
                color: selected.contains(o.id) ? null : AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: selected.contains(o.id) ? Colors.transparent : AppColors.cardBorder),
              ),
              child: Text(o.name,
                  style: TextStyle(
                      color: selected.contains(o.id) ? Colors.white : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }

  Widget _regionPicker(AppState appState) {
    final options = appState.regionOptions;
    final value = options.any((o) => o.id == _draft.region) ? _draft.region : 'any';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.isEmpty ? null : value,
          isExpanded: true,
          dropdownColor: AppColors.surfaceElevated,
          iconEnabledColor: AppColors.textSecondary,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          items: [for (final o in options) DropdownMenuItem(value: o.id, child: Text(o.name))],
          onChanged: (v) {
            if (v != null) setState(() => _draft = _draft.copyWith(region: v));
          },
        ),
      ),
    );
  }

  Widget _actionButton(AppState appState, bool unlocked) {
    final busy = appState.filterUnlocking || appState.matchPrefsSaving;
    final String label = unlocked ? 'Save preferences' : 'Unlock advanced filters \u2014 ${appState.filterUnlockCost} coins';
    return InkWell(
      onTap: busy ? null : () => unlocked ? _save(appState) : _unlock(appState),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(20)),
        child: busy
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(unlocked ? Icons.check_rounded : Icons.lock_open_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                ],
              ),
      ),
    );
  }
}
