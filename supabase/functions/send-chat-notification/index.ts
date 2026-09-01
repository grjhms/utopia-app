// Supabase Edge Function: send-chat-notification
// Description: Receives chat notification data, reads the recipient's FCM token
//              from Firestore, and sends an instant push notification via FCM HTTP v1 API.
//              Replaces the slow GitHub Actions dispatch path for chat notifications.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID");
const FIREBASE_CLIENT_EMAIL = Deno.env.get("FIREBASE_CLIENT_EMAIL");
const FIREBASE_PRIVATE_KEY_RAW = Deno.env.get("FIREBASE_PRIVATE_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (!FIREBASE_PROJECT_ID || !FIREBASE_CLIENT_EMAIL || !FIREBASE_PRIVATE_KEY_RAW) {
      throw new Error("Missing Firebase service account environment variables.");
    }

    const body = await req.json();
    const {
      sender_id,
      sender_name,
      recipient_id,
      chat_id,
      message_text,
      title,
      type,
      custom_data,
    } = body;

    if (!recipient_id || !sender_id) {
      return new Response(JSON.stringify({ success: false, error: "Missing required fields: sender_id, recipient_id" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 400,
      });
    }

    const notifType = type || "chat";
    const notifTitle = title || sender_name || "New Notification";
    const notifBody = (message_text || "New message").length > 160
      ? `${(message_text || "New message").substring(0, 157)}...`
      : (message_text || "New message");

    // Step 1: Get OAuth2 access token for FCM
    const accessToken = await getAccessToken();

    // Step 2: Read recipient's FCM token from Firestore REST API
    const fcmToken = await getRecipientFCMToken(accessToken, recipient_id);
    if (!fcmToken) {
      console.log(`[send-chat-notification] No FCM token found for recipient: ${recipient_id}`);
      return new Response(JSON.stringify({ success: false, error: "Recipient has no FCM token registered." }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });
    }

    // Step 3: Send FCM push notification via HTTP v1 API
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`;
    const dataPayload: Record<string, string> = {
      type: notifType,
      chatId: chat_id || "",
      senderId: sender_id || "",
      senderName: sender_name || "",
      title: notifTitle,
      body: notifBody,
    };
    if (custom_data && typeof custom_data === "object") {
      for (const [key, value] of Object.entries(custom_data)) {
        dataPayload[key] = String(value);
      }
    }

    const fcmResponse = await fetch(fcmUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: {
            title: notifTitle,
            body: notifBody,
          },
          data: dataPayload,
          android: {
            priority: "high",
            notification: {
              channel_id: "utopia_high_importance_v3",
              priority: "MAX",
              default_sound: true,
              default_vibrate_timings: true,
            },
          },
          apns: {
            payload: {
              aps: {
                alert: {
                  title: notifTitle,
                  body: notifBody,
                },
                sound: "default",
                badge: 1,
              },
            },
          },
        },
      }),
    });

    const fcmResult = await fcmResponse.json();

    if (!fcmResponse.ok) {
      console.error(`[send-chat-notification] FCM send failed:`, JSON.stringify(fcmResult));
      return new Response(JSON.stringify({ success: false, error: "FCM send failed", details: fcmResult }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      });
    }

    console.log(`[send-chat-notification] Push sent successfully to ${recipient_id}`);

    // Step 4: Write notification record to Firestore /notifications with admin privileges
    try {
      const notifId = crypto.randomUUID();
      const notifUrl = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/notifications?documentId=${notifId}`;
      await fetch(notifUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          fields: {
            id: { stringValue: notifId },
            recipientId: { stringValue: recipient_id },
            senderId: { stringValue: sender_id },
            senderName: { stringValue: sender_name || "" },
            senderPhotoUrl: { stringValue: custom_data?.senderPhotoUrl ? String(custom_data.senderPhotoUrl) : "" },
            title: { stringValue: notifTitle },
            body: { stringValue: notifBody },
            type: { stringValue: notifType },
            chatId: { stringValue: chat_id || "" },
            read: { booleanValue: false },
            createdAt: { timestampValue: new Date().toISOString() },
          },
        }),
      });
    } catch (dbErr) {
      console.error("[send-chat-notification] Firestore admin write failed:", dbErr);
    }

    return new Response(JSON.stringify({ success: true, messageId: fcmResult.name }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });

  } catch (error) {
    console.error("[send-chat-notification] Error:", error.message);
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});

// ─────────────────────────────────────────────────────────────
// Helper: Generate Google OAuth2 access token from service account
// ─────────────────────────────────────────────────────────────

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const expiry = now + 3600; // 1 hour

  // Build JWT header and claim set
  const header = { alg: "RS256", typ: "JWT" };
  const claimSet = {
    iss: FIREBASE_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/datastore",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: expiry,
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedClaim = base64UrlEncode(JSON.stringify(claimSet));
  const unsignedJwt = `${encodedHeader}.${encodedClaim}`;

  // Sign the JWT with the private key
  const privateKeyPem = FIREBASE_PRIVATE_KEY_RAW!.replace(/\\n/g, "\n");
  const signature = await signWithRS256(unsignedJwt, privateKeyPem);
  const jwt = `${unsignedJwt}.${signature}`;

  // Exchange JWT for access token
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  if (!tokenResponse.ok) {
    const errText = await tokenResponse.text();
    throw new Error(`OAuth2 token exchange failed: ${tokenResponse.status} — ${errText}`);
  }

  const tokenData = await tokenResponse.json();
  return tokenData.access_token;
}

// ─────────────────────────────────────────────────────────────
// Helper: Read recipient's FCM token from Firestore REST API
// ─────────────────────────────────────────────────────────────

async function getRecipientFCMToken(accessToken: string, recipientId: string): Promise<string | null> {
  const firestoreUrl = `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/users/${recipientId}`;
  const response = await fetch(firestoreUrl, {
    headers: {
      "Authorization": `Bearer ${accessToken}`,
    },
  });

  if (!response.ok) {
    console.error(`[send-chat-notification] Firestore read failed for ${recipientId}: ${response.status}`);
    return null;
  }

  const doc = await response.json();
  const fields = doc.fields;
  if (!fields) return null;

  // Primary token (single string)
  const fcmToken = fields.fcmToken?.stringValue;
  if (fcmToken && fcmToken.trim() !== "") {
    return fcmToken;
  }

  // Fallback: first token from the fcmTokens array
  const fcmTokens = fields.fcmTokens?.arrayValue?.values;
  if (Array.isArray(fcmTokens) && fcmTokens.length > 0) {
    const firstToken = fcmTokens[fcmTokens.length - 1]?.stringValue;
    if (firstToken && firstToken.trim() !== "") {
      return firstToken;
    }
  }

  return null;
}

// ─────────────────────────────────────────────────────────────
// Crypto helpers: Base64URL encoding and RS256 signing
// ─────────────────────────────────────────────────────────────

function base64UrlEncode(str: string): string {
  const encoder = new TextEncoder();
  const data = encoder.encode(str);
  let base64 = btoa(String.fromCharCode(...data));
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlEncodeBytes(bytes: Uint8Array): string {
  let base64 = btoa(String.fromCharCode(...bytes));
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function signWithRS256(data: string, privateKeyPem: string): Promise<string> {
  // Parse PEM to binary DER
  const pemContents = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");

  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const encoder = new TextEncoder();
  const signatureBuffer = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    encoder.encode(data)
  );

  return base64UrlEncodeBytes(new Uint8Array(signatureBuffer));
}
