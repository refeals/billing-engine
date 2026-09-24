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
CREATE TABLE IF NOT EXISTS "webhook_events" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "provider_event_id" varchar NOT NULL, "event_type" varchar NOT NULL, "provider_object_id" varchar NOT NULL, "payload" json NOT NULL, "provider_created_at" datetime(6) NOT NULL, "received_at" datetime(6) NOT NULL, "processing_status" varchar DEFAULT 'received' NOT NULL, "processed_at" datetime(6), "attempts" integer DEFAULT 0 NOT NULL, "last_error" text, "duplicate_deliveries_count" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT webhook_events_processing_status_known CHECK (processing_status IN ('received', 'processed', 'failed', 'skipped_stale', 'ignored_unhandled')));
CREATE UNIQUE INDEX "index_webhook_events_on_provider_event_id" ON "webhook_events" ("provider_event_id");
CREATE INDEX "index_webhook_events_on_provider_object_id" ON "webhook_events" ("provider_object_id");
CREATE INDEX "index_webhook_events_on_processing_status" ON "webhook_events" ("processing_status");
CREATE INDEX "index_webhook_events_on_event_type" ON "webhook_events" ("event_type");
CREATE TABLE IF NOT EXISTS "mocked_webhook_events" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "event_id" varchar NOT NULL, "event_type" varchar NOT NULL, "api_version" varchar NOT NULL, "payload" json NOT NULL, "provider_object_id" varchar NOT NULL, "provider_subscription_id" varchar, "provider_created_at" datetime(6) NOT NULL, "delivery_mode" varchar DEFAULT 'deliver' NOT NULL, "copies" integer DEFAULT 1 NOT NULL, "delivery_status" varchar DEFAULT 'pending' NOT NULL, "delivery_count" integer DEFAULT 0 NOT NULL, "delivery_attempts" integer DEFAULT 0 NOT NULL, "last_delivery_result" varchar, "last_delivered_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT mocked_webhook_events_delivery_status_known CHECK (delivery_status IN ('pending', 'delivered', 'dropped')), CONSTRAINT mocked_webhook_events_delivery_mode_known CHECK (delivery_mode IN ('deliver', 'drop')), CONSTRAINT mocked_webhook_events_copies_range CHECK (copies BETWEEN 1 AND 5));
CREATE UNIQUE INDEX "index_mocked_webhook_events_on_event_id" ON "mocked_webhook_events" ("event_id");
CREATE INDEX "index_mocked_webhook_events_on_provider_subscription_id" ON "mocked_webhook_events" ("provider_subscription_id");
CREATE INDEX "index_mocked_webhook_events_on_delivery_status" ON "mocked_webhook_events" ("delivery_status");
CREATE TABLE IF NOT EXISTS "invoice_number_sequences" ("year" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "last_value" integer DEFAULT 0 NOT NULL);
CREATE TABLE IF NOT EXISTS "invoices" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "subscription_id" integer NOT NULL, "customer_id" integer NOT NULL, "provider_invoice_id" varchar NOT NULL, "number" varchar NOT NULL, "status" varchar NOT NULL, "billing_reason" varchar NOT NULL, "period_start" datetime(6) NOT NULL, "period_end" datetime(6) NOT NULL, "subtotal_cents" integer NOT NULL, "credit_applied_cents" integer DEFAULT 0 NOT NULL, "total_cents" integer NOT NULL, "amount_paid_cents" integer DEFAULT 0 NOT NULL, "amount_refunded_cents" integer DEFAULT 0 NOT NULL, "amount_due_cents" integer NOT NULL, "currency" varchar DEFAULT 'USD' NOT NULL, "issued_at" datetime(6) NOT NULL, "paid_at" datetime(6), "attempt_count" integer DEFAULT 0 NOT NULL, "last_provider_event_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_457c900f6e"
FOREIGN KEY ("subscription_id")
  REFERENCES "subscriptions" ("id")
, CONSTRAINT "fk_rails_0d349e632f"
FOREIGN KEY ("customer_id")
  REFERENCES "customers" ("id")
, CONSTRAINT invoices_status_known CHECK (status IN ('open', 'paid', 'void', 'uncollectible')), CONSTRAINT invoices_billing_reason_known CHECK (billing_reason IN ('subscription_create', 'subscription_cycle', 'subscription_update', 'manual')), CONSTRAINT invoices_amounts_non_negative CHECK (subtotal_cents >= 0 AND credit_applied_cents >= 0 AND amount_paid_cents >= 0 AND amount_refunded_cents >= 0 AND amount_due_cents >= 0), CONSTRAINT invoices_total_consistent CHECK (total_cents = subtotal_cents - credit_applied_cents));
CREATE INDEX "index_invoices_on_subscription_id" ON "invoices" ("subscription_id");
CREATE INDEX "index_invoices_on_customer_id" ON "invoices" ("customer_id");
CREATE UNIQUE INDEX "index_invoices_on_provider_invoice_id" ON "invoices" ("provider_invoice_id");
CREATE UNIQUE INDEX "index_invoices_on_number" ON "invoices" ("number");
CREATE INDEX "index_invoices_on_status" ON "invoices" ("status");
CREATE TABLE IF NOT EXISTS "invoice_line_items" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "invoice_id" integer NOT NULL, "kind" varchar NOT NULL, "description" varchar NOT NULL, "plan_id" integer, "amount_cents" integer NOT NULL, "period_start" datetime(6), "period_end" datetime(6), "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_1b1f533054"
FOREIGN KEY ("plan_id")
  REFERENCES "plans" ("id")
, CONSTRAINT "fk_rails_80427eb9d3"
FOREIGN KEY ("invoice_id")
  REFERENCES "invoices" ("id")
, CONSTRAINT invoice_line_items_kind_known CHECK (kind IN ('subscription', 'proration_credit', 'proration_charge', 'credit_applied')));
CREATE INDEX "index_invoice_line_items_on_invoice_id" ON "invoice_line_items" ("invoice_id");
CREATE TRIGGER invoice_line_items_no_update
BEFORE UPDATE ON invoice_line_items
BEGIN
  SELECT RAISE(ABORT, 'invoice_line_items is append-only');
END;
CREATE TRIGGER invoice_line_items_no_delete
BEFORE DELETE ON invoice_line_items
BEGIN
  SELECT RAISE(ABORT, 'invoice_line_items is append-only');
END;
CREATE TABLE IF NOT EXISTS "payment_attempts" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "invoice_id" integer NOT NULL, "payment_method_id" integer, "provider_charge_id" varchar NOT NULL, "status" varchar NOT NULL, "failure_code" varchar, "amount_cents" integer NOT NULL, "attempted_at" datetime(6) NOT NULL, "webhook_event_id" integer, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_8a81ff14ab"
FOREIGN KEY ("payment_method_id")
  REFERENCES "payment_methods" ("id")
, CONSTRAINT "fk_rails_cba35add1a"
FOREIGN KEY ("invoice_id")
  REFERENCES "invoices" ("id")
, CONSTRAINT payment_attempts_status_known CHECK (status IN ('succeeded', 'failed')));
CREATE INDEX "index_payment_attempts_on_invoice_id" ON "payment_attempts" ("invoice_id");
CREATE INDEX "index_payment_attempts_on_payment_method_id" ON "payment_attempts" ("payment_method_id");
CREATE UNIQUE INDEX "index_payment_attempts_on_provider_charge_id" ON "payment_attempts" ("provider_charge_id");
CREATE TRIGGER payment_attempts_no_update
BEFORE UPDATE ON payment_attempts
BEGIN
  SELECT RAISE(ABORT, 'payment_attempts is append-only');
END;
CREATE TRIGGER payment_attempts_no_delete
BEFORE DELETE ON payment_attempts
BEGIN
  SELECT RAISE(ABORT, 'payment_attempts is append-only');
END;
CREATE TABLE IF NOT EXISTS "plan_changes" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "subscription_id" integer NOT NULL, "from_plan_id" integer NOT NULL, "to_plan_id" integer NOT NULL, "kind" varchar NOT NULL, "strategy" varchar NOT NULL, "status" varchar NOT NULL, "proration_date" datetime(6), "effective_at" datetime(6) NOT NULL, "credit_cents" integer DEFAULT 0 NOT NULL, "charge_cents" integer DEFAULT 0 NOT NULL, "net_cents" integer DEFAULT 0 NOT NULL, "invoice_id" integer, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_207719221a"
FOREIGN KEY ("subscription_id")
  REFERENCES "subscriptions" ("id")
, CONSTRAINT "fk_rails_41e1964728"
FOREIGN KEY ("from_plan_id")
  REFERENCES "plans" ("id")
, CONSTRAINT "fk_rails_277d281b22"
FOREIGN KEY ("to_plan_id")
  REFERENCES "plans" ("id")
, CONSTRAINT "fk_rails_25269cf082"
FOREIGN KEY ("invoice_id")
  REFERENCES "invoices" ("id")
, CONSTRAINT plan_changes_kind_known CHECK (kind IN ('upgrade', 'downgrade', 'lateral', 'trial_swap')), CONSTRAINT plan_changes_strategy_known CHECK (strategy IN ('immediate', 'at_period_end')), CONSTRAINT plan_changes_status_known CHECK (status IN ('scheduled', 'applied', 'canceled')), CONSTRAINT plan_changes_net_consistent CHECK (net_cents = credit_cents + charge_cents));
CREATE INDEX "index_plan_changes_on_subscription_id" ON "plan_changes" ("subscription_id");
CREATE UNIQUE INDEX "index_plan_changes_one_scheduled_per_subscription" ON "plan_changes" ("subscription_id") WHERE status = 'scheduled';
INSERT INTO "schema_migrations" (version) VALUES
('20260924222126'),
('20260924220007'),
('20260924220005'),
('20260924220003'),
('20260924220002'),
('20260924214612'),
('20260924195002'),
('20260924193755'),
('20260924193753'),
('20260924193751'),
('20260924192040'),
('20260924192038'),
('20260924192036'),
('20260924192035'),
('20260924191115'),
('20260924185702');

