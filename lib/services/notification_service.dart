import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';
import '../main.dart';
import 'platform_support.dart';
import 'follow_service.dart';
import 'people_interaction_service.dart';
import 'chat_service.dart';
import 'uni_chat_service.dart';
import '../screens/chat_screen.dart';
import '../screens/delve/delve_shell.dart';
import '../screens/event_certificates_screen.dart';
import '../screens/event_notifications_screen.dart';
import '../screens/habit_tracker_screen.dart';
import '../screens/timetable_screen.dart';
import '../screens/uni_chat_screen.dart';
import '../screens/sciwordle_screen.dart';
import '../widgets/app_motion.dart';
import '../widgets/utopia_snackbar.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/focus_models.dart';
import 'user_timetable_service.dart';
import '../models/user_timetable.dart';
import 'focus_database_service.dart';
import 'focus_supabase_service.dart';

@pragma('vm:entry-point')
Future<void> notificationActionBackgroundCallback(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  final localNotif = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('ic_notification');
  try {
    await localNotif.initialize(
      const InitializationSettings(android: androidSettings),
    );
  } catch (_) {}
  await NotificationService.onDidReceiveBackgroundNotificationResponse(response);
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!PlatformSupport.supportsNotifications) {
    return;
  }
  debugPrint('[FCM_BACKGROUND] Background handler received message: id=${message.messageId}, data=${message.data}, notifTitle=${message.notification?.title}');
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    final type = (message.data['type'] ?? '').toString();
    final isChat = type == 'chat';

    // If message contains a standard notification payload and is not a chat message,
    // Android/Google Play Services and iOS APNs automatically render the system notification banner directly.
    if (message.notification != null && !isChat) {
      return;
    }

    // For data-only messages in the background/killed state, display the notification manually
    final rawTitle = (message.data['title']?.toString() ??
        message.data['senderName']?.toString() ??
        message.data['sender_name']?.toString() ??
        message.notification?.title ??
        '').trim();
    final rawBody = (message.data['body']?.toString() ??
        message.data['message']?.toString() ??
        message.data['message_text']?.toString() ??
        message.notification?.body ??
        '').trim();

    // Ignore empty/data-only background pings that contain no user-visible message
    if (rawBody.isEmpty) {
      return;
    }

    final title = rawTitle.isNotEmpty ? rawTitle : 'UTOPIA';
    final body = rawBody;

    final localNotifications = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('ic_notification');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );
    await localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (response.actionId == 'action_reply' || response.actionId == 'action_mark_as_read') {
          if (response.payload != null && response.payload!.isNotEmpty) {
            await NotificationService.handleChatNotificationAction(
              actionId: response.actionId!,
              replyInput: response.input,
              payload: response.payload!,
              notificationId: response.id ?? 0,
            );
          }
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationActionBackgroundCallback,
    );

    const generalChannel = AndroidNotificationChannel(
      'utopia_high_importance_v3',
      'UTOPIA Notifications',
      description: 'Live alerts, general notifications, and reminders from UTOPIA',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
      enableLights: true,
    );

    const chatChannel = AndroidNotificationChannel(
      'utopia_chat_messages_v4',
      'UTOPIA Direct Messages',
      description: 'Real-time conversational chat messages from friends',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
      enableLights: true,
    );

    final androidPlugin = localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(generalChannel);
    await androidPlugin?.createNotificationChannel(chatChannel);

    final chatId = (message.data['chatId'] ?? message.data['chat_id'] ?? '').toString();
    final notifTag = (isChat && chatId.isNotEmpty)
        ? 'chat_$chatId'
        : (message.data['messageId'] ??
            message.data['waveId'] ??
            message.data['linkDocId'] ??
            message.data['followDocId'] ??
            message.data['notificationId'] ??
            message.messageId ??
            '${title}_$body').toString();
    final notifId = notifTag.hashCode & 0x7FFFFFFF;

    final themeColor = await NotificationService.getNotificationThemeColor();
    final senderName = (message.data['senderName'] ?? message.data['sender_name'] ?? title).toString();
    final senderId = (message.data['senderId'] ?? message.data['sender_id'] ?? '').toString();
    final recipientId = (message.data['recipientId'] ?? message.data['recipient_id'] ?? '').toString();
    final List<AndroidNotificationAction>? actions = isChat
        ? NotificationService.buildChatActions(senderName: senderName)
        : NotificationService._getActionsForType(type, Map<String, dynamic>.from(message.data));

    final StyleInformation styleInformation;
    final unreadCountStr = (message.data['unreadCount'] ?? message.data['unread_count'] ?? '').toString();
    final unreadCount = int.tryParse(unreadCountStr);
    if (isChat && chatId.isNotEmpty) {
      final messageList = await NotificationService.getAccumulatedChatMessages(
        chatId: chatId,
        senderName: senderName,
        senderId: senderId,
        newBody: body,
        unreadCount: unreadCount,
      );
      const mePerson = Person(
        name: 'Me',
        key: 'me',
      );
      styleInformation = MessagingStyleInformation(
        mePerson,
        conversationTitle: null,
        groupConversation: false,
        messages: messageList,
      );
    } else if (isChat) {
      final senderPerson = Person(
        name: senderName.isNotEmpty ? senderName : 'Friend',
        key: senderId.isNotEmpty ? senderId : null,
        important: true,
        icon: const DrawableResourceAndroidIcon('ic_notification_large'),
      );
      const mePerson = Person(
        name: 'Me',
        key: 'me',
      );
      styleInformation = MessagingStyleInformation(
        mePerson,
        conversationTitle: null,
        groupConversation: false,
        messages: [
          Message(
            body,
            DateTime.now(),
            senderPerson,
          ),
        ],
      );
    } else {
      styleInformation = BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'UTOPIA',
      );
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        isChat ? 'utopia_chat_messages_v4' : 'utopia_high_importance_v3',
        isChat ? 'UTOPIA Direct Messages' : 'UTOPIA Notifications',
        channelDescription: isChat
            ? 'Real-time conversational chat messages from friends'
            : 'Live alerts, chat messages, and reminders from UTOPIA',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        category: isChat ? AndroidNotificationCategory.message : AndroidNotificationCategory.event,
        tag: null,
        groupKey: (isChat && chatId.isNotEmpty) ? 'chat_$chatId' : null,
        color: themeColor,
        actions: actions,
        styleInformation: styleInformation,
        icon: 'ic_notification',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
      ),
    );

    // Cancel any system-generated notification from Google Play Services (which uses id 0 or collapseTag)
    try {
      if (notifTag.isNotEmpty) {
        await androidPlugin?.cancel(0, tag: notifTag);
      }
      await androidPlugin?.cancel(0);
      final active = await androidPlugin?.getActiveNotifications();
      if (active != null) {
        for (final n in active) {
          if (n.id != notifId && (n.tag == notifTag || (isChat && n.tag == 'chat_$chatId'))) {
            await androidPlugin?.cancel(n.id ?? 0, tag: n.tag);
          }
        }
      }
    } catch (_) {}

    await localNotifications.show(
      notifId,
      title,
      body,
      details,
      payload: jsonEncode({
        'title': title,
        'body': body,
        'tag': notifTag,
        'type': type,
        'senderId': senderId,
        'recipientId': recipientId,
        'chatId': chatId,
        'senderName': senderName,
        'data': message.data,
      }),
    );
  } catch (e) {
    debugPrint('Error in background message handler: $e');
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _launchDetailsHandled = false;
  static bool isDialogShowing = false;
  static StreamSubscription<User?>? _authSubscription;
  static bool _isAppForeground = true;
  static String? _activeChatId;

  // Deduplication cache for incoming FCM payloads
  static final Set<String> _recentlyHandledMessageIds = <String>{};
  static final Map<String, DateTime> _recentMessageTimestamps = <String, DateTime>{};

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'utopia_high_importance_v3',
    'UTOPIA Notifications',
    description: 'Live alerts, general notifications, and reminders from UTOPIA',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
    enableLights: true,
  );

  static const AndroidNotificationChannel _chatChannel = AndroidNotificationChannel(
    'utopia_chat_messages_v4',
    'UTOPIA Direct Messages',
    description: 'Real-time conversational chat messages from friends',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    showBadge: true,
    enableLights: true,
  );

  /// Resolves the user's active theme primary color for notification accents and buttons.
  static Future<Color> getNotificationThemeColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final colorVal = prefs.getInt('theme_primary_color_value');
      if (colorVal != null && colorVal != 0) {
        return Color(colorVal);
      }
    } catch (_) {}
    return appThemeNotifier.value.primary;
  }

  /// Builds interactive Android notification actions for incoming chat messages.
  static List<AndroidNotificationAction> buildChatActions({
    required String senderName,
  }) {
    return [
      AndroidNotificationAction(
        'action_reply',
        'Reply',
        inputs: [
          AndroidNotificationActionInput(
            label: 'Reply to $senderName...',
          ),
        ],
        allowGeneratedReplies: true,
        showsUserInterface: false,
        cancelNotification: true,
      ),
      const AndroidNotificationAction(
        'action_mark_as_read',
        'Mark as read',
        showsUserInterface: false,
        cancelNotification: true,
      ),
    ];
  }

  /// Persists and returns the conversation thread for a chat so Android displays
  /// a single grouped notification with multiple messages (like Instagram / WhatsApp).
  static Future<List<Message>> getAccumulatedChatMessages({
    required String chatId,
    required String senderName,
    required String senderId,
    required String newBody,
    int? unreadCount,
    DateTime? timestamp,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.reload();
    } catch (_) {}

    // Check Firestore for the true unreadCount if not supplied in push payload
    int effectiveUnread = unreadCount ?? 0;
    if (effectiveUnread <= 0) {
      try {
        final myUid = FirebaseAuth.instance.currentUser?.uid ??
            prefs.getString('cached_user_uid') ??
            prefs.getString('auth_uid') ??
            prefs.getString('last_known_uid') ??
            '';
        if (myUid.isNotEmpty) {
          final chatDoc = await FirebaseFirestore.instance
              .collection('chats')
              .doc(chatId)
              .get()
              .timeout(const Duration(milliseconds: 1500));
          if (chatDoc.exists) {
            effectiveUnread =
                (chatDoc.data()?['unreadCount_$myUid'] as num?)?.toInt() ?? 0;
          }
        }
      } catch (_) {}
    }

    final key = 'notif_msgs_$chatId';
    final rawList = prefs.getStringList(key) ?? [];
    final nowMs = (timestamp ?? DateTime.now()).millisecondsSinceEpoch;
    final lastReadMs = prefs.getInt('chat_last_read_$chatId') ?? 0;

    final List<Map<String, dynamic>> messagesJson = [];

    // Only keep prior messages if there are multiple unread messages (> 1)
    if (effectiveUnread > 1) {
      for (final item in rawList) {
        try {
          final decoded = jsonDecode(item);
          if (decoded is Map<String, dynamic>) {
            final time = decoded['time'] as int? ?? 0;
            if (time > lastReadMs) {
              messagesJson.add(decoded);
            }
          }
        } catch (_) {}
      }

      // Keep at most (effectiveUnread - 1) previous unread messages so total equals effectiveUnread
      final maxPrior = effectiveUnread - 1;
      if (messagesJson.length > maxPrior) {
        messagesJson.removeRange(0, messagesJson.length - maxPrior);
      }
    } else {
      // Single unread message: start completely fresh!
      messagesJson.clear();
    }

    // Append new incoming message
    messagesJson.add({
      'text': newBody,
      'time': nowMs,
      'isMe': false,
    });

    // Keep up to 10 most recent unread messages
    if (messagesJson.length > 10) {
      messagesJson.removeRange(0, messagesJson.length - 10);
    }

    await prefs.setStringList(
      key,
      messagesJson.map((m) => jsonEncode(m)).toList(),
    );

    final senderPerson = Person(
      name: senderName.isNotEmpty ? senderName : 'Friend',
      key: senderId.isNotEmpty ? senderId : null,
      important: true,
      icon: const DrawableResourceAndroidIcon('ic_notification_large'),
    );
    const mePerson = Person(
      name: 'Me',
      key: 'me',
    );

    return messagesJson.map((m) {
      final text = (m['text'] ?? '').toString();
      final timeMs = m['time'] as int? ?? nowMs;
      final isMe = m['isMe'] == true;
      return Message(
        text,
        DateTime.fromMillisecondsSinceEpoch(timeMs),
        isMe ? mePerson : senderPerson,
      );
    }).toList();
  }

  /// Records a sent reply into the accumulated chat history so subsequent
  /// notification updates show both sides of the conversation thread.
  static Future<void> recordSentChatMessage({
    required String chatId,
    required String text,
  }) async {
    if (chatId.isEmpty || text.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'notif_msgs_$chatId';
      final rawList = prefs.getStringList(key) ?? [];
      final List<Map<String, dynamic>> messagesJson = [];
      for (final item in rawList) {
        try {
          final decoded = jsonDecode(item);
          if (decoded is Map<String, dynamic>) {
            messagesJson.add(decoded);
          }
        } catch (_) {}
      }
      messagesJson.add({
        'text': text,
        'time': DateTime.now().millisecondsSinceEpoch,
        'isMe': true,
      });
      if (messagesJson.length > 10) {
        messagesJson.removeRange(0, messagesJson.length - 10);
      }
      await prefs.setStringList(
        key,
        messagesJson.map((m) => jsonEncode(m)).toList(),
      );
    } catch (_) {}
  }

  /// Cancels any active notification for a chat and clears its accumulated message history.
  static Future<void> clearChatNotification(String chatId) async {
    if (chatId.isEmpty) return;
    final notifId = 'chat_$chatId'.hashCode & 0x7FFFFFFF;
    final notifTag = 'chat_$chatId';
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 1. Immediately purge persisted messages and record last read timestamp
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        await prefs.reload();
      } catch (_) {}
      await prefs.remove('notif_msgs_$chatId');
      await prefs.setInt('chat_last_read_$chatId', nowMs);
    } catch (e) {
      debugPrint('[NOTIF] Failed to clear prefs for $chatId: $e');
    }

    // 2. Safely dismiss Android / local notifications (both with and without tag)
    try {
      final localNotif = FlutterLocalNotificationsPlugin();
      await localNotif.cancel(notifId);
      await localNotif.cancel(notifId, tag: notifTag);
      await _localNotifications.cancel(notifId);
      await _localNotifications.cancel(notifId, tag: notifTag);
      final androidPlugin = localNotif
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.cancel(notifId);
      await androidPlugin?.cancel(notifId, tag: notifTag);

      // Cancel any active notifications matching this tag or id
      final active = await androidPlugin?.getActiveNotifications();
      if (active != null) {
        for (final n in active) {
          if (n.tag == notifTag || n.id == notifId || (n.tag?.contains(chatId) ?? false)) {
            await androidPlugin?.cancel(n.id ?? 0, tag: n.tag);
            await androidPlugin?.cancel(n.id ?? 0);
          }
        }
      }
    } catch (e) {
      debugPrint('[NOTIF] Failed to cancel notifications for $chatId: $e');
    }
  }

  /// Robust timezone initialization with graceful multi-tier fallback.
  static Future<void> _ensureTimezone() async {
    tz.initializeTimeZones();
    try {
      final res = await FlutterTimezone.getLocalTimezone();
      final String timeZoneName = res.identifier;
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      } catch (_) {
        tz.setLocalLocation(tz.local);
      }
    }
  }

  /// Await navigatorKey.currentState availability for cold-start launch notifications.
  static Future<NavigatorState?> _waitForNavigator({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final start = DateTime.now();
    while (navigatorKey.currentState == null) {
      if (DateTime.now().difference(start) > timeout) {
        return null;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return navigatorKey.currentState;
  }

  static Future<void> initialize() async {
    if (!PlatformSupport.supportsNotifications) {
      return;
    }
    try {
      if (_initialized) {
        return;
      }
      await _ensureTimezone();

      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('ic_notification');
      const DarwinInitializationSettings darwinSettings =
          DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
            defaultPresentAlert: true,
            defaultPresentSound: true,
            defaultPresentBadge: true,
            defaultPresentBanner: true,
            defaultPresentList: true,
          );
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) async {
          try {
            if (response.actionId == 'action_reply' || response.actionId == 'action_mark_as_read') {
              if (response.payload != null && response.payload!.isNotEmpty) {
                await handleChatNotificationAction(
                  actionId: response.actionId!,
                  replyInput: response.input,
                  payload: response.payload!,
                  notificationId: response.id ?? 0,
                );
              }
              return;
            }
            if (response.actionId != null && response.actionId!.isNotEmpty && response.payload != null) {
              unawaited(_handleQuickAction(
                actionId: response.actionId!,
                payload: response.payload!,
                notificationId: response.id,
                input: response.input,
              ));
              return;
            }
            if (response.payload != null && response.payload!.isNotEmpty) {
              unawaited(_handleNotificationPayload(response.payload!));
            }
          } catch (e) {
            debugPrint('Error handling notification response: $e');
          }
        },
        onDidReceiveBackgroundNotificationResponse: notificationActionBackgroundCallback,
      );

      final launchDetails = await _localNotifications
          .getNotificationAppLaunchDetails();
      if (!_launchDetailsHandled && (launchDetails?.didNotificationLaunchApp ?? false)) {
        _launchDetailsHandled = true;
        final payload = launchDetails?.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          unawaited(_handleNotificationPayload(payload));
        }
      }

      // Create high-importance notification channels for Android
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(_channel);
      await androidPlugin?.createNotificationChannel(_chatChannel);

      // Request runtime notification permissions
      await _requestRuntimePermissions();

      // Retrieve and register FCM token
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
      }

      FirebaseMessaging.instance.onTokenRefresh.listen(_saveTokenToFirestore);
      _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) async {
        if (user == null) {
          return;
        }
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await _saveTokenToFirestore(token);
        }
      });

      // Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        try {
          debugPrint('[FCM_FOREGROUND] Message received: id=${message.messageId}, type=${message.data['type']}, title=${message.notification?.title ?? message.data['title']}, body=${message.notification?.body ?? message.data['body'] ?? message.data['message']}');
          final rawTitle = (message.notification?.title ??
              message.data['title']?.toString() ??
              message.data['senderName']?.toString() ??
              message.data['sender_name']?.toString() ??
              '').trim();
          final rawBody = (message.notification?.body ??
              message.data['body']?.toString() ??
              message.data['message']?.toString() ??
              message.data['message_text']?.toString() ??
              '').trim();

          // Ignore empty pings without user message content
          if (rawBody.isEmpty) {
            debugPrint('[FCM_FOREGROUND] Dropped empty message payload');
            return;
          }

          // Deduplicate incoming messages within 30-second window
          final rawMsgId = message.messageId;
          final msgKey = (rawMsgId != null && rawMsgId.isNotEmpty)
              ? rawMsgId
              : '${rawTitle}_${rawBody}_${message.data['type']}_${message.data['chatId'] ?? message.data['messageId']}';

          final now = DateTime.now();
          _recentMessageTimestamps.removeWhere((k, t) => now.difference(t).inSeconds > 30);
          _recentlyHandledMessageIds.removeWhere((id) => !_recentMessageTimestamps.containsKey(id));

          if (_recentlyHandledMessageIds.contains(msgKey)) {
            debugPrint('[FCM_FOREGROUND] Dropped duplicate incoming message: $msgKey');
            return;
          }
          _recentlyHandledMessageIds.add(msgKey);
          _recentMessageTimestamps[msgKey] = now;

          final title = rawTitle.isNotEmpty ? rawTitle : 'UTOPIA';
          final body = rawBody;
          final type = (message.data['type'] ?? '').toString();
          final chatId =
              (message.data['chatId'] ?? message.data['chat_id'] ?? '')
                  .toString();
          final uniId =
              (message.data['universityId'] ?? message.data['university_id'] ?? '')
                  .toString();
          final isForegroundChat = type == 'chat' && _isAppForeground;
          final isForegroundUniChat =
              (type == 'uni_chat' || type == 'global_chat') && _isAppForeground;
          final isActiveChat =
              isForegroundChat && chatId.isNotEmpty && _activeChatId == chatId;
          final isActiveUniChat = isForegroundUniChat &&
              (_activeChatId == 'uni_$uniId' || (_activeChatId?.startsWith('uni_') ?? false));

          if (isActiveChat || isActiveUniChat) {
            debugPrint('[FCM_FOREGROUND] Silenced notification for currently active open chat screen ($chatId)');
            return;
          }

          if (type == 'morning_notification' && !U.morningNotifEnabled) {
            return;
          }

          debugPrint('[FCM_FOREGROUND] Showing local notification for: "$title" - "$body"');
          await _showLocalNotification(
            title: title,
            body: body,
            data: Map<String, dynamic>.from(message.data),
          );

          if (isForegroundChat || isForegroundUniChat) {
            _showInAppMessageHint(title: title, body: body);
          }
        } catch (e) {
          debugPrint('Error handling foreground FCM message: $e');
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((
        RemoteMessage message,
      ) async {
        try {
          await _handleRemoteMessageInteraction(message);
        } catch (e) {
          debugPrint('Error handling onMessageOpenedApp: $e');
        }
      });

      RemoteMessage? initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) {
        final msgId = initialMessage.messageId ??
            'fcm_${initialMessage.sentTime?.millisecondsSinceEpoch}';
        final prefs = await SharedPreferences.getInstance();
        final lastHandledMsgId = prefs.getString('last_handled_fcm_initial_msg_id');
        if (msgId.isNotEmpty && msgId != lastHandledMsgId) {
          await prefs.setString('last_handled_fcm_initial_msg_id', msgId);
          try {
            await _handleRemoteMessageInteraction(initialMessage);
          } catch (e) {
            debugPrint('Error handling initialMessage: $e');
          }
        }
      }
      _initialized = true;
    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
      return;
    }
  }

  static Future<void> _requestRuntimePermissions() async {
    try {
      // 1. Android 13+ (API 33+) POST_NOTIFICATIONS permission
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
      }

      // 2. Firebase Messaging Permission (iOS & Android)
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
    } catch (e) {
      debugPrint('Error requesting runtime permissions: $e');
    }
  }

  static Future<bool> areNotificationPermissionsEnabled() async {
    if (!PlatformSupport.supportsNotifications) return true;
    try {
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final areEnabled = await androidPlugin.areNotificationsEnabled();
        if (areEnabled != null) {
          return areEnabled;
        }
      }
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }
      return true;
    } catch (e) {
      return true;
    }
  }

  static Future<void> requestNotificationPermissionOnly() async {
    if (!PlatformSupport.supportsNotifications) return;
    await _requestRuntimePermissions();
  }

  static Future<void> ensureNotificationPermissions() async {
    await _requestRuntimePermissions();
  }

  static void setAppForeground(bool isForeground) {
    _isAppForeground = isForeground;
  }

  static Future<void> refreshTokenRegistration() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveTokenToFirestore(token);
      }
    } catch (e) {
      return;
    }
  }

  static void setActiveChat(String? chatId) {
    _activeChatId = chatId;
    if (chatId != null && chatId.isNotEmpty) {
      unawaited(clearChatNotification(chatId));
    }
  }

  static Future<void> sendPersonalMorningNotification({
    required String title,
    required String body,
  }) async {
    final resolvedTitle = title.trim().isEmpty
        ? 'Morning notification'
        : title.trim();
    final resolvedBody = body.trim();
    if (resolvedBody.isEmpty) {
      return;
    }

    await initialize();
    await _showLocalNotification(
      title: resolvedTitle,
      body: resolvedBody,
      data: const <String, dynamic>{'type': 'morning_notification'},
    );

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
  }

  static void _showInAppMessageHint({
    required String title,
    required String body,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      return;
    }

    final previewBody = body;
    final message = switch ((title.trim().isNotEmpty, body.trim().isNotEmpty)) {
      (true, true) => '$title: $previewBody',
      (true, false) => title,
      (false, true) => previewBody,
      _ => 'New message',
    };

    showUtopiaSnackBar(
      context,
      message: message,
      tone: UtopiaSnackBarTone.info,
    );
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
    int? notificationId,
  }) async {
    if (body.trim().isEmpty) {
      return;
    }

    final type = (data?['type'] ?? '').toString();
    final isChat = type == 'chat';
    final chatId = (data?['chatId'] ?? data?['chat_id'] ?? '').toString();

    final notifTag = (isChat && chatId.isNotEmpty)
        ? 'chat_$chatId'
        : (data?['messageId'] ??
            data?['waveId'] ??
            data?['linkDocId'] ??
            data?['followDocId'] ??
            data?['notificationId'] ??
            '${title}_$body').toString();
    final notifId = notificationId ?? (notifTag.hashCode & 0x7FFFFFFF);

    final senderName = (data?['senderName'] ?? data?['sender_name'] ?? title).toString();
    final themeColor = await getNotificationThemeColor();
    final List<AndroidNotificationAction>? actions = isChat
        ? buildChatActions(senderName: senderName)
        : null;

    final senderId = (data?['senderId'] ?? data?['sender_id'] ?? '').toString();
    final recipientId = (data?['recipientId'] ?? data?['recipient_id'] ?? data?['recipientUid'] ?? '').toString();

    final payloadString = jsonEncode({
      'title': title,
      'body': body,
      'tag': notifTag,
      'type': type,
      'senderId': senderId,
      'recipientId': recipientId,
      'chatId': chatId,
      'senderName': senderName,
      'data': data ?? const <String, dynamic>{},
    });

    final StyleInformation styleInformation;
    final unreadCountStr = (data?['unreadCount'] ?? data?['unread_count'] ?? '').toString();
    final unreadCount = int.tryParse(unreadCountStr);
    if (isChat && chatId.isNotEmpty) {
      final messageList = await getAccumulatedChatMessages(
        chatId: chatId,
        senderName: senderName,
        senderId: senderId,
        newBody: body,
        unreadCount: unreadCount,
      );
      const mePerson = Person(
        name: 'Me',
        key: 'me',
      );
      styleInformation = MessagingStyleInformation(
        mePerson,
        conversationTitle: null,
        groupConversation: false,
        messages: messageList,
      );
    } else if (isChat) {
      final senderPerson = Person(
        name: senderName.isNotEmpty ? senderName : 'Friend',
        key: senderId.isNotEmpty ? senderId : null,
        important: true,
        icon: const DrawableResourceAndroidIcon('ic_notification_large'),
      );
      const mePerson = Person(
        name: 'Me',
        key: 'me',
      );
      styleInformation = MessagingStyleInformation(
        mePerson,
        conversationTitle: null,
        groupConversation: false,
        messages: [
          Message(
            body,
            DateTime.now(),
            senderPerson,
          ),
        ],
      );
    } else {
      styleInformation = BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'UTOPIA',
      );
    }

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
    );

    // 1. Attempt display with large icon
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          isChat ? 'utopia_chat_messages_v4' : 'utopia_high_importance_v3',
          isChat ? 'UTOPIA Direct Messages' : 'UTOPIA Notifications',
          channelDescription: isChat
              ? 'Real-time conversational chat messages from friends'
              : 'Live alerts, chat messages, and reminders from UTOPIA',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          category: isChat ? AndroidNotificationCategory.message : AndroidNotificationCategory.event,
          tag: null,
          groupKey: (isChat && chatId.isNotEmpty) ? 'chat_$chatId' : null,
          color: themeColor,
          actions: actions,
          styleInformation: styleInformation,
          icon: 'ic_notification',
          largeIcon: const DrawableResourceAndroidBitmap('ic_notification_large'),
        ),
        iOS: iosDetails,
      );

      // Cancel any system-generated notification from Google Play Services (which uses id 0 or collapseTag)
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      try {
        if (notifTag.isNotEmpty) {
          await androidPlugin?.cancel(0, tag: notifTag);
        }
        await androidPlugin?.cancel(0);
        final active = await androidPlugin?.getActiveNotifications();
        if (active != null) {
          for (final n in active) {
            if (n.id != notifId && (n.tag == notifTag || (isChat && n.tag == 'chat_$chatId'))) {
              await androidPlugin?.cancel(n.id ?? 0, tag: n.tag);
            }
          }
        }
      } catch (_) {}

      await _localNotifications.show(
        notifId,
        title,
        body,
        details,
        payload: payloadString,
      );
      return;
    } catch (e) {
      debugPrint('NOTIF: Failed to show local notification with large icon: $e. Retrying without large icon...');
    }

    // 2. Fallback without large icon
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          isChat ? 'utopia_chat_messages_v4' : 'utopia_high_importance_v3',
          isChat ? 'UTOPIA Direct Messages' : 'UTOPIA Notifications',
          channelDescription: isChat
              ? 'Real-time conversational chat messages from friends'
              : 'Live alerts, chat messages, and reminders from UTOPIA',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          category: isChat ? AndroidNotificationCategory.message : AndroidNotificationCategory.event,
          tag: null,
          groupKey: (isChat && chatId.isNotEmpty) ? 'chat_$chatId' : null,
          color: themeColor,
          actions: actions,
          styleInformation: styleInformation,
          icon: 'ic_notification',
        ),
        iOS: iosDetails,
      );

      await _localNotifications.show(
        notifId,
        title,
        body,
        details,
        payload: payloadString,
      );
    } catch (e) {
      debugPrint('NOTIF: Failed to show local notification: $e');
    }
  }

  static Future<void> _handleNotificationPayload(String payload) async {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        final title = (decoded['title'] ?? '').toString();
        final body = (decoded['body'] ?? '').toString();
        final chatId = (decoded['chatId'] ?? decoded['data']?['chatId'] ?? '').toString();
        if (chatId.isNotEmpty) {
          unawaited(clearChatNotification(chatId));
        }
        final data = decoded['data'] is Map
            ? Map<String, dynamic>.from(decoded['data'] as Map)
            : const <String, dynamic>{};
        await _handleNotificationInteraction(
          title: title,
          body: body,
          data: data,
        );
        return;
      }
    } catch (_) {}

    final parts = payload.split('||');
    final title = parts.isNotEmpty ? parts[0] : '';
    final body = parts.length > 1 ? parts[1] : '';
    await _handleNotificationInteraction(
      title: title,
      body: body,
      data: const <String, dynamic>{},
    );
  }

  static Future<void> _handleRemoteMessageInteraction(
    RemoteMessage message,
  ) async {
    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    return _handleNotificationInteraction(
      title: title,
      body: body,
      data: Map<String, dynamic>.from(message.data),
    );
  }

  static Future<void> _handleNotificationInteraction({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    final navigator = await _waitForNavigator();
    if (navigator == null) {
      debugPrint('NOTIF: Navigator not ready to handle notification interaction');
      return;
    }

    final type = (data['type'] ?? '').toString();
    if (type == 'uni_chat' || type == 'global_chat') {
      final universityId = (data['universityId'] ?? data['university_id'] ?? '').toString();
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => UniChatScreen(
            universityId: universityId.isNotEmpty
                ? universityId
                : (U.cachedUniversityId.isNotEmpty
                    ? U.cachedUniversityId
                    : 'support'),
          ),
        ),
      );
      return;
    }
    if (type == 'chat') {
      final senderId = (data['senderId'] ?? data['sender_id'] ?? '').toString();
      final senderName = (data['senderName'] ?? data['sender_name'] ?? title)
          .toString();
      if (senderId.isNotEmpty) {
        final opened = await _openChatFromNotification(
          otherUserId: senderId,
          fallbackName: senderName,
        );
        if (opened) {
          return;
        }
      }
      return;
    }
    if (type == 'wave' || type == 'follow_request' || type == 'follow_accept' || type == 'link_request' || type == 'link_accept' || type == 'general' || type == 'broadcast') {
      await navigator.push(
        MaterialPageRoute(builder: (_) => const EventNotificationsScreen()),
      );
      return;
    }
    if (type == 'certificate') {
      await navigator.push(
        MaterialPageRoute(builder: (_) => const EventCertificatesScreen()),
      );
      return;
    }
    if (type == 'timetable') {
      await navigator.push(
        MaterialPageRoute(builder: (_) => const TimetableScreen()),
      );
      return;
    }
    if (type == 'delve_reminder' || type == 'delve') {
      await navigator.push(
        MaterialPageRoute(builder: (_) => const DelveShell()),
      );
      return;
    }
    if (type == 'focus_reminder' || type == 'focus') {
      await navigator.push(
        MaterialPageRoute(builder: (_) => const HabitTrackerScreen()),
      );
      return;
    }
    if (type == 'sci_wordle' || type == 'sciwordle') {
      await navigator.push(
        MaterialPageRoute(builder: (_) => const SciwordleScreen()),
      );
      return;
    }
  }

  /// Dispatches push & in-app notification via Firebase Firestore 'notifications' collection.
  /// Cloud Function `onNotificationCreated` automatically delivers the high-importance FCM push.
  static Future<void> dispatchPushNotification({
    required String recipientId,
    required String title,
    required String message,
    required String type, // 'chat', 'wave', 'link_request', 'link_accept', 'follow_request', 'follow_accept', 'broadcast', 'general'
    String? chatId,
    Map<String, dynamic>? extraData,
    bool allowSelf = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final senderId = user?.uid ?? '';
    final senderName = user?.displayName ?? user?.email ?? 'Student';
    final senderPhotoUrl = user?.photoURL;
    if (senderId.isEmpty || recipientId.isEmpty) {
      return;
    }
    if (!allowSelf && recipientId == senderId && type != 'general') {
      return;
    }

    try {
      final notifDoc = FirebaseFirestore.instance.collection('notifications').doc();
      await notifDoc.set({
        'id': notifDoc.id,
        'recipientId': recipientId,
        'senderId': senderId,
        'senderName': senderName,
        'senderPhotoUrl': senderPhotoUrl,
        'title': title,
        'body': message,
        'type': type,
        'chatId': chatId ?? '',
        'data': extraData ?? {},
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('Firebase Notification queued to Firestore for $recipientId (type: $type)');
    } catch (e) {
      debugPrint('Error creating notification in Firestore: $e');
    }
  }

  static Future<bool> _openChatFromNotification({
    required String otherUserId,
    required String fallbackName,
  }) async {
    final navigator = await _waitForNavigator();
    if (navigator == null) {
      return false;
    }

    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(otherUserId)
          .get();
      final data = userSnap.data() ?? const <String, dynamic>{};
      final displayName = ((data['displayName'] ?? fallbackName).toString())
          .trim();
      final email = (data['email'] ?? '').toString();
      final photoUrl = (data['photoUrl'] ?? '').toString();

      await navigator.push(
        buildForwardRoute(
          ChatScreen(
            otherUserId: otherUserId,
            displayName: displayName.isEmpty ? 'Friend' : displayName,
            email: email,
            photoUrl: photoUrl.isEmpty ? null : photoUrl,
          ),
        ),
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> sendPersonalTestNotification({
    required String message,
  }) async {
    await initialize();
    await _showLocalNotification(
      title: 'Test Notification',
      body: message,
      data: const <String, dynamic>{'type': 'general'},
    );
    debugPrint("NOTIF: Test notification sent");
  }

  static Future<void> sendCertificateNotification({
    required String title,
    required String body,
  }) async {
    await initialize();
    await _showLocalNotification(
      title: title,
      body: body,
      data: const <String, dynamic>{'type': 'certificate'},
    );
  }

  static Future<bool> scheduleDailyTimetableNotification({
    required int hour,
    required int minute,
  }) async {
    if (!PlatformSupport.supportsNotifications) {
      debugPrint("NOTIF: Notifications not supported on this platform");
      return false;
    }
    try {
      // Ensure service is initialized
      await initialize();
      await _ensureTimezone();
      final localLocation = tz.local;

      // Cancel all existing timetable notifications
      await _localNotifications.cancel(100);
      for (int i = 101; i <= 107; i++) {
        await _localNotifications.cancel(i);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('timetable_notif_hour', hour);
      await prefs.setInt('timetable_notif_minute', minute);
      await prefs.setBool('timetable_notif_enabled', true);

      UserTimetable? timetable;
      try {
        timetable = await UserTimetableService.getTimetable();
      } catch (e) {
        debugPrint("NOTIF: Could not fetch timetable for dynamic scheduling: $e");
      }

      if (timetable == null || timetable.week.isEmpty) {
        // Fallback to scheduling a single daily notification with generic text
        debugPrint("NOTIF: Timetable is empty, scheduling generic notification.");
        final now = tz.TZDateTime.now(localLocation);
        var scheduledDate = tz.TZDateTime(
          localLocation,
          now.year,
          now.month,
          now.day,
          hour,
          minute,
        );
        if (scheduledDate.isBefore(now)) {
          scheduledDate = scheduledDate.add(const Duration(days: 1));
        }

        await _scheduleSingleZoned(
          id: 100,
          title: 'Daily Timetable',
          body: 'Time to check your classes for today!',
          scheduledDate: scheduledDate,
          components: DateTimeComponents.time,
        );
      } else {
        // Schedule 6 weekly notifications, one for each weekday (1 = Monday, 6 = Saturday)
        debugPrint("NOTIF: Timetable found, scheduling weekly weekday notifications.");
        final now = tz.TZDateTime.now(localLocation);
        final dayPrefixes = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

        for (int i = 1; i <= 6; i++) {
          final targetWeekday = i; // 1 = Monday, 6 = Saturday
          var scheduledDate = tz.TZDateTime(
            localLocation,
            now.year,
            now.month,
            now.day,
            hour,
            minute,
          );
          while (scheduledDate.weekday != targetWeekday || scheduledDate.isBefore(now)) {
            scheduledDate = scheduledDate.add(const Duration(days: 1));
          }

          final prefix = dayPrefixes[i - 1];
          final dayData = timetable.week.firstWhere(
            (d) => d.day.toLowerCase().startsWith(prefix),
            orElse: () => const TimetableDay(day: '', slots: []),
          );

          final activeSlots = dayData.slots
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();

          String bodyText = 'No classes today! Enjoy your free time.';
          if (activeSlots.isNotEmpty) {
            bodyText = 'Today\'s Classes: ${activeSlots.join(", ")}';
          }

          final dayId = 100 + i;
          await _scheduleSingleZoned(
            id: dayId,
            title: 'Your Timetable for ${dayData.day.isNotEmpty ? dayData.day : prefix.toUpperCase()}',
            body: bodyText,
            scheduledDate: scheduledDate,
            components: DateTimeComponents.dayOfWeekAndTime,
          );
        }
      }
      return true;
    } catch (e) {
      debugPrint("NOTIF: Failed to schedule timetable notification: $e");
      return false;
    }
  }

  // Robust zoned scheduling wrapper that always succeeds even if a resource (like largeIcon) is missing,
  // or if exact alarm permissions are denied.
  static Future<void> _safeZonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required String channelId,
    required String channelName,
    required String channelDescription,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    List<AndroidNotificationAction>? actions;
    if (payload != null) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          final type = (decoded['type'] ?? decoded['data']?['type'] ?? '').toString();
          final payloadData = decoded['data'] is Map
              ? Map<String, dynamic>.from(decoded['data'] as Map)
              : decoded;
          actions = _getActionsForType(type, payloadData);
        }
      } catch (_) {}
    }

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      presentBanner: true,
      presentList: true,
    );

    // Try INEXACT scheduling (Standard Google Play compliant mode)
    try {
      await _localNotifications.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            icon: 'ic_notification',
            actions: actions,
          ),
          iOS: darwinDetails,
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      );
      debugPrint("NOTIF: Scheduled successfully (inexact) for ID $id at $scheduledDate");
    } catch (e) {
      debugPrint("NOTIF: Failed to schedule local notification for ID $id: $e");
    }
  }

  // Private helper to avoid code duplication and support robust exact/inexact fallback
  static Future<void> _scheduleSingleZoned({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required DateTimeComponents components,
  }) async {
    final payloadString = jsonEncode({
      'title': title,
      'body': body,
      'data': {
        'type': 'timetable'
      }
    });

    await _safeZonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      channelId: 'utopia_high_importance_v3',
      channelName: 'UTOPIA Notifications',
      channelDescription: 'Daily timetable reminders',
      payload: payloadString,
      matchDateTimeComponents: components,
    );
  }

  static Future<void> cancelTimetableNotification() async {
    if (!PlatformSupport.supportsNotifications) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('timetable_notif_enabled', false);
      await _localNotifications.cancel(100);
      for (int i = 101; i <= 107; i++) {
        await _localNotifications.cancel(i);
      }
      debugPrint("NOTIF: Timetable notifications cancelled successfully.");
    } catch (e) {
      // Ignored
    }
  }

  // ─── SciWordle Daily Notifications ───────────────────────────────────────
  static const int sciwordleMorningNotifId = 201;
  static const int sciwordleAfternoonNotifId = 202;
  static const int sciwordleEveningNotifId = 203;

  /// Schedule 3 daily zoned repeating notifications for SciWordle puzzle sessions.
  static Future<bool> scheduleSciwordleDailyNotifications({
    bool morning = true,
    bool afternoon = true,
    bool evening = true,
  }) async {
    if (!PlatformSupport.supportsNotifications) return false;
    try {
      await initialize();
      await _ensureTimezone();
      final localLocation = tz.local;
      final now = tz.TZDateTime.now(localLocation);

      // Morning Notification: 8:00 AM (08:00)
      if (morning) {
        var morningDate = tz.TZDateTime(localLocation, now.year, now.month, now.day, 8, 0);
        if (morningDate.isBefore(now)) {
          morningDate = morningDate.add(const Duration(days: 1));
        }
        await _safeZonedSchedule(
          id: sciwordleMorningNotifId,
          title: 'SciWordle • Morning Edition is Live! 🌅',
          body: 'Crack today\'s morning science mystery and build your streak!',
          scheduledDate: morningDate,
          channelId: 'utopia_high_importance_v3',
          channelName: 'UTOPIA Notifications',
          channelDescription: 'SciWordle daily puzzle alerts',
          matchDateTimeComponents: DateTimeComponents.time,
          payload: jsonEncode({
            'title': 'SciWordle • Morning Edition is Live! 🌅',
            'body': 'Crack today\'s morning science mystery and build your streak!',
            'data': {'type': 'sciwordle'}
          }),
        );
      } else {
        await _localNotifications.cancel(sciwordleMorningNotifId);
      }

      // Afternoon Notification: 11:00 AM (11:00)
      if (afternoon) {
        var afternoonDate = tz.TZDateTime(localLocation, now.year, now.month, now.day, 11, 0);
        if (afternoonDate.isBefore(now)) {
          afternoonDate = afternoonDate.add(const Duration(days: 1));
        }
        await _safeZonedSchedule(
          id: sciwordleAfternoonNotifId,
          title: 'SciWordle • Afternoon Edition Unlocked! ☀️',
          body: 'A brand new science puzzle is waiting for your deduction.',
          scheduledDate: afternoonDate,
          channelId: 'utopia_high_importance_v3',
          channelName: 'UTOPIA Notifications',
          channelDescription: 'SciWordle daily puzzle alerts',
          matchDateTimeComponents: DateTimeComponents.time,
          payload: jsonEncode({
            'title': 'SciWordle • Afternoon Edition Unlocked! ☀️',
            'body': 'A brand new science puzzle is waiting for your deduction.',
            'data': {'type': 'sciwordle'}
          }),
        );
      } else {
        await _localNotifications.cancel(sciwordleAfternoonNotifId);
      }

      // Evening Notification: 4:00 PM (16:00)
      if (evening) {
        var eveningDate = tz.TZDateTime(localLocation, now.year, now.month, now.day, 16, 0);
        if (eveningDate.isBefore(now)) {
          eveningDate = eveningDate.add(const Duration(days: 1));
        }
        await _safeZonedSchedule(
          id: sciwordleEveningNotifId,
          title: 'SciWordle • Evening Edition is Ready! 🌙',
          body: 'Solve the evening puzzle to climb this week\'s leaderboard!',
          scheduledDate: eveningDate,
          channelId: 'utopia_high_importance_v3',
          channelName: 'UTOPIA Notifications',
          channelDescription: 'SciWordle daily puzzle alerts',
          matchDateTimeComponents: DateTimeComponents.time,
          payload: jsonEncode({
            'title': 'SciWordle • Evening Edition is Ready! 🌙',
            'body': 'Solve the evening puzzle to climb this week\'s leaderboard!',
            'data': {'type': 'sciwordle'}
          }),
        );
      } else {
        await _localNotifications.cancel(sciwordleEveningNotifId);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sciwordle_notif_enabled', morning || afternoon || evening);
      await prefs.setBool('sciwordle_notif_morning', morning);
      await prefs.setBool('sciwordle_notif_afternoon', afternoon);
      await prefs.setBool('sciwordle_notif_evening', evening);

      return true;
    } catch (e) {
      debugPrint("NOTIF: Error scheduling SciWordle notifications: $e");
      return false;
    }
  }

  /// Cancels all SciWordle scheduled notifications.
  static Future<void> cancelSciwordleNotifications() async {
    if (!PlatformSupport.supportsNotifications) return;
    try {
      await _localNotifications.cancel(sciwordleMorningNotifId);
      await _localNotifications.cancel(sciwordleAfternoonNotifId);
      await _localNotifications.cancel(sciwordleEveningNotifId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sciwordle_notif_enabled', false);
      debugPrint("NOTIF: SciWordle notifications cancelled.");
    } catch (_) {}
  }

  /// Check if exact alarms are permitted (Android 12+)
  static Future<bool> canScheduleExactNotifications() async {
    if (!PlatformSupport.isAndroid) return true;
    try {
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final canExact = await androidPlugin.canScheduleExactNotifications();
        return canExact ?? true;
      }
      return true;
    } catch (e) {
      return true;
    }
  }

  /// Open system settings for exact alarm permission (Android 12+)
  static Future<void> openExactAlarmSettings() async {
    if (!PlatformSupport.isAndroid) return;
    try {
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestExactAlarmsPermission();
      }
    } catch (e) {
      debugPrint("NOTIF: Error requesting exact alarm permission: $e");
    }
  }

  /// Check if battery optimization is ignored/disabled for the app.
  static Future<bool> isBatteryOptimizationIgnored() async {
    if (!PlatformSupport.isAndroid) return true;
    try {
      const platform = MethodChannel('utopia_app/app_update');
      final bool? ignored = await platform.invokeMethod<bool>('isBatteryOptimizationIgnored');
      return ignored ?? true;
    } catch (e) {
      debugPrint("NOTIF: Error checking battery optimization: $e");
      return true;
    }
  }

  /// Direct user to system settings to disable battery optimization.
  static Future<void> requestIgnoreBatteryOptimization() async {
    if (!PlatformSupport.isAndroid) return;
    try {
      const platform = MethodChannel('utopia_app/app_update');
      await platform.invokeMethod('requestIgnoreBatteryOptimization');
    } catch (e) {
      debugPrint("NOTIF: Error requesting ignore battery optimization: $e");
    }
  }

  static int _notificationIdFromUuid(String uuid) {
    return uuid.hashCode & 0x7FFFFFF0;
  }

  static Future<void> scheduleFocusReminder(FocusReminder reminder) async {
    if (!PlatformSupport.supportsNotifications || reminder.id == null) {
      debugPrint("NOTIF: Cannot schedule reminder. Supported: ${PlatformSupport.supportsNotifications}, ID: ${reminder.id}");
      return;
    }
    try {
      debugPrint("NOTIF: Starting scheduling for reminder: ID=${reminder.id}, Label=${reminder.label}, Type=${reminder.type}, Time=${reminder.reminderTime}, Active=${reminder.isActive}");
      await initialize();
      final ist = tz.local;
      
      // Cancel any pre-existing notifications for this reminder
      await cancelFocusReminder(reminder.id!);

      if (!reminder.isActive) {
        debugPrint("NOTIF: Reminder is inactive, skipping schedule.");
        return;
      }

      final timeParts = reminder.reminderTime.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final baseId = _notificationIdFromUuid(reminder.id!);
      final now = tz.TZDateTime.now(ist);
      debugPrint("NOTIF: Hashed baseId=$baseId. Current timezone time: $now");

      final payloadString = jsonEncode({
        'type': 'focus_reminder',
        'reminderId': reminder.id,
        'habitId': reminder.habitId,
        'userId': reminder.userId,
        'label': reminder.label,
      });

      final notifTitle = reminder.label.trim().isEmpty ? 'Reminder' : reminder.label;
      final notifBody = (reminder.description != null && reminder.description!.isNotEmpty)
          ? reminder.description!
          : reminder.scheduleSummary;

      if (reminder.type == 'daily') {
        debugPrint("NOTIF: Scheduling daily repeating reminder: ${reminder.label} at $hour:$minute");
        var scheduledDate = tz.TZDateTime(ist, now.year, now.month, now.day, hour, minute);
        if (scheduledDate.isBefore(now)) {
          scheduledDate = scheduledDate.add(const Duration(days: 1));
        }

        await _safeZonedSchedule(
          id: baseId,
          title: notifTitle,
          body: notifBody,
          scheduledDate: scheduledDate,
          channelId: 'utopia_high_importance_v3',
          channelName: 'UTOPIA Notifications',
          channelDescription: 'Focus reminders and task alerts',
          matchDateTimeComponents: DateTimeComponents.time,
          payload: payloadString,
        );
      } else if (reminder.type == 'one_time' && reminder.remindDate != null) {
        final dateParts = reminder.remindDate!.split('-');
        final year = int.parse(dateParts[0]);
        final month = int.parse(dateParts[1]);
        final day = int.parse(dateParts[2]);

        var scheduledDate = tz.TZDateTime(ist, year, month, day, hour, minute);
        debugPrint("NOTIF: Calculated scheduled date for one_time reminder: $scheduledDate");
        if (scheduledDate.isBefore(now)) {
          debugPrint("NOTIF: Scheduled date is in the past ($scheduledDate < $now), skipping scheduling.");
          return;
        }

        await _safeZonedSchedule(
          id: baseId,
          title: notifTitle,
          body: notifBody,
          scheduledDate: scheduledDate,
          channelId: 'utopia_high_importance_v3',
          channelName: 'UTOPIA Notifications',
          channelDescription: 'Focus reminders and task alerts',
          payload: payloadString,
        );
      } else if (reminder.type == 'weekly' && reminder.weekdays != null) {
        debugPrint("NOTIF: Scheduling weekly reminder for weekdays: ${reminder.weekdays}");
        for (final weekday in reminder.weekdays!) {
          // Dart weekday: 1 = Mon, 7 = Sun. Our index: 0 = Mon, 6 = Sun.
          final targetWeekday = weekday + 1;
          
          // Find the next occurrence of this weekday
          var scheduledDate = tz.TZDateTime(ist, now.year, now.month, now.day, hour, minute);
          while (scheduledDate.weekday != targetWeekday || scheduledDate.isBefore(now)) {
            scheduledDate = scheduledDate.add(const Duration(days: 1));
          }

          final dayId = baseId + weekday;
          await _safeZonedSchedule(
            id: dayId,
            title: notifTitle,
            body: notifBody,
            scheduledDate: scheduledDate,
            channelId: 'utopia_high_importance_v3',
            channelName: 'UTOPIA Notifications',
            channelDescription: 'Focus reminders and task alerts',
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            payload: payloadString,
          );
        }
      } else if (reminder.type == 'monthly_date' && reminder.monthDay != null) {
        var scheduledDate = tz.TZDateTime(ist, now.year, now.month, reminder.monthDay!, hour, minute);
        if (scheduledDate.isBefore(now)) {
          // Move to next month
          scheduledDate = tz.TZDateTime(ist, now.year, now.month + 1, reminder.monthDay!, hour, minute);
        }

        await _safeZonedSchedule(
          id: baseId,
          title: notifTitle,
          body: notifBody,
          scheduledDate: scheduledDate,
          channelId: 'utopia_high_importance_v3',
          channelName: 'UTOPIA Notifications',
          channelDescription: 'Focus reminders and task alerts',
          matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
          payload: payloadString,
        );
      }
    } catch (e, stack) {
      debugPrint("NOTIF: Error scheduling focus reminder: $e");
      debugPrint("NOTIF_STACKTRACE: $stack");
    }
  }

  static Future<void> cancelFocusReminder(String reminderId) async {
    if (!PlatformSupport.supportsNotifications) return;
    try {
      final baseId = _notificationIdFromUuid(reminderId);
      debugPrint("NOTIF: Cancelling scheduled notifications for baseId=$baseId");
      // Cancel base ID (for one-time and monthly)
      await _localNotifications.cancel(baseId);
      // Cancel weekly weekday IDs
      for (int i = 0; i < 7; i++) {
        await _localNotifications.cancel(baseId + i);
      }
      debugPrint("NOTIF: Focus reminder cancelled successfully: $reminderId (baseId=$baseId)");
    } catch (e) {
      debugPrint("NOTIF: Error cancelling focus reminder: $e");
    }
  }

  @pragma('vm:entry-point')
  static Future<void> onDidReceiveBackgroundNotificationResponse(NotificationResponse response) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      if (response.actionId == 'action_reply' || response.actionId == 'action_mark_as_read') {
        if (response.payload != null && response.payload!.isNotEmpty) {
          await handleChatNotificationAction(
            actionId: response.actionId!,
            replyInput: response.input,
            payload: response.payload!,
            notificationId: response.id ?? 0,
          );
        }
        return;
      }
      if (response.actionId != null && response.actionId!.isNotEmpty && response.payload != null) {
        unawaited(_handleQuickAction(
          actionId: response.actionId!,
          payload: response.payload!,
          notificationId: response.id,
          input: response.input,
        ));
        return;
      }
      if (response.payload != null && response.payload!.isNotEmpty) {
        final payload = response.payload!;
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          final type = decoded['type']?.toString();
          if (type == 'focus_reminder') {
            final actionId = response.actionId;
            final habitId = decoded['habitId']?.toString();
            final userId = decoded['userId']?.toString();
            if (habitId != null && userId != null) {
              unawaited(_handleBackgroundHabitAction(
                actionId: actionId,
                habitId: habitId,
                userId: userId,
                notificationId: response.id,
              ));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error in onDidReceiveBackgroundNotificationResponse: $e');
    }
  }

  /// Directly processes interactive notification actions without opening the application.
  @pragma('vm:entry-point')
  static Future<void> handleChatNotificationAction({
    required String actionId,
    String? replyInput,
    required String payload,
    required int notificationId,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('[NOTIF_ACTION] ── START ── action=$actionId, notifId=$notificationId, input="$replyInput"');

    String notifTag = '';
    String chatId = '';

    try {
      // ── 1. Initialize Firebase ──────────────────────────────────────────
      try {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
        debugPrint('[NOTIF_ACTION] Firebase initialized');
      } catch (e) {
        debugPrint('[NOTIF_ACTION] Firebase.initializeApp (may already be init): $e');
      }

      // ── 2. Restore auth session (critical for Firestore writes) ─────────
      // Background isolates don't share auth state. Wait up to 5s for
      // Firebase to restore the persisted session from disk.
      if (FirebaseAuth.instance.currentUser == null) {
        debugPrint('[NOTIF_ACTION] Auth is null, waiting for session restore...');
        try {
          await FirebaseAuth.instance
              .authStateChanges()
              .firstWhere((u) => u != null)
              .timeout(const Duration(seconds: 4));
        } catch (_) {}

        for (int i = 0; i < 16 && FirebaseAuth.instance.currentUser == null; i++) {
          await Future.delayed(const Duration(milliseconds: 250));
        }
        if (FirebaseAuth.instance.currentUser != null) {
          debugPrint('[NOTIF_ACTION] Auth restored: uid=${FirebaseAuth.instance.currentUser?.uid}');
        }
      }

      // ── 3. Resolve sender UID ───────────────────────────────────────────
      final firebaseUser = FirebaseAuth.instance.currentUser;
      String myUid = firebaseUser?.uid ?? '';
      if (myUid.isEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          myUid = prefs.getString('cached_user_uid') ??
              prefs.getString('auth_uid') ??
              prefs.getString('last_known_uid') ??
              '';
        } catch (_) {}
      }

      // If still empty, the recipient of the incoming notification on this device is ME
      if (myUid.isEmpty) {
        try {
          final dynamic decodedRaw = jsonDecode(payload);
          if (decodedRaw is Map<String, dynamic>) {
            myUid = (decodedRaw['recipientId'] ??
                    decodedRaw['data']?['recipientId'] ??
                    '')
                .toString()
                .trim();
          }
        } catch (_) {}
      }

      if (myUid.isEmpty) {
        debugPrint('[NOTIF_ACTION] ✘ ABORT: Cannot determine sender UID for reply.');
        return;
      }
      debugPrint('[NOTIF_ACTION] Authenticated/Resolved as uid=$myUid (auth.currentUser=${firebaseUser?.uid})');

      // ── 4. Parse payload ────────────────────────────────────────────────
      final dynamic decodedRaw = jsonDecode(payload);
      if (decodedRaw is! Map<String, dynamic>) {
        debugPrint('[NOTIF_ACTION] Payload is not a valid map');
        return;
      }
      final decoded = decodedRaw;

      final data = decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : <String, dynamic>{};

      final otherUserId = (decoded['senderId'] ??
              data['senderId'] ??
              data['sender_id'] ??
              '')
          .toString()
          .trim();

      chatId = (decoded['chatId'] ??
              data['chatId'] ??
              data['chat_id'] ??
              '')
          .toString()
          .trim();

      notifTag = (decoded['tag'] ??
              data['tag'] ??
              (chatId.isNotEmpty ? 'chat_$chatId' : ''))
          .toString()
          .trim();

      debugPrint('[NOTIF_ACTION] otherUserId=$otherUserId, chatId=$chatId, notifTag=$notifTag');

      if (otherUserId.isEmpty) {
        debugPrint('[NOTIF_ACTION] Missing otherUserId');
        return;
      }

      if (chatId.isEmpty) {
        final ids = [myUid, otherUserId]..sort();
        chatId = '${ids.first}_${ids.last}';
        debugPrint('[NOTIF_ACTION] Derived chatId=$chatId');
      }

      final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);

      // ── 5. Handle REPLY action ──────────────────────────────────────────
      if (actionId == 'action_reply') {
        final replyText = replyInput?.trim() ?? '';
        if (replyText.isEmpty) {
          debugPrint('[NOTIF_ACTION] Reply text was empty, cancelling action');
          return;
        }

        final sentAt = Timestamp.now();
        final messageRef = chatRef.collection('messages').doc();

        // 5a. Write message & chat metadata atomically via batch
        debugPrint('[NOTIF_ACTION] Writing message & updating chat metadata in batch to ${messageRef.path}...');
        final batch = FirebaseFirestore.instance.batch();
        batch.set(messageRef, {
          'senderId': myUid,
          'text': replyText,
          'timestamp': sentAt,
          'read': false,
        });

        batch.set(chatRef, {
          'participants': [myUid, otherUserId]..sort(),
          'lastMessageRaw': replyText,
          'lastMessage': replyText,
          'lastMessageTime': sentAt,
          'unreadCount_$myUid': 0,
          'unreadCount_$otherUserId': FieldValue.increment(1),
        }, SetOptions(merge: true));

        await batch.commit();
        debugPrint('[NOTIF_ACTION] ✔ Message committed atomically to Firestore: "${replyText.length > 30 ? '${replyText.substring(0, 30)}...' : replyText}"');

        // 5b. Get sender display name for notification to friend
        String myDisplayName = 'Friend';
        try {
          final myDoc = await FirebaseFirestore.instance.collection('users').doc(myUid).get();
          myDisplayName = myDoc.data()?['displayName']?.toString() ??
              myDoc.data()?['email']?.toString() ??
              'Friend';
        } catch (_) {}

        // 5c. Write notification document so friend gets push notification
        try {
          final notifDoc = FirebaseFirestore.instance.collection('notifications').doc();
          await notifDoc.set({
            'id': notifDoc.id,
            'recipientId': otherUserId,
            'senderId': myUid,
            'senderName': myDisplayName,
            'type': 'chat',
            'title': myDisplayName,
            'body': replyText.length > 120 ? '${replyText.substring(0, 117)}...' : replyText,
            'chatId': chatId,
            'messageId': messageRef.id,
            'data': {
              'chatId': chatId,
              'senderId': myUid,
              'senderName': myDisplayName,
              'recipientId': otherUserId,
              'type': 'chat',
              'body': replyText,
            },
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
          debugPrint('[NOTIF_ACTION] ✔ Notification doc ${notifDoc.id} created for friend $otherUserId');
        } catch (e) {
          debugPrint('[NOTIF_ACTION] Non-fatal: notification doc write failed: $e');
        }

        // 5d. Record sent reply into local message thread
        await recordSentChatMessage(chatId: chatId, text: replyText);

        // 5e. Mark incoming unread messages from other user as read
        try {
          final unreadSnap = await chatRef
              .collection('messages')
              .where('senderId', isEqualTo: otherUserId)
              .where('read', isEqualTo: false)
              .get();

          if (unreadSnap.docs.isNotEmpty) {
            final readBatch = FirebaseFirestore.instance.batch();
            for (final doc in unreadSnap.docs) {
              readBatch.update(doc.reference, {'read': true});
            }
            await readBatch.commit();
            debugPrint('[NOTIF_ACTION] Marked ${unreadSnap.docs.length} messages as read');
          }
        } catch (e) {
          debugPrint('[NOTIF_ACTION] Non-fatal: marking unreads failed: $e');
        }

        debugPrint('[NOTIF_ACTION] ✔ Reply flow completed successfully');

      // ── 6. Handle MARK AS READ action ───────────────────────────────────
      } else if (actionId == 'action_mark_as_read') {
        if (chatId.isNotEmpty) {
          unawaited(clearChatNotification(chatId));
        }
        try {
          final unreadSnap = await chatRef
              .collection('messages')
              .where('senderId', isEqualTo: otherUserId)
              .where('read', isEqualTo: false)
              .get();

          final batch = FirebaseFirestore.instance.batch();
          for (final doc in unreadSnap.docs) {
            batch.update(doc.reference, {'read': true});
          }
          batch.set(chatRef, {
            'unreadCount_$myUid': 0,
          }, SetOptions(merge: true));

          await batch.commit();
          debugPrint('[NOTIF_ACTION] ✔ Chat marked as read: chatId=$chatId');
        } catch (e) {
          debugPrint('[NOTIF_ACTION] Error marking chat as read: $e');
        }
      }
    } catch (e, stack) {
      debugPrint('[NOTIF_ACTION] ✘ ERROR in $actionId: $e');
      debugPrint('[NOTIF_ACTION] Stacktrace: $stack');
    } finally {
      // ALWAYS dismiss the notification and clear the Android RemoteInput spinner
      try {
        final localNotif = FlutterLocalNotificationsPlugin();
        final resolvedId = (notificationId != 0)
            ? notificationId
            : (chatId.isNotEmpty ? ('chat_$chatId'.hashCode & 0x7FFFFFFF) : 0);
        if (resolvedId != 0) {
          await localNotif.cancel(resolvedId);
          await localNotif.cancel(resolvedId, tag: 'chat_$chatId');
          if (notifTag.isNotEmpty) {
            await localNotif.cancel(resolvedId, tag: notifTag);
          }
          final androidPlugin = localNotif
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
          await androidPlugin?.cancel(resolvedId);
          await androidPlugin?.cancel(resolvedId, tag: 'chat_$chatId');
          if (notifTag.isNotEmpty) {
            await androidPlugin?.cancel(resolvedId, tag: notifTag);
          }
        }
        if (chatId.isNotEmpty) {
          await clearChatNotification(chatId);
        }
        debugPrint('[NOTIF_ACTION] ── END ── notification dismissed');
      } catch (cancelErr) {
        debugPrint('[NOTIF_ACTION] Error in finally dismissing notification: $cancelErr');
      }
    }
  }

  static Future<void> _handleBackgroundHabitAction({
    String? actionId,
    required String habitId,
    required String userId,
    int? notificationId,
  }) async {
    try {
      debugPrint("NOTIF: Handling background/foreground habit action: $actionId for habit: $habitId");
      try {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      } catch (_) {}

      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final db = FocusDatabaseService();
      final habit = await db.getHabit(habitId);
      final targetValue = habit?.targetValue ?? 1.0;
      final existingRecord = await db.getRecord(habitId, dateStr);

      final record = HabitRecord(
        id: existingRecord?.id ?? const Uuid().v4(),
        habitId: habitId,
        userId: userId,
        date: dateStr,
        value: actionId == 'action_completed' ? targetValue : 0.0,
        targetValue: targetValue,
        completed: actionId == 'action_completed',
        syncStatus: 'pending',
        updatedAt: DateTime.now(),
      );

      final supabaseService = FocusSupabaseService();
      await supabaseService.saveRecord(record);
      debugPrint("NOTIF: Background habit action success - saved HabitRecord: completed=${record.completed}");

      if (notificationId != null) {
        await _localNotifications.cancel(notificationId);
      }
    } catch (e) {
      debugPrint("NOTIF: Error in background habit action handler: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Quick Action Buttons for Notification Drawer
  // ---------------------------------------------------------------------------

  /// Returns the appropriate quick action buttons based on notification type.
  static List<AndroidNotificationAction>? _getActionsForType(
    String type,
    Map<String, dynamic>? data,
  ) {
    switch (type) {
      case 'follow_request':
      case 'link_request':
        return const [
          AndroidNotificationAction(
            'action_accept_link',
            '✓ Accept',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'action_decline_link',
            '✗ Decline',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ];

      case 'wave':
        final isReply = data?['isReply'] == true || data?['isReply'] == 'true';
        return [
          if (!isReply)
            const AndroidNotificationAction(
              'action_wave_back',
              '👋 Wave Back',
              showsUserInterface: false,
              cancelNotification: true,
            ),
          const AndroidNotificationAction(
            'action_reply_wave',
            '💬 Reply',
            inputs: [
              AndroidNotificationActionInput(
                label: 'Send a message...',
                allowFreeFormInput: true,
              ),
            ],
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ];

      case 'chat':
        return const [
          AndroidNotificationAction(
            'action_reply_chat',
            '💬 Reply',
            inputs: [
              AndroidNotificationActionInput(
                label: 'Type a reply...',
                allowFreeFormInput: true,
              ),
            ],
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'action_mark_read',
            '✓ Mark Read',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ];

      case 'uni_chat':
      case 'global_chat':
        return const [
          AndroidNotificationAction(
            'action_reply_uni_chat',
            '💬 Reply',
            inputs: [
              AndroidNotificationActionInput(
                label: 'Reply to channel...',
                allowFreeFormInput: true,
              ),
            ],
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'action_mark_read',
            '✓ Mark Read',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ];

      case 'focus_reminder':
        if (data?['habitId'] != null) {
          return const [
            AndroidNotificationAction(
              'action_completed',
              '✓ Completed',
              showsUserInterface: false,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              'action_not_done',
              '✗ Not Done',
              showsUserInterface: false,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              'action_snooze_10m',
              '⏰ Snooze 10m',
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ];
        }
        return null;

      default:
        return null;
    }
  }

  /// Unified handler for all quick action button presses and inline direct replies from notification drawer.
  static Future<void> _handleQuickAction({
    required String actionId,
    required String payload,
    int? notificationId,
    String? input,
  }) async {
    try {
      debugPrint('NOTIF_ACTION: Handling quick action: $actionId, input: $input');
      try {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      } catch (_) {}

      Map<String, dynamic> decoded = {};
      Map<String, dynamic> data = {};
      try {
        final raw = jsonDecode(payload);
        if (raw is Map<String, dynamic>) {
          decoded = raw;
          data = raw['data'] is Map
              ? Map<String, dynamic>.from(raw['data'] as Map)
              : raw;
        }
      } catch (_) {}

      final replyText = (input ?? '').trim();

      switch (actionId) {
        // ── Direct Reply for 1-on-1 Chat ──
        case 'action_reply_chat':
          final senderId = (data['senderId'] ?? data['sender_id'] ?? '').toString();
          if (senderId.isNotEmpty && replyText.isNotEmpty) {
            await ChatService().sendMessage(
              otherUserId: senderId,
              text: replyText,
            );
            debugPrint('NOTIF_ACTION: Sent direct reply to $senderId: "$replyText"');
          }
          final notifId = (data['notificationId'] ?? data['messageId'] ?? '').toString();
          if (notifId.isNotEmpty) {
            await dismissNotification(notifId);
          }
          break;

        // ── Direct Reply for Uni / Campus Chat ──
        case 'action_reply_uni_chat':
          if (replyText.isNotEmpty) {
            final uniId = (data['universityId'] ?? data['university_id'] ?? '').toString();
            final effectiveUniId = uniId.isNotEmpty
                ? uniId
                : (U.cachedUniversityId.isNotEmpty ? U.cachedUniversityId : 'support');
            final cleanUniId = effectiveUniId.trim().toLowerCase();

            final user = FirebaseAuth.instance.currentUser;
            final currentUid = user?.uid ?? '';
            final currentName = user?.displayName ?? 'Student';
            final currentEmail = user?.email ?? '';

            if (cleanUniId.isNotEmpty && currentUid.isNotEmpty) {
              await FirebaseFirestore.instance
                  .collection('uni_chats')
                  .doc(cleanUniId)
                  .collection('messages')
                  .add({
                'text': replyText,
                'senderId': currentUid,
                'senderName': currentName,
                'senderEmail': currentEmail,
                'timestamp': FieldValue.serverTimestamp(),
                'views': [currentUid],
                'viewCount': 1,
              });
              debugPrint('NOTIF_ACTION: Sent uni chat reply to $cleanUniId: "$replyText"');
            }
          }
          final notifId = (data['notificationId'] ?? data['messageId'] ?? '').toString();
          if (notifId.isNotEmpty) {
            await dismissNotification(notifId);
          }
          break;

        // ── Direct Reply for Wave ──
        case 'action_reply_wave':
          final senderId = (data['senderId'] ?? data['sender_id'] ?? '').toString();
          if (senderId.isNotEmpty && replyText.isNotEmpty) {
            await ChatService().sendMessage(
              otherUserId: senderId,
              text: replyText,
            );
            debugPrint('NOTIF_ACTION: Sent wave reply message to $senderId: "$replyText"');
          }
          final notifId = (data['notificationId'] ?? data['waveId'] ?? '').toString();
          if (notifId.isNotEmpty) {
            await dismissNotification(notifId);
          }
          break;

        // ── Link / Follow Request Actions ──
        case 'action_accept_link':
          final requestDocId = (data['requestDocId'] ?? data['followDocId'] ?? data['notificationId'] ?? '').toString();
          if (requestDocId.isNotEmpty) {
            await FollowService().acceptRequest(requestDocId);
            debugPrint('NOTIF_ACTION: Accepted link request: $requestDocId');
          }
          break;

        case 'action_decline_link':
          final requestDocId = (data['requestDocId'] ?? data['followDocId'] ?? data['notificationId'] ?? '').toString();
          if (requestDocId.isNotEmpty) {
            await FollowService().declineRequest(requestDocId);
            debugPrint('NOTIF_ACTION: Declined link request: $requestDocId');
          }
          break;

        // ── Wave Back Action ──
        case 'action_wave_back':
          final senderId = (data['senderId'] ?? data['sender_id'] ?? '').toString();
          final waveId = (data['waveId'] ?? '').toString();
          if (senderId.isNotEmpty) {
            await PeopleInteractionService().sendWave(
              senderId,
              isReply: true,
              replyToWaveId: waveId.isNotEmpty ? waveId : null,
            );
            debugPrint('NOTIF_ACTION: Waved back at $senderId');
          }
          break;

        // ── Chat Mark Read Action ──
        case 'action_mark_read':
          final chatId = (data['chatId'] ?? data['chat_id'] ?? '').toString();
          final notifId = (data['notificationId'] ?? data['messageId'] ?? '').toString();
          if (notifId.isNotEmpty) {
            await dismissNotification(notifId);
          }
          if (chatId.isNotEmpty) {
            try {
              final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
              if (uid.isNotEmpty) {
                await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
                  'lastReadBy_$uid': FieldValue.serverTimestamp(),
                  'unreadCount_$uid': 0,
                }, SetOptions(merge: true));
              }
            } catch (_) {}
          }
          final uniId = (data['universityId'] ?? data['university_id'] ?? '').toString();
          if (uniId.isNotEmpty) {
            await UniChatService().markAsSeen(uniId);
          }
          debugPrint('NOTIF_ACTION: Marked chat as read: $chatId / $uniId');
          break;

        // ── Focus / Habit Actions ──
        case 'action_completed':
        case 'action_not_done':
          final habitId = (decoded['habitId'] ?? data['habitId'] ?? '').toString();
          final userId = (decoded['userId'] ?? data['userId'] ?? '').toString();
          if (habitId.isNotEmpty && userId.isNotEmpty) {
            await _handleBackgroundHabitAction(
              actionId: actionId,
              habitId: habitId,
              userId: userId,
              notificationId: notificationId,
            );
          }
          break;

        case 'action_snooze_10m':
          final title = (decoded['title'] ?? data['title'] ?? 'Reminder').toString();
          final body = (decoded['body'] ?? data['body'] ?? '').toString();
          final snoozeId = ((notificationId ?? 9999) + 50000) & 0x7FFFFFFF;
          final snoozeTime = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 10));
          await _safeZonedSchedule(
            id: snoozeId,
            title: title,
            body: body,
            scheduledDate: snoozeTime,
            channelId: 'utopia_high_importance_v3',
            channelName: 'UTOPIA Notifications',
            channelDescription: 'Snoozed reminders',
            payload: payload,
          );
          debugPrint('NOTIF_ACTION: Snoozed reminder for 10 minutes: $snoozeId');
          break;
      }

      // Dismiss the notification from the drawer after action
      if (notificationId != null) {
        await _localNotifications.cancel(notificationId);
      }
    } catch (e) {
      debugPrint('NOTIF_ACTION: Error handling quick action $actionId: $e');
    }
  }

  static Future<void> _saveTokenToFirestore(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && token.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcmToken': token,
          'fcmTokens': FieldValue.arrayUnion([token]),
          'email': user.email,
          'displayName': user.displayName ?? '',
          'tokenUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('FCM: Successfully registered token for ${user.uid}');
      }
    } catch (e) {
      debugPrint('FCM: Error saving token to Firestore: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Delve Vocabulary Reminders (IDs 200, 201, 202)
  // ---------------------------------------------------------------------------

  static const int _delveNotifMorningId = 200;
  static const int _delveNotifAfternoonId = 201;
  static const int _delveNotifEveningId = 202;

  /// Schedule 3 daily notifications for Delve vocabulary session reminders.
  /// Morning (9 AM), Afternoon (2 PM), Evening (8 PM).
  static Future<void> scheduleDelveReminders() async {
    if (!PlatformSupport.supportsNotifications) return;
    try {
      await initialize();
      await _ensureTimezone();
      final localLocation = tz.local;
      final now = tz.TZDateTime.now(localLocation);

      // Clean up previous Delve notifications before scheduling to prevent duplicates
      await _localNotifications.cancel(_delveNotifMorningId);
      await _localNotifications.cancel(_delveNotifAfternoonId);
      await _localNotifications.cancel(_delveNotifEveningId);

      final reminders = <Map<String, dynamic>>[
        {
          'id': _delveNotifMorningId,
          'hour': 9,
          'minute': 0,
          'title': 'Delve – Morning Review',
          'body': 'Start your day strong! Your vocabulary session is waiting.',
        },
        {
          'id': _delveNotifAfternoonId,
          'hour': 14,
          'minute': 0,
          'title': 'Delve – Afternoon Boost',
          'body': 'Quick break? Spend 2 minutes reviewing today\'s words.',
        },
        {
          'id': _delveNotifEveningId,
          'hour': 20,
          'minute': 0,
          'title': 'Delve – Evening Wrap-up',
          'body': 'Don\'t miss today\'s session! Complete it before bed.',
        },
      ];

      for (final r in reminders) {
        var scheduledDate = tz.TZDateTime(
          localLocation,
          now.year,
          now.month,
          now.day,
          r['hour'] as int,
          r['minute'] as int,
        );
        if (scheduledDate.isBefore(now)) {
          scheduledDate = scheduledDate.add(const Duration(days: 1));
        }

        final payloadString = jsonEncode({
          'title': r['title'],
          'body': r['body'],
          'data': {'type': 'delve_reminder'},
        });

        await _safeZonedSchedule(
          id: r['id'] as int,
          title: r['title'] as String,
          body: r['body'] as String,
          scheduledDate: scheduledDate,
          channelId: 'utopia_high_importance_v3',
          channelName: 'UTOPIA Notifications',
          channelDescription: 'Delve vocabulary session reminders',
          payload: payloadString,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
      debugPrint('NOTIF: Delve reminders scheduled (9 AM, 2 PM, 8 PM)');
    } catch (e) {
      debugPrint('NOTIF: Failed to schedule Delve reminders: $e');
    }
  }

  /// Cancel all Delve vocabulary session reminders.
  static Future<void> cancelDelveReminders() async {
    if (!PlatformSupport.supportsNotifications) return;
    try {
      await _localNotifications.cancel(_delveNotifMorningId);
      await _localNotifications.cancel(_delveNotifAfternoonId);
      await _localNotifications.cancel(_delveNotifEveningId);
      debugPrint('NOTIF: Delve reminders cancelled.');
    } catch (e) {
      debugPrint('NOTIF: Failed to cancel Delve reminders: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Cloud & Local Notification Clearance & Dismissal Synchronization
  // ---------------------------------------------------------------------------

  /// Fetches dismissed notification IDs merged from local preferences & Firestore user document.
  static Future<Set<String>> getDismissedNotificationIds() async {
    final Set<String> dismissed = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final localList = prefs.getStringList('dismissed_notifications') ?? [];
      dismissed.addAll(localList);

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final cloudList = userDoc.data()?['dismissedNotificationIds'];
        if (cloudList is List) {
          for (final item in cloudList) {
            if (item != null) dismissed.add(item.toString());
          }
          // Sync merged set back to local storage
          await prefs.setStringList('dismissed_notifications', dismissed.toList());
        }
      }
    } catch (e) {
      debugPrint('NOTIF: Error getting dismissed notification IDs: $e');
    }
    return dismissed;
  }

  /// Fetches the timestamp of when notifications were last cleared across devices.
  static Future<DateTime?> getLastNotificationsClearedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localStr = prefs.getString('last_notifications_cleared_at');
      DateTime? localDate = localStr != null ? DateTime.tryParse(localStr) : null;

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final rawCloud = userDoc.data()?['lastNotificationsClearedAt'];
        DateTime? cloudDate;
        if (rawCloud is Timestamp) {
          cloudDate = rawCloud.toDate();
        } else if (rawCloud is String) {
          cloudDate = DateTime.tryParse(rawCloud);
        }

        if (cloudDate != null) {
          if (localDate == null || cloudDate.isAfter(localDate)) {
            localDate = cloudDate;
            await prefs.setString('last_notifications_cleared_at', cloudDate.toIso8601String());
          }
        }
      }
      return localDate;
    } catch (e) {
      debugPrint('NOTIF: Error getting last notifications cleared timestamp: $e');
      return null;
    }
  }

  /// Dismiss a single notification/event/wave/certificate across local and cloud storage.
  static Future<void> dismissNotification(String notifId) async {
    if (notifId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final localList = prefs.getStringList('dismissed_notifications') ?? [];
      if (!localList.contains(notifId)) {
        localList.add(notifId);
        await prefs.setStringList('dismissed_notifications', localList);
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        // Persist to user profile in Firestore
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'dismissedNotificationIds': FieldValue.arrayUnion([notifId]),
        }, SetOptions(merge: true));

        // Delete from Firestore notifications collection if it exists
        try {
          await FirebaseFirestore.instance.collection('notifications').doc(notifId).delete();
        } catch (_) {}

        // Delete from Firestore waves collection if it exists
        try {
          await FirebaseFirestore.instance.collection('waves').doc(notifId).delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('NOTIF: Error dismissing notification $notifId: $e');
    }
  }

  /// Clear all notifications across local and cloud Firestore storage permanently.
  static Future<void> clearAllNotifications({List<String>? additionalIds}) async {
    try {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_notifications_cleared_at', now.toIso8601String());

      final localList = prefs.getStringList('dismissed_notifications') ?? [];
      final Set<String> updated = Set.from(localList);
      if (additionalIds != null && additionalIds.isNotEmpty) {
        updated.addAll(additionalIds);
      }
      await prefs.setStringList('dismissed_notifications', updated.toList());

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        final Map<String, dynamic> updateData = {
          'lastNotificationsClearedAt': FieldValue.serverTimestamp(),
        };
        if (updated.isNotEmpty) {
          updateData['dismissedNotificationIds'] = FieldValue.arrayUnion(updated.toList());
        }
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          updateData,
          SetOptions(merge: true),
        );

        // Delete all in-app notifications for this recipient
        try {
          final notifsSnap = await FirebaseFirestore.instance
              .collection('notifications')
              .where('recipientId', isEqualTo: uid)
              .get();
          if (notifsSnap.docs.isNotEmpty) {
            final batch = FirebaseFirestore.instance.batch();
            for (final doc in notifsSnap.docs) {
              batch.delete(doc.reference);
            }
            await batch.commit();
          }
        } catch (e) {
          debugPrint('NOTIF: Error deleting notifications batch: $e');
        }

        // Delete all waves received for this user
        try {
          final wavesSnap = await FirebaseFirestore.instance
              .collection('waves')
              .where('receiverId', isEqualTo: uid)
              .get();
          if (wavesSnap.docs.isNotEmpty) {
            final batch = FirebaseFirestore.instance.batch();
            for (final doc in wavesSnap.docs) {
              batch.delete(doc.reference);
            }
            await batch.commit();
          }
        } catch (e) {
          debugPrint('NOTIF: Error deleting waves batch: $e');
        }
      }
    } catch (e) {
      debugPrint('NOTIF: Error in clearAllNotifications: $e');
    }
  }

  /// Check if a notification item is dismissed either by ID or by clear timestamp.
  static bool isNotificationDismissed(
    String? id, {
    DateTime? createdAt,
    Set<String>? dismissedIds,
    DateTime? lastClearedAt,
  }) {
    if (id != null && id.isNotEmpty && dismissedIds != null && dismissedIds.contains(id)) {
      return true;
    }
    if (lastClearedAt != null && createdAt != null) {
      if (createdAt.isBefore(lastClearedAt) || createdAt.isAtSameMomentAs(lastClearedAt)) {
        return true;
      }
    }
    return false;
  }
}

