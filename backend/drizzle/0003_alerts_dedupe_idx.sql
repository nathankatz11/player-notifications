CREATE INDEX IF NOT EXISTS "alerts_dedupe_idx" ON "alerts" ("subscription_id", "game_id", "event_description", "sent_at" DESC);
