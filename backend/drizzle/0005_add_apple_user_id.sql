ALTER TABLE "users" ADD COLUMN IF NOT EXISTS "apple_user_id" text;
--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "users_apple_user_id_unique" ON "users" ("apple_user_id");
