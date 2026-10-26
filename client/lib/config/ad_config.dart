import 'package:flutter/foundation.dart';

/// AdMob configuration.
///
/// - Release builds use the real ECHO ad units below.
/// - Debug/profile builds use Google's TEST units, so you never click your own
///   live ads (that can get an AdMob account suspended).
/// - Any unit can still be overridden at build time with
///   --dart-define=ADMOB_BANNER_ID=... / ADMOB_INTERSTITIAL_ID=... / ADMOB_REWARDED_ID=...
///
/// The AdMob *app* ID is set in android/gradle.properties (admobAppId). Note: the
/// manifest uses that same live app ID in every build, which is fine because the
/// ad units (not the app ID) decide whether ads are test or live.
class AdConfig {
  static const String _testPrefix = 'ca-app-pub-3940256099942544';

  // Live ECHO ad units (AdMob publisher pub-2996217719964580)
  static const String _liveBanner = 'ca-app-pub-2996217719964580/4260040054'; // echo_banner_home
  static const String _liveInterstitial = 'ca-app-pub-2996217719964580/7512889351'; // echo_interstitial_aftercall
  static const String _liveRewarded = 'ca-app-pub-2996217719964580/8634399335'; // echo_rewarded_coins

  // Google test units
  static const String _testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const String _testRewarded = 'ca-app-pub-3940256099942544/5224354917';

  static const String _bannerOverride = String.fromEnvironment('ADMOB_BANNER_ID');
  static const String _interstitialOverride = String.fromEnvironment('ADMOB_INTERSTITIAL_ID');
  static const String _rewardedOverride = String.fromEnvironment('ADMOB_REWARDED_ID');

  static String get bannerAdUnitId =>
      _bannerOverride.isNotEmpty ? _bannerOverride : (kReleaseMode ? _liveBanner : _testBanner);
  static String get interstitialAdUnitId => _interstitialOverride.isNotEmpty
      ? _interstitialOverride
      : (kReleaseMode ? _liveInterstitial : _testInterstitial);
  static String get rewardedAdUnitId =>
      _rewardedOverride.isNotEmpty ? _rewardedOverride : (kReleaseMode ? _liveRewarded : _testRewarded);

  /// True while any ad unit is still a Google test unit (no revenue is earned).
  static bool get usingTestIds =>
      bannerAdUnitId.startsWith(_testPrefix) ||
      interstitialAdUnitId.startsWith(_testPrefix) ||
      rewardedAdUnitId.startsWith(_testPrefix);

  /// Used when the server doesn't provide ad settings.
  static const int defaultInterstitialCooldownSeconds = 120;
}
