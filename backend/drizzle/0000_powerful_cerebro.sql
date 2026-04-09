CREATE TYPE "public"."delivery_method" AS ENUM('push', 'sms', 'both');--> statement-breakpoint
CREATE TYPE "public"."game_status" AS ENUM('pre', 'in', 'post');--> statement-breakpoint
CREATE TYPE "public"."league" AS ENUM('nba', 'nfl', 'nhl', 'mlb', 'ncaafb', 'ncaamb', 'mls');--> statement-breakpoint
CREATE TYPE "public"."plan" AS ENUM('free', 'premium');--> statement-breakpoint
CREATE TYPE "public"."subscription_type" AS ENUM('player_stat', 'team_event');--> statement-breakpoint
CREATE TABLE "alerts" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"subscription_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"message" text NOT NULL,
	"sent_at" timestamp DEFAULT now() NOT NULL,
	"delivery_method" text NOT NULL,
	"game_id" text NOT NULL,
	"event_description" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "games" (
	"id" text PRIMARY KEY NOT NULL,
	"league" "league" NOT NULL,
	"home_team" text NOT NULL,
	"away_team" text NOT NULL,
	"status" "game_status" DEFAULT 'pre' NOT NULL,
	"last_polled_at" timestamp,
	"last_play_id" text
);
--> statement-breakpoint
CREATE TABLE "subscriptions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"type" "subscription_type" NOT NULL,
	"league" "league" NOT NULL,
	"entity_id" text NOT NULL,
	"entity_name" text NOT NULL,
	"trigger" text NOT NULL,
	"delivery_method" "delivery_method" DEFAULT 'push' NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" text NOT NULL,
	"phone" text,
	"apns_token" text,
	"plan" "plan" DEFAULT 'free' NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_subscription_id_subscriptions_id_fk" FOREIGN KEY ("subscription_id") REFERENCES "public"."subscriptions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "subscriptions" ADD CONSTRAINT "subscriptions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;