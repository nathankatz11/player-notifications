import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { UserDoc } from "../lib/types";

const db = admin.firestore();

/**
 * Sends an SMS alert via Twilio. Premium users only.
 * Requires TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, and TWILIO_PHONE_NUMBER
 * to be set in Firebase Functions config.
 */
export async function sendTwilioSMS(userId: string, message: string): Promise<void> {
  const userSnap = await db.collection("users").doc(userId).get();
  const user = userSnap.data() as UserDoc | undefined;

  if (!user) {
    logger.warn(`User ${userId} not found`);
    return;
  }

  // Only premium users get SMS
  if (user.plan !== "premium") {
    logger.info(`User ${userId} is not premium, skipping SMS`);
    return;
  }

  if (!user.phone) {
    logger.warn(`No phone number for user ${userId}`);
    return;
  }

  // TODO: Implement Twilio integration
  // const accountSid = functions.config().twilio?.account_sid;
  // const authToken = functions.config().twilio?.auth_token;
  // const fromNumber = functions.config().twilio?.phone_number;
  //
  // const client = twilio(accountSid, authToken);
  // await client.messages.create({
  //   body: message,
  //   from: fromNumber,
  //   to: user.phone,
  // });

  logger.info(`[STUB] SMS to ${user.phone}: ${message}`);
}
