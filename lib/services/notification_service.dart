import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

class NotificationService {
  static Future<void> init(String oneSignalAppId) async {
    await OneSignal.initialize(oneSignalAppId);

    OneSignal.Notifications.addPermissionObserver((state) {
      debugPrint('OneSignal permission: $state');
    });

    OneSignal.Notifications.addClickListener((event) {
      debugPrint('OneSignal notification clicked: ${event.notification}');
    });

    await OneSignal.Notifications.requestPermission(true);
  }

  static Future<void> setUserId(String userId) async {
    await OneSignal.login(userId);
    debugPrint('OneSignal external ID set: $userId');
  }

  static Future<void> clearUserId() async {
    await OneSignal.logout();
    debugPrint('OneSignal external ID cleared');
  }

  static Future<String?> getPlayerId() async {
    final sub = OneSignal.User.pushSubscription;
    return sub.id;
  }
}
