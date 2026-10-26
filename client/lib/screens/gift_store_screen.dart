import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/gift.dart';
import '../providers/app_state.dart';
import '../widgets/gift_widgets.dart';
import 'coin_store_screen.dart';

/// Gift Store: pick a gift and send it to the stranger you are talking to.
/// Outside a call it works as a catalogue (and shows the gifts you have sent).
class GiftStoreScreen extends StatefulWidget {
  const GiftStoreScreen({super.key});

  @override
  State<GiftStoreScreen> createState() => _GiftStoreScreenState();
}

class _GiftStoreScreenState extends State<GiftStoreScreen> {
  String? _selectedId;
  bool _showMyGifts = false;

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    appState.loadGifts();
    appState.loadWalletHistory();
  }

  Future<void> _send(AppState appState, Gift gift) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await appState.sendGift(gift);
    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop(); // back to the call, where the animation plays
    } else {
      messenger.showSnackBar(SnackBar(content: Text(result.error ?? 'Could not send the gift.'), backgroundColor: AppColors.danger));
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
    final inCall = appState.activeCall != null;
    final isGuest = appState.currentUser?.isGuest ?? true;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.screenGradient),
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
                    const Icon(Icons.card_giftcard_rounded, color: AppColors.coinGold, size: 30),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: 'Gift ', style: TextStyle(color: AppColors.textPrimary)),
                          TextSpan(text: 'Store', style: TextStyle(color: AppColors.coinGold)),
                        ]),
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                      ),
                    ),
                    GiftCoinPill(
                      coins: balance,
                      showPlus: true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CoinStoreScreen()),
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 58, top: 2),
                  child: Text('Make your moments special \u2665',
                      style: TextStyle(color: AppColors.primaryLight, fontSize: 12)),
                ),
                const SizedBox(height: 14),
                _tabs(),
                const SizedBox(height: 14),
                Expanded(
                  child: _showMyGifts
                      ? _myGifts(appState)
                      : Column(
                          children: [
                            Expanded(child: _grid(gifts, selected)),
                            const SizedBox(height: 10),
                            _balanceAfter(balance, selected),
                            const SizedBox(height: 12),
                            _sendButton(appState, selected, inCall, isGuest),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabs() {
    Widget tab(String label, IconData icon, bool active, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: active ? AppColors.brandGradient : null,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: active ? Colors.white : AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        color: active ? Colors.white : AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          tab('Gifts', Icons.card_giftcard_rounded, !_showMyGifts, () => setState(() => _showMyGifts = false)),
          tab('My Gifts', Icons.inventory_2_outlined, _showMyGifts, () {
            setState(() => _showMyGifts = true);
            Provider.of<AppState>(context, listen: false).loadWalletHistory();
          }),
        ],
      ),
    );
  }

  Widget _grid(List<Gift> gifts, Gift selected) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      itemCount: gifts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.98,
      ),
      itemBuilder: (context, i) {
        final g = gifts[i];
        final isSel = g.id == selected.id;
        return InkWell(
          onTap: () => setState(() => _selectedId = g.id),
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: g.glow.withOpacity(isSel ? 0.16 : 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isSel ? AppColors.coinGold : g.glow.withOpacity(0.4), width: isSel ? 2 : 1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GiftArt(gift: g, size: 54),
                    const SizedBox(height: 4),
                    Text(g.name,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CoinIcon(size: 17),
                        const SizedBox(width: 5),
                        Text('${g.price} coins',
                            style: const TextStyle(color: AppColors.coinGold, fontSize: 14, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),
              if (g.popular)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: const BoxDecoration(
                      color: AppColors.coinGold,
                      borderRadius: BorderRadius.only(topRight: Radius.circular(20), bottomLeft: Radius.circular(12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.workspace_premium_rounded, size: 13, color: Color(0xFF3A2A00)),
                        SizedBox(width: 3),
                        Text('Popular',
                            style: TextStyle(color: Color(0xFF3A2A00), fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _balanceAfter(int balance, Gift selected) {
    final after = balance - selected.price;
    final enough = after >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (enough ? AppColors.coinGold : AppColors.danger).withOpacity(0.6)),
      ),
      child: Row(
        children: [
          const CoinIcon(size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(enough ? 'Balance after gift' : 'Not enough coins',
                style: TextStyle(color: enough ? AppColors.textSecondary : AppColors.danger, fontSize: 14)),
          ),
          Text(enough ? '$after coins' : 'Need ${-after} more',
              style: TextStyle(
                  color: enough ? AppColors.coinGold : AppColors.danger, fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _sendButton(AppState appState, Gift selected, bool inCall, bool isGuest) {
    final String label;
    if (isGuest) {
      label = 'Sign up to send gifts';
    } else if (inCall) {
      label = 'Send ${selected.name}';
    } else {
      label = 'Gifts are sent during a call';
    }
    return InkWell(
      onTap: appState.giftSending
          ? null
          : () {
              if (isGuest) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sign up with a username to send gifts.'), backgroundColor: AppColors.surfaceElevated));
              } else if (!inCall) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Start a call, then tap Gift to send this to your match.'),
                    backgroundColor: AppColors.surfaceElevated));
              } else {
                _send(appState, selected);
              }
            },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: inCall && !isGuest ? kGiftSendGradient : null,
          color: inCall && !isGuest ? null : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: inCall && !isGuest ? null : Border.all(color: AppColors.cardBorder),
        ),
        child: appState.giftSending
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.send_rounded, color: inCall && !isGuest ? Colors.white : AppColors.textSecondary, size: 22),
                  const SizedBox(width: 10),
                  Text(label,
                      style: TextStyle(
                          color: inCall && !isGuest ? Colors.white : AppColors.textSecondary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                ],
              ),
      ),
    );
  }

  Widget _myGifts(AppState appState) {
    final sent = appState.walletHistory.where((t) => t.source == 'gift_sent').toList();
    if (appState.walletHistoryLoading && sent.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (sent.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.card_giftcard_rounded, color: AppColors.textSecondary, size: 48),
            const SizedBox(height: 12),
            Text(appState.walletHistoryFailed ? 'Could not load your gifts. Try again later.' : 'No gifts sent yet',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Gifts you send during calls will show up here.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }
    final fmt = DateFormat('d MMM, h:mm a');
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: sent.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final t = sent[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.card_giftcard_rounded, color: AppColors.pink, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                    Text(fmt.format(t.createdAt), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Text('${t.delta}', style: const TextStyle(color: AppColors.coinGold, fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
        );
      },
    );
  }
}
