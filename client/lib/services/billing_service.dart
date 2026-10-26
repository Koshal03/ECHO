import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// Google Play Billing. Coins are NEVER granted here: every purchase is sent to the
/// server, which verifies it with Google. A purchase is only "completed" (consumed)
/// after the server has confirmed it, so a failed verification is retried on the
/// next app start instead of losing the customer's money.
class BillingService {
  static final BillingService _instance = BillingService._internal();
  factory BillingService() => _instance;
  BillingService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _available = false;

  /// Return true when the server confirmed (or definitively rejected) the purchase,
  /// so it can be completed. Return false to keep it pending and retry later.
  Future<bool> Function(PurchaseDetails purchase)? onPurchaseVerified;
  Function(String message)? onMessage;

  Future<void> init() async {
    _available = await _iap.isAvailable();
    if (!_available) {
      debugPrint('[BILLING] In-app purchase not available');
      return;
    }
    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onDone: () => _subscription?.cancel(),
      onError: (error) => debugPrint('[BILLING ERROR] $error'),
    );
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> list) async {
    for (final purchase in list) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          onMessage?.call('Payment is pending...');
          break;
        case PurchaseStatus.error:
          onMessage?.call('Purchase failed. You have not been charged.');
          if (purchase.pendingCompletePurchase) await _iap.completePurchase(purchase);
          break;
        case PurchaseStatus.canceled:
          onMessage?.call('Purchase cancelled.');
          if (purchase.pendingCompletePurchase) await _iap.completePurchase(purchase);
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final confirmed = await (onPurchaseVerified?.call(purchase) ?? Future.value(false));
          if (confirmed) await _finish(purchase);
          break;
      }
    }
  }

  /// Closes out a purchase AFTER the server has handled it.
  /// Android: consume (this also acknowledges it, and lets the user buy the pack again).
  Future<void> _finish(PurchaseDetails purchase) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      await android.consumePurchase(purchase);
    } else if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  /// Re-delivers purchases that were paid but never confirmed by the server
  /// (e.g. the phone was offline). Call this once a signed-in session exists.
  Future<void> checkPendingPurchases() async {
    if (!_available) return;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[BILLING] restorePurchases failed: $e');
    }
  }

  /// Opens the Google Play purchase sheet. Returns an error message, or null if it launched.
  Future<String?> buyPack(String productId) async {
    if (!_available) return 'Google Play Billing is not available on this device.';
    final response = await _iap.queryProductDetails({productId});
    if (response.productDetails.isEmpty) {
      debugPrint('[BILLING] Product not found in Play Console: $productId');
      return 'This coin pack is not available right now.';
    }
    final param = PurchaseParam(productDetails: response.productDetails.first);
    // autoConsume:false -> the plugin must not consume before the server verified it.
    final launched = await _iap.buyConsumable(purchaseParam: param, autoConsume: false);
    return launched ? null : 'Could not start the purchase. Please try again.';
  }

  void dispose() {
    _subscription?.cancel();
  }
}
