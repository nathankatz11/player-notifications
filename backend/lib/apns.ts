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
 *   APNS_KEY_BASE64   — Base64-encoded .p8 private key contents (PEM)
 *   APNS_ENVIRONMENT  — Optional. "production" (default) or "sandbox".
 *                       TestFlight builds use "production". Xcode-installed
 *                       development builds need "sandbox".
 */

import crypto from "node:crypto";
import http2 from "node:http2";

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

/** Max APNs payload size is 4096 bytes; leave buffer for JSON encoding overhead. */
const MAX_PAYLOAD_BYTES = 4000;
/** Safety cap on alert body characters to keep payloads well under the APNs limit. */
const MAX_BODY_CHARS = 180;
/** JWT refresh window — APNs rejects tokens older than 1 hour. */
const JWT_TTL_MS = 50 * 60 * 1000;
/** HTTP/2 request timeout. */
const REQUEST_TIMEOUT_MS = 10_000;

interface CachedJwt {
  token: string;
  expiresAt: number;
  /** Fingerprint of the key material used so env rotation invalidates the cache. */
  fingerprint: string;
}

let cachedJwt: CachedJwt | null = null;

function base64url(input: Buffer | string): string {
  const buf = typeof input === "string" ? Buffer.from(input) : input;
  return buf
    .toString("base64")
    .replace(/=+$/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function decodeP8(keyBase64: string): string {
  // APNS_KEY_BASE64 is base64 of the .p8 file contents, which is already PEM.
  return Buffer.from(keyBase64, "base64").toString("utf8");
}

function buildJwt(keyId: string, teamId: string, keyBase64: string): string {
  const fingerprint = `${keyId}:${teamId}:${keyBase64.length}`;
  const now = Date.now();

  if (cachedJwt && cachedJwt.expiresAt > now && cachedJwt.fingerprint === fingerprint) {
    return cachedJwt.token;
  }

  const header = { alg: "ES256", kid: keyId, typ: "JWT" };
  const claims = { iss: teamId, iat: Math.floor(now / 1000) };

  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(
    JSON.stringify(claims)
  )}`;

  const privateKey = crypto.createPrivateKey({
    key: decodeP8(keyBase64),
    format: "pem",
  });

  // `dsaEncoding: 'ieee-p1363'` makes Node emit a JOSE-style raw r||s signature
  // (64 bytes for P-256) instead of DER. That's exactly what JWT ES256 requires,
  // so we avoid a manual DER → JOSE conversion.
  const signature = crypto.sign("sha256", Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: "ieee-p1363",
  });

  const token = `${signingInput}.${base64url(signature)}`;

  cachedJwt = {
    token,
    expiresAt: now + JWT_TTL_MS,
    fingerprint,
  };

  return token;
}

function truncateBody(body: string): string {
  if (body.length <= MAX_BODY_CHARS) return body;
  return body.slice(0, MAX_BODY_CHARS - 1) + "…";
}

function buildApnsPayload(payload: APNsPayload): string {
  const build = (bodyText: string) => {
    const apsAlert: Record<string, unknown> = {
      title: payload.title,
      body: bodyText,
    };
    const aps: Record<string, unknown> = { alert: apsAlert };
    if (typeof payload.badge === "number") aps.badge = payload.badge;
    if (payload.sound) aps.sound = payload.sound;

    const wire: Record<string, unknown> = { aps };
    if (payload.subscriptionId) wire.subscriptionId = payload.subscriptionId;
    if (payload.alertId) wire.alertId = payload.alertId;
    return wire;
  };

  let bodyText = truncateBody(payload.body);
  let json = JSON.stringify(build(bodyText));

  if (Buffer.byteLength(json, "utf8") > MAX_PAYLOAD_BYTES) {
    // Body is already capped at MAX_BODY_CHARS; if we're still over (unlikely),
    // halve it until we fit.
    while (
      Buffer.byteLength(json, "utf8") > MAX_PAYLOAD_BYTES &&
      bodyText.length > 20
    ) {
      bodyText = bodyText.slice(0, Math.floor(bodyText.length / 2)) + "…";
      json = JSON.stringify(build(bodyText));
    }
  }

  return json;
}

interface APNsResponse {
  statusCode: number;
  body: string;
}

function apnsHost(): string {
  const env = (process.env.APNS_ENVIRONMENT ?? "production").toLowerCase();
  return env === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
}

function postToApns(
  host: string,
  deviceToken: string,
  jwt: string,
  bundleId: string,
  jsonBody: string
): Promise<APNsResponse> {
  return new Promise((resolve, reject) => {
    let settled = false;
    const client = http2.connect(host);

    const finish = (result: APNsResponse | Error) => {
      if (settled) return;
      settled = true;
      try {
        client.close();
      } catch {
        // ignore
      }
      if (result instanceof Error) reject(result);
      else resolve(result);
    };

    client.on("error", (err) => finish(err));

    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${jwt}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    });

    req.setTimeout(REQUEST_TIMEOUT_MS, () => {
      req.close();
      finish(new Error("APNs request timed out"));
    });

    let statusCode = 0;
    const chunks: Buffer[] = [];

    req.on("response", (headers) => {
      statusCode = Number(headers[":status"]) || 0;
    });
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => {
      finish({ statusCode, body: Buffer.concat(chunks).toString("utf8") });
    });
    req.on("error", (err) => finish(err));

    req.write(jsonBody);
    req.end();
  });
}

/**
 * Send a push notification to an iOS device via APNs.
 * Uses token-based authentication (ES256 JWT) over HTTP/2.
 *
 * The on-wire body shape is:
 *   {
 *     "aps": { "alert": { "title": "...", "body": "..." }, "sound": "default", "badge": 1 },
 *     "subscriptionId": "<id>",   // custom, outside aps
 *     "alertId": "<id>"           // custom, outside aps
 *   }
 *
 * Returns true on HTTP 200, false otherwise (including missing env, bad token,
 * rate limiting, transient 5xx). Never throws on non-200 — callers decide.
 */
export async function sendPushNotification(
  deviceToken: string,
  payload: APNsPayload
): Promise<boolean> {
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  const bundleId = process.env.APNS_BUNDLE_ID;
  const keyBase64 = process.env.APNS_KEY_BASE64;

  if (!keyId || !teamId || !bundleId || !keyBase64) {
    console.warn("[APNs] Missing configuration — push notification skipped");
    console.log(
      `[APNs STUB] → ${deviceToken}: ${payload.title} — ${payload.body}` +
        (payload.subscriptionId ? ` (subscriptionId=${payload.subscriptionId})` : "")
    );
    return false;
  }

  let jwt: string;
  try {
    jwt = buildJwt(keyId, teamId, keyBase64);
  } catch (err) {
    console.error("[APNs] Failed to build JWT:", err);
    return false;
  }

  const jsonBody = buildApnsPayload(payload);
  const host = apnsHost();

  let response: APNsResponse;
  try {
    response = await postToApns(host, deviceToken, jwt, bundleId, jsonBody);
  } catch (err) {
    console.error("[APNs] HTTP/2 request failed:", err);
    return false;
  }

  const { statusCode, body } = response;

  if (statusCode === 200) {
    return true;
  }

  // Parse APNs error reason (e.g. { "reason": "BadDeviceToken" })
  let reason = "";
  try {
    const parsed = JSON.parse(body) as { reason?: string };
    reason = parsed?.reason ?? "";
  } catch {
    // body may be empty or non-JSON; ignore
  }

  if (statusCode === 410 || reason === "Unregistered" || reason === "BadDeviceToken") {
    console.warn(
      `[APNs] Dead token (${statusCode} ${reason || "Unregistered"}) for device ${deviceToken}` +
        (payload.subscriptionId ? ` subscriptionId=${payload.subscriptionId}` : "") +
        (payload.alertId ? ` alertId=${payload.alertId}` : "")
    );
    return false;
  }

  if (statusCode === 429) {
    console.warn(`[APNs] Rate limited (429 ${reason}) for device ${deviceToken}`);
    return false;
  }

  if (statusCode >= 500) {
    console.warn(`[APNs] Transient error ${statusCode} ${reason} — caller may retry`);
    return false;
  }

  console.warn(`[APNs] Request rejected: ${statusCode} ${reason} body=${body}`);
  return false;
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
