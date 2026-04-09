import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { UserDoc } from "../lib/types";

const db = admin.firestore();

/**
 * Sends a push notification to a user via Firebase Cloud Messaging.
 * Fetches the user's FCM token from Firestore and dispatches the message.
 */
export async function sendFCM(userId: string, message: string): Promise<void> {
  const userSnap = await db.collection("users").doc(userId).get();
  const user = userSnap.data() as UserDoc | undefined;

  if (!user?.fcmToken) {
    logger.warn(`No FCM token for user ${userId}`);
    return;
  }

  try {
    await admin.messaging().send({
      token: user.fcmToken,
      notification: {
        title: "StatShot",
        body: message,
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    });

    logger.info(`FCM sent to ${userId}`);
  } catch (err) {
    logger.error(`FCM send failed for ${userId}:`, err);

    // If token is invalid, clean it up
    if (err instanceof Error && err.message.includes("not-registered")) {
      await db.collection("users").doc(userId).update({ fcmToken: "" });
    }
  }
}
