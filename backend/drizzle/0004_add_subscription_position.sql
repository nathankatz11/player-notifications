ALTER TABLE "subscriptions" ADD COLUMN IF NOT EXISTS "position" text;
--> statement-breakpoint
ALTER TABLE "subscriptions" ADD COLUMN IF NOT EXISTS "external_player_id" text;
