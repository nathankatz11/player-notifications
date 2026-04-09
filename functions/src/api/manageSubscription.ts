import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { Response } from "express";
import { SubscriptionDoc, UserDoc } from "../lib/types";

const db = admin.firestore();
const FREE_TIER_LIMIT = 3;

/**
 * HTTP function: CRUD operations for user subscriptions.
 * Enforces free tier limit (3 active subscriptions max).
 *
 * POST   /manageSubscription — create subscription
 * PUT    /manageSubscription — update subscription
 * DELETE /manageSubscription — deactivate subscription
 */
export const manageSubscription = onRequest(async (req, res) => {
  // TODO: Add Firebase Auth token verification
  // const token = req.headers.authorization?.split("Bearer ")[1];
  // const decoded = await admin.auth().verifyIdToken(token);
  // const userId = decoded.uid;

  const userId = req.body?.userId as string | undefined;
  if (!userId) {
    res.status(401).json({ error: "userId is required" });
    return;
  }

  switch (req.method) {
  case "POST":
    await createSubscription(userId, req.body, res);
    break;
  case "PUT":
    await updateSubscription(req.body, res);
    break;
  case "DELETE":
    await deleteSubscription(req.body, res);
    break;
  default:
    res.status(405).json({ error: "Method not allowed" });
  }
});

async function createSubscription(
  userId: string,
  body: Record<string, unknown>,
  res: Response
): Promise<void> {
  // Check user's plan and current subscription count
  const userSnap = await db.collection("users").doc(userId).get();
  const user = userSnap.data() as UserDoc | undefined;

  if (user?.plan !== "premium") {
    const activeSubs = await db
      .collection("subscriptions")
      .where("userId", "==", userId)
      .where("active", "==", true)
      .count()
      .get();

    if (activeSubs.data().count >= FREE_TIER_LIMIT) {
      res.status(403).json({
        error: `Free tier limited to ${FREE_TIER_LIMIT} active alerts. Upgrade to premium for unlimited.`,
      });
      return;
    }
  }

  const subscription: Omit<SubscriptionDoc, "createdAt"> & { createdAt: FirebaseFirestore.FieldValue } = {
    userId,
    type: body.type as SubscriptionDoc["type"],
    league: body.league as SubscriptionDoc["league"],
    entityId: String(body.entityId),
    entityName: String(body.entityName),
    trigger: body.trigger as SubscriptionDoc["trigger"],
    deliveryMethod: (body.deliveryMethod as SubscriptionDoc["deliveryMethod"]) ?? "push",
    active: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  const docRef = await db.collection("subscriptions").add(subscription);
  res.status(201).json({ id: docRef.id, ...subscription });
}

async function updateSubscription(
  body: Record<string, unknown>,
  res: Response
): Promise<void> {
  const subId = body.subscriptionId as string | undefined;
  if (!subId) {
    res.status(400).json({ error: "subscriptionId is required" });
    return;
  }

  const updates: Record<string, unknown> = {};
  if (body.trigger) updates.trigger = body.trigger;
  if (body.deliveryMethod) updates.deliveryMethod = body.deliveryMethod;
  if (body.active !== undefined) updates.active = body.active;

  await db.collection("subscriptions").doc(subId).update(updates);
  res.json({ updated: true });
}

async function deleteSubscription(
  body: Record<string, unknown>,
  res: Response
): Promise<void> {
  const subId = body.subscriptionId as string | undefined;
  if (!subId) {
    res.status(400).json({ error: "subscriptionId is required" });
    return;
  }

  await db.collection("subscriptions").doc(subId).update({ active: false });
  res.json({ deactivated: true });
}
