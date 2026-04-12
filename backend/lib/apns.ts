/**
 * Apple Push Notification service (APNs) client.
 *
 * Sends push notifications directly to iOS devices via APNs HTTP/2 API.
 * Requires an APNs auth key (.p8 file) from Apple Developer Console.
 *
 * Environment variables needed:
 *   APNS_KEY_ID       — Key ID from Apple Developer
 *   APNS_TEAM_ID      — Apple Developer Team ID
 *   APNS_BUNDLE_ID    — App bundle identifier (com.statshot.app)
 *   APNS_KEY_BASE64   — Base64-encoded .p8 private key contents
 */

interface APNsPayload {
  title: string;
  body: string;
  badge?: number;
  sound?: string;
  /** Custom field — the subscription that triggered this alert (for iOS deep-linking). */
  subscriptionId?: string;
  /** Custom field — the alert row id (for iOS deep-linking / analytics). */
  alertId?: string;
}

/**
 * Send a push notification to an iOS device via APNs.
 * Uses token-based authentication (JWT).
 *
 * The on-wire body shape is:
 *   {
 *     "aps": { "alert": { "title": "...", "body": "..." }, "sound": "default" },
 *     "subscriptionId": "<id>",   // custom, outside aps
 *     "alertId": "<id>"           // custom, outside aps
 *   }
 */
export async function sendPushNotification(
  deviceToken: string,
  payload: APNsPayload
): Promise<boolean> {
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  const bundleId = process.env.APNS_BUNDLE_ID;

  if (!keyId || !teamId || !bundleId) {
    console.warn("[APNs] Missing configuration — push notification skipped");
    console.log(
      `[APNs STUB] → ${deviceToken}: ${payload.title} — ${payload.body}` +
        (payload.subscriptionId ? ` (subscriptionId=${payload.subscriptionId})` : "")
    );
    return false;
  }

  // TODO: Implement JWT signing with the .p8 key and send via APNs HTTP/2
  // 1. Create JWT: { iss: teamId, iat: now } signed with ES256 using the .p8 key
  // 2. POST to https://api.push.apple.com/3/device/{deviceToken}
  //    Headers:
  //      authorization: bearer <jwt>
  //      apns-topic: <bundleId>
  //      apns-push-type: alert
  //    Body: {
  //      aps: { alert: { title, body }, badge, sound: "default" },
  //      subscriptionId, alertId    // custom fields outside aps
  //    }

  console.log(
    `[APNs STUB] → ${deviceToken}: ${payload.title} — ${payload.body}` +
      (payload.subscriptionId ? ` (subscriptionId=${payload.subscriptionId})` : "")
  );
  return true;
}

/**
 * Send a push notification to a user by looking up their APNs token.
 *
 * Optional `ids` lets callers attach a `subscriptionId` / `alertId` so the iOS
 * app can deep-link into the right `AlertDetailView` when the user taps the
 * notification.
 */
export async function sendPushToUser(
  userId: string,
  message: string,
  ids?: { subscriptionId?: string; alertId?: string }
): Promise<boolean> {
  // Import here to avoid circular dependency
  const { db } = await import("./db");
  const { users } = await import("./db/schema");
  const { eq } = await import("drizzle-orm");

  const [user] = await db.select().from(users).where(eq(users.id, userId));

  if (!user?.apnsToken) {
    console.warn(`[APNs] No token for user ${userId}`);
    return false;
  }

  return sendPushNotification(user.apnsToken, {
    title: "StatShot",
    body: message,
    sound: "default",
    badge: 1,
    subscriptionId: ids?.subscriptionId,
    alertId: ids?.alertId,
  });
}
