CREATE TABLE IF NOT EXISTS "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "simulation_clock" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "current_time" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT simulation_clock_single_row CHECK (id = 1));
CREATE TABLE IF NOT EXISTS "billing_events" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "subject_type" varchar, "subject_id" integer, "subscription_id" integer, "customer_id" integer, "webhook_event_id" integer, "event_type" varchar NOT NULL, "actor_type" varchar NOT NULL, "data" json DEFAULT '{}' NOT NULL, "occurred_at" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL);
CREATE INDEX "index_billing_events_on_subject" ON "billing_events" ("subject_type", "subject_id") /*application='Api'*/;
CREATE INDEX "index_billing_events_on_subscription_id_and_occurred_at" ON "billing_events" ("subscription_id", "occurred_at") /*application='Api'*/;
CREATE INDEX "index_billing_events_on_customer_id_and_occurred_at" ON "billing_events" ("customer_id", "occurred_at") /*application='Api'*/;
CREATE INDEX "index_billing_events_on_event_type" ON "billing_events" ("event_type") /*application='Api'*/;
CREATE INDEX "index_billing_events_on_occurred_at" ON "billing_events" ("occurred_at") /*application='Api'*/;
CREATE TRIGGER billing_events_no_update
BEFORE UPDATE ON billing_events
BEGIN
  SELECT RAISE(ABORT, 'billing_events is append-only');
END;
CREATE TRIGGER billing_events_no_delete
BEFORE DELETE ON billing_events
BEGIN
  SELECT RAISE(ABORT, 'billing_events is append-only');
END;
INSERT INTO "schema_migrations" (version) VALUES
('20260924191115'),
('20260924185702');

