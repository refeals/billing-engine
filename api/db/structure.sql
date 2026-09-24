CREATE TABLE IF NOT EXISTS "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "simulation_clock" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "current_time" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT simulation_clock_single_row CHECK (id = 1));
CREATE TABLE IF NOT EXISTS "billing_events" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "subject_type" varchar, "subject_id" integer, "subscription_id" integer, "customer_id" integer, "webhook_event_id" integer, "event_type" varchar NOT NULL, "actor_type" varchar NOT NULL, "data" json DEFAULT '{}' NOT NULL, "occurred_at" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL);
CREATE INDEX "index_billing_events_on_subject" ON "billing_events" ("subject_type", "subject_id");
CREATE INDEX "index_billing_events_on_subscription_id_and_occurred_at" ON "billing_events" ("subscription_id", "occurred_at");
CREATE INDEX "index_billing_events_on_customer_id_and_occurred_at" ON "billing_events" ("customer_id", "occurred_at");
CREATE INDEX "index_billing_events_on_event_type" ON "billing_events" ("event_type");
CREATE INDEX "index_billing_events_on_occurred_at" ON "billing_events" ("occurred_at");
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
CREATE TABLE IF NOT EXISTS "plans" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "code" varchar NOT NULL, "name" varchar NOT NULL, "amount_cents" integer NOT NULL, "currency" varchar DEFAULT 'USD' NOT NULL, "interval" varchar NOT NULL, "trial_days" integer DEFAULT 0 NOT NULL, "archived_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT plans_amount_positive CHECK (amount_cents > 0), CONSTRAINT plans_interval_known CHECK (interval IN ('month', 'year')), CONSTRAINT plans_currency_usd CHECK (currency = 'USD'), CONSTRAINT plans_trial_days_non_negative CHECK (trial_days >= 0));
CREATE UNIQUE INDEX "index_plans_on_code" ON "plans" ("code");
CREATE TABLE IF NOT EXISTS "customers" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "email" varchar NOT NULL, "provider_customer_id" varchar NOT NULL, "credit_balance_cents" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT customers_credit_balance_non_negative CHECK (credit_balance_cents >= 0));
CREATE UNIQUE INDEX "index_customers_on_email" ON "customers" ("email");
CREATE UNIQUE INDEX "index_customers_on_provider_customer_id" ON "customers" ("provider_customer_id");
CREATE TABLE IF NOT EXISTS "payment_methods" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "customer_id" integer NOT NULL, "provider_payment_method_id" varchar NOT NULL, "test_card_token" varchar NOT NULL, "brand" varchar NOT NULL, "last4" varchar NOT NULL, "exp_month" integer NOT NULL, "exp_year" integer NOT NULL, "is_default" boolean DEFAULT FALSE NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_84a67e8b40"
FOREIGN KEY ("customer_id")
  REFERENCES "customers" ("id")
, CONSTRAINT payment_methods_exp_month_valid CHECK (exp_month BETWEEN 1 AND 12));
CREATE INDEX "index_payment_methods_on_customer_id" ON "payment_methods" ("customer_id");
CREATE UNIQUE INDEX "index_payment_methods_on_provider_payment_method_id" ON "payment_methods" ("provider_payment_method_id");
CREATE UNIQUE INDEX "index_payment_methods_one_default_per_customer" ON "payment_methods" ("customer_id") WHERE is_default = 1;
CREATE TABLE IF NOT EXISTS "credit_ledger_entries" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "customer_id" integer NOT NULL, "amount_cents" integer NOT NULL, "balance_after_cents" integer NOT NULL, "reason" varchar NOT NULL, "invoice_id" integer, "plan_change_id" integer, "note" varchar, "occurred_at" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_c3ef0bfaf5"
FOREIGN KEY ("customer_id")
  REFERENCES "customers" ("id")
, CONSTRAINT credit_ledger_entries_amount_non_zero CHECK (amount_cents <> 0), CONSTRAINT credit_ledger_entries_balance_non_negative CHECK (balance_after_cents >= 0), CONSTRAINT credit_ledger_entries_reason_known CHECK (reason IN ('downgrade_proration', 'applied_to_invoice', 'refund_to_balance', 'manual_adjustment')));
CREATE INDEX "index_credit_ledger_entries_on_customer_id_and_id" ON "credit_ledger_entries" ("customer_id", "id");
CREATE TRIGGER credit_ledger_entries_no_update
BEFORE UPDATE ON credit_ledger_entries
BEGIN
  SELECT RAISE(ABORT, 'credit_ledger_entries is append-only');
END;
CREATE TRIGGER credit_ledger_entries_no_delete
BEFORE DELETE ON credit_ledger_entries
BEGIN
  SELECT RAISE(ABORT, 'credit_ledger_entries is append-only');
END;
CREATE TABLE IF NOT EXISTS "subscriptions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "customer_id" integer NOT NULL, "plan_id" integer NOT NULL, "provider_subscription_id" varchar NOT NULL, "status" varchar NOT NULL, "current_period_start" datetime(6) NOT NULL, "current_period_end" datetime(6) NOT NULL, "trial_ends_at" datetime(6), "cancel_at_period_end" boolean DEFAULT FALSE NOT NULL, "canceled_at" datetime(6), "cancellation_reason" varchar, "paused_at" datetime(6), "resumes_at" datetime(6), "access_suspended_at" datetime(6), "last_provider_event_at" datetime(6), "lock_version" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_63d3df128b"
FOREIGN KEY ("plan_id")
  REFERENCES "plans" ("id")
, CONSTRAINT "fk_rails_66eb6b32c1"
FOREIGN KEY ("customer_id")
  REFERENCES "customers" ("id")
, CONSTRAINT subscriptions_status_known CHECK (status IN ('trialing', 'active', 'past_due', 'paused', 'canceled')));
CREATE INDEX "index_subscriptions_on_plan_id" ON "subscriptions" ("plan_id");
CREATE UNIQUE INDEX "index_subscriptions_on_provider_subscription_id" ON "subscriptions" ("provider_subscription_id");
CREATE INDEX "index_subscriptions_on_status" ON "subscriptions" ("status");
CREATE INDEX "index_subscriptions_on_current_period_end" ON "subscriptions" ("current_period_end");
CREATE INDEX "index_subscriptions_on_customer_id" ON "subscriptions" ("customer_id");
CREATE UNIQUE INDEX "index_subscriptions_one_live_per_customer" ON "subscriptions" ("customer_id") WHERE status <> 'canceled';
CREATE TABLE IF NOT EXISTS "subscription_state_transitions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "subscription_id" integer NOT NULL, "from_status" varchar, "to_status" varchar NOT NULL, "reason" varchar NOT NULL, "actor_type" varchar NOT NULL, "webhook_event_id" integer, "billing_event_id" integer NOT NULL, "metadata" json DEFAULT '{}' NOT NULL, "occurred_at" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_45cf9f3d0e"
FOREIGN KEY ("subscription_id")
  REFERENCES "subscriptions" ("id")
, CONSTRAINT "fk_rails_d48954816d"
FOREIGN KEY ("billing_event_id")
  REFERENCES "billing_events" ("id")
);
CREATE INDEX "idx_on_subscription_id_occurred_at_70bdbb273b" ON "subscription_state_transitions" ("subscription_id", "occurred_at");
CREATE TRIGGER subscription_state_transitions_no_update
BEFORE UPDATE ON subscription_state_transitions
BEGIN
  SELECT RAISE(ABORT, 'subscription_state_transitions is append-only');
END;
CREATE TRIGGER subscription_state_transitions_no_delete
BEFORE DELETE ON subscription_state_transitions
BEGIN
  SELECT RAISE(ABORT, 'subscription_state_transitions is append-only');
END;
CREATE TABLE IF NOT EXISTS "idempotency_keys" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "request_fingerprint" varchar NOT NULL, "response_status" integer, "response_body" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_idempotency_keys_on_key" ON "idempotency_keys" ("key");
INSERT INTO "schema_migrations" (version) VALUES
('20260924193755'),
('20260924193753'),
('20260924193751'),
('20260924192040'),
('20260924192038'),
('20260924192036'),
('20260924192035'),
('20260924191115'),
('20260924185702');

