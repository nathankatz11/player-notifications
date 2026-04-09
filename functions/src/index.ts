import * as admin from "firebase-admin";

// Initialize Firebase Admin SDK
admin.initializeApp();

// Export scheduled functions
export { pollLiveGames } from "./polling/pollLiveGames";

// Export HTTP functions
export { searchEntity } from "./api/searchEntity";
export { manageSubscription } from "./api/manageSubscription";
