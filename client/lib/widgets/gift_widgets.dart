import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/gift.dart';
import '../providers/app_state.dart';

/// Gold -> purple style gradient used by the Send buttons.
const LinearGradient kGiftSendGradient = LinearGradient(
  colors: [Color(0xFF5B6CFF), Color(0xFFB44CFF), Color(0xFFFFB340)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

/// Gift artwork with a soft glow behind it.
class GiftArt extends StatelessWidget {
  final Gift gift;
  final double size;
  const GiftArt({super.key, required this.gift, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final box = size * 1.7;
    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: box,
            height: box,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [gift.glow.withOpacity(0.38), gift.glow.withOpacity(0.0)],
              ),
            ),
          ),
          Text(gift.emoji, style: TextStyle(fontSize: size, height: 1.0)),
        ],
      ),
    );
  }
}

class CoinIcon extends StatelessWidget {
  final double size;
  const CoinIcon({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) => Icon(Icons.monetization_on, color: AppColors.coinGold, size: size);
}

/// Opens the "Send a gift" sheet during a call.
Future<void> showGiftSheet(BuildContext context) {
  final appState = Provider.of<AppState>(context, listen: false);
  appState.loadGifts();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _GiftSheet(),
  );
}

class _GiftSheet extends StatefulWidget {
  const _GiftSheet();

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  String? _selectedId;
  String? _error;

  Future<void> _send(AppState appState, Gift gift) async {
    setState(() => _error = null);
    final result = await appState.sendGift(gift);
    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = result.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final gifts = appState.gifts;
    final selected = gifts.firstWhere(
      (g) => g.id == _selectedId,
      orElse: () => gifts.firstWhere((g) => g.popular, orElse: () => gifts.first),
    );
    final balance = appState.currentUser?.coins ?? 0;
    final after = balance - selected.price;
    final enough = after >= 0;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.cardBorder, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.card_giftcard_rounded, color: AppColors.coinGold, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Send a gift',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('Show your love with a special gift \u2665',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              GiftCoinPill(coins: balance),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final g in gifts) ...[
                Expanded(
                  child: _GiftTile(
                    gift: g,
                    selected: g.id == selected.id,
                    onTap: () => setState(() {
                      _selectedId = g.id;
                      _error = null;
                    }),
                  ),
                ),
                if (g != gifts.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: enough ? AppColors.primaryLight : AppColors.danger, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    enough
                        ? 'Confirm: ${selected.price} coins  \u2022  Balance $balance \u2192 $after'
                        : 'You need ${selected.price} coins  \u2022  Balance $balance',
                    maxLines: 2,
                    style: TextStyle(
                      color: enough ? AppColors.textPrimary : AppColors.danger,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: appState.giftSending ? null : () => _send(appState, selected),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: kGiftSendGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: appState.giftSending
                        ? const SizedBox(
                            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.send_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text('Send',
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GiftTile extends StatelessWidget {
  final Gift gift;
  final bool selected;
  final VoidCallback onTap;
  const _GiftTile({required this.gift, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected ? gift.glow.withOpacity(0.14) : AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? AppColors.coinGold : AppColors.cardBorder, width: selected ? 2 : 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GiftArt(gift: gift, size: 28),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CoinIcon(size: 13),
                    const SizedBox(width: 3),
                    Text('${gift.price}',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
          if (selected)
            Positioned(
              top: -6,
              right: -4,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(color: AppColors.coinGold, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 16, color: Color(0xFF3A2A00)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Balance chip with the coin icon (used on the gift screens).
class GiftCoinPill extends StatelessWidget {
  final int coins;
  final VoidCallback? onTap;
  final bool showPlus;
  const GiftCoinPill({super.key, required this.coins, this.onTap, this.showPlus = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.coinGold.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CoinIcon(size: 20),
            const SizedBox(width: 6),
            Text('$coins',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
            if (showPlus) ...[
              const SizedBox(width: 8),
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(color: Color(0xFF3A4BFF), shape: BoxShape.circle),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 15),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Put this inside the call screen's Stack. It listens for gifts (sent by us or received) and
/// plays a short animation on top of the call, one gift at a time. It never blocks touches.
class GiftOverlayHost extends StatefulWidget {
  const GiftOverlayHost({super.key});

  @override
  State<GiftOverlayHost> createState() => _GiftOverlayHostState();
}

class _GiftOverlayHostState extends State<GiftOverlayHost> {
  StreamSubscription<GiftEvent>? _sub;
  final List<GiftEvent> _queue = [];
  GiftEvent? _current;
  Key _currentKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _sub = Provider.of<AppState>(context, listen: false).giftEvents.listen((e) {
      if (!mounted) return;
      _queue.add(e);
      if (_queue.length > 6) _queue.removeAt(0);
      _next();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _next() {
    if (_current != null || _queue.isEmpty) return;
    setState(() {
      _current = _queue.removeAt(0);
      _currentKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = _current;
    if (event == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: _GiftBurst(
          key: _currentKey,
          event: event,
          onDone: () {
            if (!mounted) return;
            setState(() => _current = null);
            _next();
          },
        ),
      ),
    );
  }
}

class _GiftBurst extends StatefulWidget {
  final GiftEvent event;
  final VoidCallback onDone;
  const _GiftBurst({super.key, required this.event, required this.onDone});

  @override
  State<_GiftBurst> createState() => _GiftBurstState();
}

class _GiftBurstState extends State<_GiftBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _particle(int i, double t, Gift g) {
    final a = (i / 10) * 2 * math.pi + 0.3;
    final dist = 50 + 100 * Curves.easeOut.transform(t);
    return Transform.translate(
      offset: Offset(math.cos(a) * dist, math.sin(a) * dist * 0.7 - 50 * t),
      child: Opacity(
        opacity: (1 - t).clamp(0.0, 1.0),
        child: Text(i.isEven ? '\u2728' : g.emoji, style: TextStyle(fontSize: 12.0 + (i % 3) * 5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.event.gift;
    final label = widget.event.received ? g.receivedLabel : '${g.name} sent';
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final fade = t > 0.8 ? (1 - (t - 0.8) / 0.2) : 1.0;
        final pop = Curves.elasticOut.transform((t / 0.35).clamp(0.0, 1.0));
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Align(
            alignment: const Alignment(0, -0.1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 280,
                  height: 230,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      for (var i = 0; i < 10; i++) _particle(i, t, g),
                      Transform.scale(scale: pop, child: GiftArt(gift: g, size: 92)),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: pop,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFFFD44D), Color(0xFFFFA502)]),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(g.emoji, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Text(label,
                            style: const TextStyle(
                                color: Color(0xFF3A2A00), fontSize: 16, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
