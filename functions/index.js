const {setGlobalOptions} = require("firebase-functions");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

// Global Cloud Functions configuration
setGlobalOptions({ maxInstances: 10 });

/**
 * Helper to retrieve all active FCM tokens for a user and send multicast push notification.
 * Cleans up invalid/expired tokens automatically and respects user notification preferences.
 */
async function sendPushToUser(recipientId, { title, body, data = {} }, category = null) {
  if (!recipientId) return;

  const resolvedBody = (body || "").toString().trim();
  if (!resolvedBody) {
    logger.info(`Skipping push notification with empty body for users/${recipientId}`);
    return;
  }

  const db = admin.firestore();
  const userSnap = await db.doc(`users/${recipientId}`).get();

  if (!userSnap.exists) {
    logger.warn(`Recipient document users/${recipientId} not found`);
    return;
  }

  const userData = userSnap.data() || {};

  // Check user notification preferences
  const notifPrefs = userData.notification_preferences || {};
  if (category) {
    if (userData[`notif_${category}_enabled`] === false || notifPrefs[category] === false) {
      logger.info(`Recipient users/${recipientId} has disabled notifications for category: ${category}`);
      return;
    }
  }

  let tokens = [];

  if (Array.isArray(userData.fcmTokens) && userData.fcmTokens.length > 0) {
    tokens = [...userData.fcmTokens];
  }
  if (userData.fcmToken && typeof userData.fcmToken === "string") {
    tokens.unshift(userData.fcmToken);
  }

  // Remove duplicates, empty strings, and limit to recent valid tokens
  tokens = [...new Set(tokens.filter((t) => typeof t === "string" && t.trim().length > 0))].slice(0, 3);

  if (tokens.length === 0) {
    logger.info(`Recipient users/${recipientId} has no registered FCM tokens`);
    return;
  }

  // Convert all data values to strings (FCM requirement)
  const stringifiedData = {};
  for (const [key, value] of Object.entries(data)) {
    if (value !== null && value !== undefined) {
      stringifiedData[key] = typeof value === "object" ? JSON.stringify(value) : String(value);
    }
  }
  stringifiedData.click_action = "FLUTTER_NOTIFICATION_CLICK";
  stringifiedData.title = title || "";
  stringifiedData.body = resolvedBody || "";

  const isChat = category === "chat" || stringifiedData.type === "chat";

  // Compute a deterministic collapse key / notification tag so devices deduplicate multiple deliveries
  const collapseTag = (isChat && stringifiedData.chatId)
    ? `chat_${stringifiedData.chatId}`
    : (stringifiedData.messageId ||
       stringifiedData.waveId ||
       stringifiedData.followDocId ||
       stringifiedData.notificationId ||
       (stringifiedData.type ? `${stringifiedData.type}` : "utopia_general"));

  const message = {
    tokens,
    ...(!isChat ? {
      notification: {
        title,
        body: resolvedBody,
      },
    } : {}),
    data: stringifiedData,
    android: {
      priority: "high",
      collapseKey: collapseTag,
      ...(!isChat ? {
        notification: {
          channelId: "utopia_high_importance_v3",
          priority: "high",
          defaultSound: true,
          defaultVibrateTimings: true,
          icon: "ic_notification",
          tag: collapseTag,
        },
      } : {}),
    },
    apns: {
      headers: {
        "apns-collapse-id": collapseTag,
      },
      payload: {
        aps: {
          alert: {
            title,
            body: resolvedBody,
          },
          sound: "default",
          badge: 1,
        },
      },
    },
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    logger.info(`Push notification sent to users/${recipientId} (${category || "general"})`, {
      successCount: response.successCount,
      failureCount: response.failureCount,
    });

    // Cleanup stale tokens if any failed
    if (response.failureCount > 0) {
      const tokensToRemove = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          const error = resp.error;
          if (
            error.code === "messaging/invalid-registration-token" ||
            error.code === "messaging/registration-token-not-registered"
          ) {
            tokensToRemove.push(tokens[idx]);
          }
        }
      });

      if (tokensToRemove.length > 0) {
        logger.info(`Removing ${tokensToRemove.length} expired FCM tokens for users/${recipientId}`);
        await db.doc(`users/${recipientId}`).update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokensToRemove),
        });
      }
    }
  } catch (err) {
    logger.error(`Error sending push notification to users/${recipientId}:`, err);
  }
}

// ─── TRIGGER 1: Chat Messages ───────────────────────────────────────────────
exports.onChatMessageCreated = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const message = snapshot.data();
    const chatId = event.params.chatId;
    const messageId = event.params.messageId;
    const senderId = message.senderId;
    const text = (message.text || "").toString().trim();

    if (!senderId || !text) return;

    const db = admin.firestore();
    const chatSnap = await db.doc(`chats/${chatId}`).get();
    if (!chatSnap.exists) return;

    const chat = chatSnap.data() || {};
    const participants = Array.isArray(chat.participants) ? chat.participants : [];
    const recipientId = participants.find((uid) => uid !== senderId);

    if (!recipientId) return;

    const senderSnap = await db.doc(`users/${senderId}`).get();
    const sender = senderSnap.data() || {};
    const senderName = sender.displayName || sender.email || "Student";
    const preview = text.length > 120 ? `${text.slice(0, 117)}...` : text;

    await sendPushToUser(
      recipientId,
      {
        title: senderName,
        body: preview,
        data: {
          type: "chat",
          chatId,
          messageId,
          senderId,
          senderName,
          recipientId,
          body: preview,
        },
      },
      "chat",
    );
  },
);

// ─── TRIGGER 2: Waves ───────────────────────────────────────────────────────
exports.onWaveCreated = onDocumentCreated(
  "waves/{waveId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const wave = snapshot.data();
    const receiverId = wave.receiverId;
    const senderId = wave.senderId;
    const senderName = wave.senderName || "Someone";
    const isReply = wave.isReply === true;

    if (!receiverId || receiverId === senderId) return;

    const title = isReply ? "Wave Back" : "Wave Received";
    const body = isReply
      ? `${senderName} waved back at you!`
      : `${senderName} waved at you! Tap to wave back`;

    await sendPushToUser(
      receiverId,
      {
        title,
        body,
        data: {
          type: "wave",
          senderId,
          senderName,
          waveId: event.params.waveId,
          isReply: isReply ? "true" : "false",
        },
      },
      "waves",
    );
  },
);

// ─── TRIGGER 3: Follow Requests & Follows ──────────────────────────────────
exports.onFollowCreated = onDocumentCreated(
  "follows/{followId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const follow = snapshot.data();
    const followerId = follow.followerId;
    const followingId = follow.followingId;
    const status = follow.status || "pending";

    if (!followingId || followingId === followerId) return;

    const db = admin.firestore();
    const followerSnap = await db.doc(`users/${followerId}`).get();
    const follower = followerSnap.data() || {};
    const followerName = follower.displayName || follower.email || "Someone";

    const title = status === "pending" ? "New Follow Request" : "New Follower 🎉";
    const body = status === "pending"
      ? `${followerName} sent you a follow request.`
      : `${followerName} started following you.`;

    await sendPushToUser(
      followingId,
      {
        title,
        body,
        data: {
          type: "follow_request",
          followerId,
          followerName,
          followDocId: event.params.followId,
        },
      },
      "follows",
    );
  },
);

// ─── TRIGGER 4: Follow Accepted ────────────────────────────────────────────
exports.onFollowUpdated = onDocumentUpdated(
  "follows/{followId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    // Check if status changed from pending -> accepted
    if (before.status === "pending" && after.status === "accepted") {
      const followerId = after.followerId;
      const followingId = after.followingId;

      if (!followerId) return;

      const db = admin.firestore();
      const followingSnap = await db.doc(`users/${followingId}`).get();
      const following = followingSnap.data() || {};
      const followingName = following.displayName || following.email || "Someone";

      await sendPushToUser(
        followerId,
        {
          title: "Follow Request Accepted ✨",
          body: `${followingName} accepted your follow request. You can now chat!`,
          data: {
            type: "follow_accept",
            followingId,
            followingName,
            followDocId: event.params.followId,
          },
        },
        "follows",
      );
    }
  },
);

// ─── TRIGGER 5: Direct Notification Documents ──────────────────────────────
exports.onNotificationCreated = onDocumentCreated(
  "notifications/{notificationId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const notif = snapshot.data();
    const recipientId = notif.recipientId || notif.uid;
    const title = notif.title || "UTOPIA";
    const body = notif.body || notif.message || "";
    const type = notif.type || "general";

    if (!recipientId || !body) return;

    // Determine notification category for user preference checks
    const category = type === "chat" ? "chat"
      : (type === "event" || type === "broadcast" || type === "certificate") ? "events"
      : null;

    await sendPushToUser(
      recipientId,
      {
        title,
        body,
        data: {
          type,
          notificationId: event.params.notificationId,
          chatId: notif.chatId || "",
          senderId: notif.senderId || "",
          senderName: notif.senderName || title || "",
          recipientId: recipientId,
          body: body,
          messageId: notif.messageId || "",
        },
      },
      category,
    );
  },
);


// ─── TRIGGER 6: Utopia Chat (Global / Campus Community Messages) ───────────
exports.onUniChatMessageCreated = onDocumentCreated(
  "uni_chats/{universityId}/messages/{messageId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const message = snapshot.data();
    const universityId = event.params.universityId;
    const messageId = event.params.messageId;
    const senderId = message.senderId;
    const senderName = message.senderName || "Student";
    const text = (message.text || "").toString().trim();

    if (!senderId || !text) return;

    const preview = text.length > 120 ? `${text.slice(0, 117)}...` : text;
    const db = admin.firestore();

    const replyTo = message.replyTo || null;
    let repliedUserId = null;

    if (replyTo && replyTo.senderId && replyTo.senderId !== senderId) {
      repliedUserId = replyTo.senderId;
    }

    const notifiedUids = new Set();
    notifiedUids.add(senderId);

    // 1. If someone replied to a specific user, deliver a "replied to you" notification
    if (repliedUserId) {
      try {
        const repliedUserSnap = await db.doc(`users/${repliedUserId}`).get();
        if (repliedUserSnap.exists) {
          const repliedUserData = repliedUserSnap.data() || {};
          const notifPrefs = repliedUserData.notification_preferences || {};
          const utopiaMode = (
            repliedUserData.notif_utopia_chat_mode ||
            notifPrefs.utopia_chat ||
            "replies"
          ).toString().toLowerCase();

          const isOverallChatEnabled = (
            repliedUserData.notif_chat_enabled !== false &&
            notifPrefs.chat !== false
          );

          if (isOverallChatEnabled && utopiaMode !== "off") {
            notifiedUids.add(repliedUserId);
            await sendPushToUser(
              repliedUserId,
              {
                title: `${senderName} replied to you in Utopia Chat`,
                body: preview,
                data: {
                  type: "uni_chat",
                  universityId,
                  messageId,
                  senderId,
                  senderName,
                  body: preview,
                },
              },
              null,
            );
          }
        }
      } catch (err) {
        logger.error(`Error processing reply notification for ${repliedUserId}:`, err);
      }
    }

    // 2. Notify users who selected "all" messages for Utopia Chat
    try {
      const allSubscribersSnap = await db
        .collection("users")
        .where("notif_utopia_chat_mode", "==", "all")
        .get();

      for (const doc of allSubscribersSnap.docs) {
        const uid = doc.id;
        if (notifiedUids.has(uid)) continue;

        const userData = doc.data() || {};
        const notifPrefs = userData.notification_preferences || {};
        if (userData.notif_chat_enabled === false || notifPrefs.chat === false) {
          continue;
        }

        // Check university scoping if applicable
        const userUni = userData.selectedUniversityId || userData.universityId || "";
        if (universityId !== "support" && userUni && userUni !== universityId) {
          continue;
        }

        notifiedUids.add(uid);
        await sendPushToUser(
          uid,
          {
            title: `Utopia Chat • ${senderName}`,
            body: preview,
            data: {
              type: "uni_chat",
              universityId,
              messageId,
              senderId,
              senderName,
              body: preview,
            },
          },
          null,
        );
      }
    } catch (err) {
      logger.error(`Error broadcasting all-messages push for uni_chat ${universityId}:`, err);
    }
  },
);

/**
 * Scheduled Cloud Function to reset SciWordle weekly scores and streaks
 * every Monday at 00:00 IST (Asia/Kolkata).
 */
exports.resetSciwordleWeeklyScores = onSchedule(
  {
    schedule: "0 0 * * 1", // Every Monday at 00:00
    timeZone: "Asia/Kolkata",
    retryCount: 3,
  },
  async (event) => {
    logger.info("Starting weekly SciWordle score reset for all users...");
    const db = admin.firestore();

    // Compute current weekKey for Asia/Kolkata: YYYY-W-MM-DD
    const now = new Date();
    const istOffsetMs = 5.5 * 60 * 60 * 1000;
    const istDate = new Date(now.getTime() + istOffsetMs);
    const dayOfWeek = istDate.getUTCDay(); // 0 is Sunday, 1 is Monday
    const diffToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
    const monday = new Date(istDate.getTime() - diffToMonday * 24 * 60 * 60 * 1000);
    const mY = String(monday.getUTCFullYear()).padStart(4, "0");
    const mM = String(monday.getUTCMonth() + 1).padStart(2, "0");
    const mD = String(monday.getUTCDate()).padStart(2, "0");
    const currentWeekKey = `${mY}-W-${mM}-${mD}`;

    try {
      const scoresSnap = await db.collection("sciwordle_scores").get();
      if (scoresSnap.empty) {
        logger.info("No sciwordle_scores documents found to reset.");
        return;
      }

      let batch = db.batch();
      let batchCount = 0;
      let totalReset = 0;

      for (const doc of scoresSnap.docs) {
        const data = doc.data() || {};
        if (data.weekKey !== currentWeekKey) {
          batch.update(doc.ref, {
            totalScore: 0,
            streak: 0,
            weekKey: currentWeekKey,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          batchCount++;

          // Also clean up users doc badge & weekly fields
          const userRef = db.collection("users").doc(doc.id);
          batch.set(
            userRef,
            {
              sciwordleScore: 0,
              sciwordleStreak: 0,
              sciwordleWeekKey: currentWeekKey,
              sciwordleTitle: admin.firestore.FieldValue.delete(),
            },
            { merge: true }
          );
          batchCount++;
          totalReset++;

          // Commit in chunks under the 500 operations Firestore limit
          if (batchCount >= 400) {
            await batch.commit();
            batch = db.batch();
            batchCount = 0;
          }
        }
      }

      if (batchCount > 0) {
        await batch.commit();
      }

      logger.info(`Successfully reset ${totalReset} SciWordle player scores for week ${currentWeekKey}.`);
    } catch (error) {
      logger.error("Error during weekly SciWordle score reset:", error);
    }
  }
);


