/**
 * Twilio SMS client for premium alert delivery.
 *
 * Environment variables needed:
 *   TWILIO_ACCOUNT_SID  — Twilio Account SID
 *   TWILIO_AUTH_TOKEN    — Twilio Auth Token
 *   TWILIO_PHONE_NUMBER  — Twilio sending phone number
 */

/**
 * Send an SMS via Twilio. Only for premium users.
 */
export async function sendSMS(to: string, message: string): Promise<boolean> {
  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  const from = process.env.TWILIO_PHONE_NUMBER;

  if (!accountSid || !authToken || !from) {
    console.warn("[Twilio] Missing configuration — SMS skipped");
    console.log(`[Twilio STUB] → ${to}: ${message}`);
    return false;
  }

  const res = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Authorization: `Basic ${Buffer.from(`${accountSid}:${authToken}`).toString("base64")}`,
      },
      body: new URLSearchParams({ To: to, From: from, Body: message }),
    }
  );

  if (!res.ok) {
    const error = await res.text();
    console.error(`[Twilio] SMS failed: ${error}`);
    return false;
  }

  return true;
}

/**
 * Send SMS to a user by looking up their phone number.
 * Verifies premium plan before sending.
 */
export async function sendSMSToUser(userId: string, message: string): Promise<boolean> {
  const { db } = await import("./db");
  const { users } = await import("./db/schema");
  const { eq } = await import("drizzle-orm");

  const [user] = await db.select().from(users).where(eq(users.id, userId));

  if (!user) {
    console.warn(`[Twilio] User ${userId} not found`);
    return false;
  }

  if (user.plan !== "premium") {
    console.info(`[Twilio] User ${userId} is not premium, skipping SMS`);
    return false;
  }

  if (!user.phone) {
    console.warn(`[Twilio] No phone for user ${userId}`);
    return false;
  }

  return sendSMS(user.phone, message);
}
