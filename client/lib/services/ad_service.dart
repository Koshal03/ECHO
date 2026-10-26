import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/ad_config.dart';

enum RewardedAdOutcome { notReady, rewarded, dismissed, error }

/// Handles consent (UMP), SDK start-up, interstitial (with cooldown) and
/// rewarded ads (with server-side verification options).
class AdService {
  bool _ready = false;
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  DateTime? _lastInterstitialAt;

  bool get isReady => _ready;
  bool get isRewardedReady => _ready && _rewardedAd != null;

  Future<void> init() async {
    await _gatherConsent();
    bool canRequest = false;
    try {
      canRequest = await ConsentInformation.instance.canRequestAds();
    } catch (e) {
      debugPrint('[ADS] consent check failed: $e');
    }
    if (!canRequest) {
      debugPrint('[ADS] Not initialising ads: consent not granted / unavailable');
      return;
    }
    await MobileAds.instance.initialize();
    _ready = true;
    if (AdConfig.usingTestIds) {
      debugPrint('[ADS] WARNING: using Google TEST ad units (no revenue).');
    }
    loadInterstitialAd();
    loadRewardedAd();
  }

  /// Google's User Messaging Platform: shows the GDPR/UK consent form when required.
  /// Configure the message in AdMob > Privacy & messaging.
  Future<void> _gatherConsent() {
    final completer = Completer<void>();
    void done() {
      if (!completer.isCompleted) completer.complete();
    }

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
              if (error != null) debugPrint('[ADS] consent form: ${error.message}');
              done();
            });
          } catch (e) {
            debugPrint('[ADS] consent form error: $e');
            done();
          }
        },
        (FormError error) {
          debugPrint('[ADS] consent info update failed: ${error.message}');
          done();
        },
      );
    } catch (e) {
      debugPrint('[ADS] consent error: $e');
      done();
    }
    return completer.future.timeout(const Duration(seconds: 15), onTimeout: () {});
  }

  // ---------------------------------------------------------------- Interstitial
  void loadInterstitialAd() {
    if (!_ready) return;
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (error) {
          debugPrint('[ADS] interstitial failed to load: ${error.message}');
          _interstitialAd = null;
        },
      ),
    );
  }

  /// Shows an interstitial only if: ads are enabled, the cooldown has passed
  /// and an ad is loaded. Returns whether it was shown.
  bool maybeShowInterstitial({required bool enabled, required int cooldownSeconds}) {
    if (!_ready || !enabled) return false;
    final last = _lastInterstitialAt;
    if (last != null && DateTime.now().difference(last).inSeconds < cooldownSeconds) {
      return false;
    }
    final ad = _interstitialAd;
    if (ad == null) {
      loadInterstitialAd();
      return false;
    }
    _interstitialAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _lastInterstitialAt = DateTime.now(),
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[ADS] interstitial failed to show: ${error.message}');
        ad.dispose();
        loadInterstitialAd();
      },
    );
    ad.show();
    return true;
  }

  // -------------------------------------------------------------------- Rewarded
  void loadRewardedAd() {
    if (!_ready) return;
    RewardedAd.load(
      adUnitId: AdConfig.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewardedAd = ad,
        onAdFailedToLoad: (error) {
          debugPrint('[ADS] rewarded failed to load: ${error.message}');
          _rewardedAd = null;
        },
      ),
    );
  }

  /// Shows a rewarded ad. [userId] and [nonce] are attached for AdMob server-side
  /// verification: Google calls our server, which credits the coins. The app never
  /// credits coins itself.
  Future<RewardedAdOutcome> showRewardedAd({
    required String userId,
    required String nonce,
  }) {
    final ad = _rewardedAd;
    if (!_ready || ad == null) {
      loadRewardedAd();
      return Future.value(RewardedAdOutcome.notReady);
    }
    _rewardedAd = null;

    final completer = Completer<RewardedAdOutcome>();
    bool earned = false;

    ad.setServerSideOptions(ServerSideVerificationOptions(userId: userId, customData: nonce));
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        loadRewardedAd();
        if (!completer.isCompleted) {
          completer.complete(earned ? RewardedAdOutcome.rewarded : RewardedAdOutcome.dismissed);
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[ADS] rewarded failed to show: ${error.message}');
        ad.dispose();
        loadRewardedAd();
        if (!completer.isCompleted) completer.complete(RewardedAdOutcome.error);
      },
    );
    ad.show(onUserEarnedReward: (_, reward) => earned = true);
    return completer.future;
  }
}
