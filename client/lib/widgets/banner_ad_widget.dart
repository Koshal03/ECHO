import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/ad_config.dart';

/// Standard 320x50 banner. Takes no space until an ad has loaded, so a failed
/// or disabled ad never leaves a blank gap. Don't place on call screens.
class BannerAdWidget extends StatefulWidget {
  final bool enabled;
  final bool sdkReady;
  const BannerAdWidget({super.key, required this.enabled, required this.sdkReady});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant BannerAdWidget old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && _ad != null) {
      _disposeAd();
    } else if (widget.enabled && widget.sdkReady && _ad == null) {
      _maybeLoad();
    }
  }

  void _maybeLoad() {
    if (!widget.enabled || !widget.sdkReady || _ad != null) return;
    final ad = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[ADS] banner failed to load: ${error.message}');
          ad.dispose();
          if (mounted) {
            setState(() {
              _ad = null;
              _loaded = false;
            });
          }
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  void _disposeAd() {
    _ad?.dispose();
    setState(() {
      _ad = null;
      _loaded = false;
    });
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!widget.enabled || !_loaded || ad == null) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
