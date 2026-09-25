# Learning Rails through this project (the API)

A guide to `api/` for someone who knows React and TypeScript well and has never written Ruby
or Rails. It explains how this billing engine works **and** the Ruby/Rails concepts it uses,
always with code from this repository, and with a React/Node parallel where one helps.

Read it with the code open. Every path is relative to `api/`.

Companion: [LEARN-WEB.md](LEARN-WEB.md) for the Vue side. For what the system *does*
(state machine, proration, dunning…), the [README](README.md) and
[docs/architecture.md](docs/architecture.md) are the reference; this guide is about *how*
it is built.

## Contents

1. [The mental map](#1-the-mental-map)
2. [Ruby for JavaScript developers](#2-ruby-for-javascript-developers)
3. [Rails in one page](#3-rails-in-one-page)
4. [Follow one request end to end](#4-follow-one-request-end-to-end)
5. [Routing](#5-routing)
6. [Controllers](#6-controllers)
7. [Active Record: models and the database](#7-active-record-models-and-the-database)
8. [Services: where the business logic lives](#8-services-where-the-business-logic-lives)
9. [Concerns: sharing behavior](#9-concerns-sharing-behavior)
10. [Request-scoped state with `Current`](#10-request-scoped-state-with-current)
11. [Serializers and errors: the API's contract](#11-serializers-and-errors-the-apis-contract)
12. [How the billing engine works, in code](#12-how-the-billing-engine-works-in-code)
13. [Authentication](#13-authentication)
14. [Testing with RSpec and FactoryBot](#14-testing-with-rspec-and-factorybot)
15. [Tooling and daily commands](#15-tooling-and-daily-commands)
16. [Gotchas for React developers](#16-gotchas-for-react-developers)
17. [Exercises](#17-exercises)
18. [Where to go next](#18-where-to-go-next)

## 1. The mental map

If you have built a Node backend (Express, Nest, Next API routes), most Rails ideas have a
cousin you already know:

| You know (Node/React world) | Rails / Ruby | In this project |
|---|---|---|
| `package.json` + npm/pnpm | `Gemfile` + Bundler (`bundle install`) | `Gemfile`, `Gemfile.lock` |
| npm package | gem | `rails`, `sqlite3`, `bcrypt`, `rack-cors`… |
| Express router | `config/routes.rb` | one file declares every URL |
| Express handler / Next route handler | controller action (a method) | `app/controllers/api/v1/*_controller.rb` |
| Express middleware | `before_action` (per controller) or Rack middleware (global) | `Authentication`, CORS |
| Prisma / TypeORM / Drizzle | Active Record | `app/models/*.rb` |
| Prisma migrations | Active Record migrations | `db/migrate/*.rb` |
| `schema.prisma` | `db/structure.sql` (generated, never edited by hand) | `db/structure.sql` |
| `import x from './x'` | nothing: Zeitwerk autoloads by file name | whole app |
| `.env` + `process.env` | `ENV["X"]`, `config/environments/*.rb` | `SIMULATOR_ENABLED`, `WEB_ORIGIN` |
| AsyncLocalStorage / request context | `ActiveSupport::CurrentAttributes` | `app/models/current.rb` |
| DTO / `toJSON` | serializer (a plain class with `as_json`) | `app/serializers/` |
| Jest / Vitest | RSpec | `spec/` |
| test data builders / fishery | FactoryBot | `spec/factories/` |
| supertest | request specs | `spec/requests/` |
| ESLint + Prettier | RuboCop | `.rubocop.yml`, `bin/rubocop` |
| `node` REPL | `bin/rails console` (the REPL with the whole app loaded) | try it! |
| npm scripts | Rake tasks | `lib/tasks/demo.rake` |

The biggest mindset shift: **Rails is convention over configuration**. You don't wire
things together; you put a file in the expected place with the expected name, and Rails
finds it. `app/models/subscription.rb` must define `Subscription`, and the table is
`subscriptions`. Once you know the conventions, you can open any Rails app and find your
way around.

## 2. Ruby for JavaScript developers

Just enough Ruby to read every file in this project.

### Everything is an object, and methods don't need parentheses

```ruby
"hello".upcase          # => "HELLO"
5.times { |i| puts i }  # 0..4
[3, 1, 2].sort.first    # => 1
nil.to_a                # => []
```

Parentheses are optional when calling methods, which is why Rails code looks like a
language of its own:

```ruby
validates :email, presence: true          # a method call: validates(:email, presence: true)
belongs_to :customer                       # also a method call, run when the class loads
render json: payload, status: :created     # render({ json: payload, status: :created })
```

### Symbols

`:email`, `:created` are **symbols**: immutable, interned names. Think of them as string
constants used as identifiers (like TS string literal types). Hash keys are usually symbols.

### Hashes (objects) and keyword arguments

```ruby
user = { email: "demo@x.dev", name: "Demo" }   # same as { :email => "demo@x.dev", ... }
user[:email]                                   # => "demo@x.dev"
user.fetch(:missing)                           # raises KeyError (like a strict access)
user.fetch(:missing, "default")                # => "default"
```

Methods can take **keyword arguments**, which is how Ruby does "options objects":

```ruby
# app/services/subscriptions/transition.rb
def initialize(subscription, to:, reason:, attributes: {}, metadata: {})
# called as:
Transition.call(subscription, to: "canceled", reason: "customer_requested")
```

`to:` is required, `attributes: {}` has a default. TS equivalent:
`constructor(subscription, { to, reason, attributes = {}, metadata = {} })`.

### Blocks: Ruby's callbacks

A block is the `{ ... }` or `do ... end` after a method call. It is Ruby's lambda-passed-as-
last-argument:

```ruby
subscriptions.map { |subscription| SubscriptionSerializer.new(subscription) }
# JS: subscriptions.map((subscription) => new SubscriptionSerializer(subscription))

ActiveRecord::Base.transaction do
  # everything here runs inside one database transaction
end
```

A method receives the block implicitly and runs it with `yield`. That is how
`with_guards` wraps an action in this project:

```ruby
# app/services/subscriptions/admin_action.rb
def with_guards(action)
  ActiveRecord::Base.transaction do
    # ...checks...
    yield            # runs the block the caller passed
    subscription
  end
end

# app/services/subscriptions/cancel.rb
with_guards("cancel_now") do
  Transition.call(subscription, to: "canceled", ...)
end
```

In React terms: a component that renders `children` inside a wrapper, but for code.

### Implicit return

The last expression of a method is its return value. `return` exists but is used for early
exits only:

```ruby
def archived?
  archived_at.present?     # returned
end
```

### Naming conventions that carry meaning

- `archived?` — ends in `?`: returns a boolean.
- `save!`, `create!`, `advance!` — ends in `!`: the "dangerous" version. For Active Record,
  `save!` **raises** on failure while `save` returns `false`. This project always uses the
  `!` versions so a failure can never go unnoticed.
- `@subscription` — instance variable (like `this.subscription`).
- `CONSTANT` — capitalized names are constants (`STATES`, `MAX_ADVANCE_DAYS`).
- `snake_case` for methods and variables, `CamelCase` for classes and modules.

### Truthiness is different from JavaScript

Only `nil` and `false` are falsy. **`0`, `""` and `[]` are truthy.** To ask "is it empty?"
Rails adds `blank?` / `present?`:

```ruby
"".present?     # => false
[].blank?       # => true
nil.blank?      # => true
```

### Small operators you will see everywhere

```ruby
@subscription ||= Subscription.find(params[:id])  # memoize: assign only if nil/false
Current.webhook_event&.id                          # safe navigation, like ?. in JS
"#{count} days"                                    # interpolation, like `${count} days`
%w[trialing active past_due]                       # => ["trialing", "active", "past_due"]
```

`begin / rescue / ensure` is `try / catch / finally`; a whole method body can act as the
`begin`:

```ruby
def run
  steps
rescue ExpectationFailed => error      # catch (error) { if (error instanceof ExpectationFailed) ... }
  finish("failed", error.message)
ensure
  cleanup                              # finally
end
```

### Classes, modules and "static" methods

```ruby
class ApplicationService
  def self.call(...)        # `self.` = class method (static)
    new(...).call           # `...` forwards every argument (like ...args)
  end
end
```

A **module** is a namespace and/or a bag of methods that can be mixed into classes. Mixing
in (`include SomeModule`) copies its methods into the class; that is how Rails shares
behavior (see [Concerns](#9-concerns-sharing-behavior)). `class << self ... end` opens a
block where every `def` is a class method (used in `BillingClock`).

`private` on its own line makes every method below it private.

## 3. Rails in one page

### The folders that matter

```
api/
  app/
    controllers/   HTTP layer: receives requests, returns JSON
    models/        Active Record classes (one per table) + plain domain objects
    services/      business logic (a convention of this project, not of Rails)
    serializers/   how records turn into JSON
    errors/        error classes
  config/
    routes.rb      every URL
    application.rb app-wide settings
    environments/  development.rb, test.rb, production.rb
    initializers/  code run once at boot (CORS...)
  db/
    migrate/       migrations, in timestamp order
    structure.sql  the resulting schema (generated)
    seeds.rb       demo data
  lib/             code that isn't the app itself (a RuboCop cop, rake tasks)
  spec/            tests
  bin/             executables: rails, rubocop, setup, dev...
```

### Autoloading: no imports

Open any file here and you will not find an `import` or `require` for app classes. Rails'
loader, **Zeitwerk**, maps names to paths:

| Constant | File |
|---|---|
| `Subscription` | `app/models/subscription.rb` |
| `Subscriptions::Cancel` | `app/services/subscriptions/cancel.rb` |
| `Api::V1::SubscriptionsController` | `app/controllers/api/v1/subscriptions_controller.rb` |
| `FakeStripe::Outbox` | `app/models/fake_stripe/outbox.rb` |

The first time code mentions `Subscriptions::Cancel`, Rails loads that file. The rule is
strict: the file must define exactly that constant (`bin/rails zeitwerk:check` verifies
it). In development, files are reloaded on every change, so there is no restart except for
config and gems.

### Environments

`RAILS_ENV` is `development`, `test` or `production`, and `config/environments/<env>.rb`
tunes each one. Example from this project: `config.x.simulator_enabled` defaults to true
only in development and test (`config/application.rb`), so the simulator routes simply
don't exist in production unless `SIMULATOR_ENABLED=true`.

### API-only

This app was generated with `--api`: no views, no sessions or cookies middleware by
default, controllers inherit from `ActionController::API`. Plan 16 added cookies back on
purpose (see [Authentication](#13-authentication)).

## 4. Follow one request end to end

The best way to learn a framework is to trace one real request. The operator clicks
**Cancel now** on a subscription.

**1. The browser** (Vue, `web/src/api/subscriptions.ts`) sends:

```
POST /api/v1/subscriptions/12/cancel
Idempotency-Key: 6f1c…
{ "lock_version": 3 }
```

**2. Rack middleware** (global, before Rails' router): CORS headers (`rack-cors`, configured
in `config/initializers/cors.rb`) and the cookie jar.

**3. The router** (`config/routes.rb`):

```ruby
resources :subscriptions, only: %i[index show create] do
  member do
    post :cancel          # POST /subscriptions/:id/cancel → SubscriptionsController#cancel
  end
end
```

**4. The controller's filters.** `SubscriptionsController < BaseController`, and
`BaseController` includes `Authentication` (a `before_action` that returns 401 without a
session), sets `Current.actor = "admin"`, and includes `Idempotent` (an `around_action`
that replays the stored response if this `Idempotency-Key` was already used).

**5. The action** (`app/controllers/api/v1/subscriptions_controller.rb`):

```ruby
def cancel
  at_period_end = ActiveModel::Type::Boolean.new.cast(params[:at_period_end]) || false
  run(Subscriptions::Cancel, at_period_end: at_period_end)
end

private

def subscription
  @subscription ||= Subscription.includes(:customer, :plan).find(params[:id])
end

def run(action, **options)
  render json: SubscriptionSerializer.new(action.call(subscription, lock_version: lock_version, **options), detail: true)
end
```

The controller is thin on purpose: read params, call a service, render.

**6. The service** (`app/services/subscriptions/cancel.rb` → `AdminAction#with_guards`)
opens a transaction, checks `lock_version` (someone else changed it? → 409), checks
`allowed_actions`, then calls `Subscriptions::Transition`.

**7. The single write path** (`app/services/subscriptions/transition.rb`) asks the state
machine whether `active → canceled` with reason `customer_requested` is legal, saves the
subscription, writes an audit event (`Audit.record`) and a `subscription_state_transitions`
row, all in the same transaction.

**8. After commit**, a model callback (`after_commit :push_to_provider`) tells the fake
Stripe about the change, and the provider's webhook comes back through the inbox.

**9. The serializer** turns the subscription into JSON; `render` writes the response.

If anything raises on the way (`DomainError`, `StaleObjectError`, `RecordNotFound`),
`ErrorRendering` (a concern in `ApplicationController`) turns it into
`{ "error": { "code", "message", "details" } }` with the right status.

Keep this path in mind; the rest of this guide zooms into each step.

## 5. Routing

`config/routes.rb` is a Ruby DSL. The helpers generate the RESTful routes you would write
by hand in Express:

```ruby
resources :plans, only: %i[index show create] do
  post :archive, on: :member
end
```

| Verb | Path | Controller#action |
|---|---|---|
| GET | `/plans` | `plans#index` |
| GET | `/plans/:id` | `plans#show` |
| POST | `/plans` | `plans#create` |
| POST | `/plans/:id/archive` | `plans#archive` |

- `namespace :api do namespace :v1 do` prefixes paths (`/api/v1/...`) **and** controller
  modules (`Api::V1::PlansController`).
- Nested `resources` produce nested paths:
  `resources :customers do resources :payment_methods end` → `/customers/:customer_id/payment_methods`.
- `resource :session` (singular) has no `:id`: there is only one session for the caller,
  so it maps to `GET/POST/DELETE /api/v1/session`.
- Routes are code: `if Rails.configuration.x.simulator_enabled` wraps the simulator ones.

Run `bin/rails routes -g subscription` to print the generated table.

## 6. Controllers

A controller is a class; each public method is an action. Inside an action you have:

- `params` — merged path, query and JSON body parameters (`params[:id]`,
  `params.require(:customer_id)` raises `ParameterMissing` → 400 if absent).
- `request` / `response` — the raw objects (`request.headers["Idempotency-Key"]`).
- `render json: ..., status: :created` — writes the response. Symbols name the statuses
  (`:not_found`, `:unprocessable_content`, `:too_many_requests`).
- `head :no_content` — status only, empty body.

### Filters: middleware per controller

```ruby
before_action :require_authentication          # runs before every action
skip_before_action :require_authentication, only: %i[show create]
around_action :with_idempotency_key, if: -> { request.post? && request.headers[HEADER].present? }
```

A `before_action` that renders (or raises) stops the request, exactly like an Express
middleware that doesn't call `next()`. An `around_action` wraps the action and `yield`s to
run it (like Koa middleware with `await next()`).

### `rescue_from`: one place for error responses

```ruby
# app/controllers/concerns/error_rendering.rb
rescue_from DomainError do |error|
  render_error(error.http_status, error.code, error.message, error.details)
end
rescue_from ActiveRecord::StaleObjectError do
  render_error(:conflict, "stale_object", "This record was changed by someone else. Reload and try again.")
end
```

Services just `raise`; the controller layer decides the HTTP shape. Think of it as a
global error boundary for the API.

### Inheritance as configuration

`ApplicationController` → `Api::V1::BaseController` → every resource controller. Put a
filter in the base class and every controller gets it. That's how one line
(`include Authentication` in `BaseController`) protected the whole API in plan 16, while
`WebhooksController` inherits directly from `ApplicationController` and stays public.

## 7. Active Record: models and the database

Active Record is Rails' ORM: **one class per table, one instance per row**, columns become
attributes automatically (nothing is declared in the class).

### Migrations

A migration is a versioned change to the schema (Prisma migrate, but in Ruby):

```ruby
# db/migrate/..._create_plans.rb
class CreatePlans < ActiveRecord::Migration[8.1]
  def change
    create_table :plans do |t|
      t.string :code, null: false
      t.integer :amount_cents, null: false
      t.string :interval, null: false
      t.timestamps                     # created_at, updated_at
    end

    add_index :plans, :code, unique: true
    add_check_constraint :plans, "amount_cents > 0", name: "plans_amount_positive"
  end
end
```

- `bin/rails g migration CreateUsers` generates a timestamped file.
- `bin/rails db:migrate` runs pending ones and regenerates `db/structure.sql`.
- Rules the database enforces (null, unique, check constraints, foreign keys) stay true even
  if Ruby code has a bug. This project puts important rules in **both** places.

Why `structure.sql` instead of the usual `schema.rb`: the append-only tables are protected
by SQLite triggers, and `schema.rb` can't express triggers (see the README).

### Models

```ruby
# app/models/plan.rb
class Plan < ApplicationRecord
  INTERVALS = %w[month year].freeze

  attr_readonly :code, :amount_cents, :currency, :interval    # can't change after create

  validates :code, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :interval, inclusion: { in: INTERVALS }

  scope :active, -> { where(archived_at: nil) }

  def archived?
    archived_at.present?
  end
end
```

- **Validations** run on `save`/`create`. `save!` raises `ActiveRecord::RecordInvalid` if
  any fail (rendered as 422 with field errors, which the Vue forms show under each field).
- **Scopes** are named, chainable queries: `Plan.active.order(:name)`.
- `->` is a lambda (`-> { ... }` ≈ `() => ...`).

### Associations

```ruby
# app/models/subscription.rb
belongs_to :customer                     # subscriptions.customer_id → subscription.customer
belongs_to :plan
has_many :invoices, dependent: :restrict_with_exception
has_many :state_transitions, -> { order(:occurred_at, :id) }, class_name: "SubscriptionStateTransition"
```

These generate methods: `subscription.customer`, `subscription.invoices.open`,
`customer.subscriptions.create!(...)`.

### Queries are lazy (the `Relation`)

```ruby
scope = Subscription.includes(:customer, :plan).order(id: :desc)   # no SQL yet
scope = scope.with_status("active")                                # still no SQL
scope = scope.search("yoga")                                       # still none
scope.limit(50).offset(0).to_a                                     # SQL runs here
```

A `Relation` is a query builder that only hits the database when you iterate it, count it
or call `to_a`/`first`/`sole`. This is how `index` actions compose filters, and how
`paginate` (`app/controllers/concerns/pagination.rb`) adds `limit/offset` to any of them.

Common calls: `find(id)` (raises `RecordNotFound` → 404), `find_by(email: x)` (returns
`nil`), `where(...)`, `where.not(...)`, `order`, `pluck(:id)`, `exists?`, `count`, `sum`,
`group(:status).count` (→ `{ "active" => 12, ... }`, used by the dashboard).

**N+1 queries**: `includes(:customer, :plan)` loads associations in a few queries instead
of one per row. Same problem as a React list that fetches inside each row component.

### Callbacks

```ruby
before_update :refuse_direct_status_change
after_commit :push_to_provider, on: :update
```

Hooks around the lifecycle of a record (`before_validation`, `after_create`,
`after_commit`…). Useful and dangerous: they run invisibly. This project uses very few, and
each one has a comment explaining why it lives on the model (`push_to_provider`: "no new
service can forget it").

### Transactions and locking

```ruby
ActiveRecord::Base.transaction do
  subscription.save!
  Audit.record(...)          # if this raises, the save above is rolled back too
end
```

Nested `transaction` blocks join the outer one. **Optimistic locking**: tables with a
`lock_version` column get it for free; saving a record loaded at version 3 when the row is
at 4 raises `StaleObjectError` (→ 409 "reload"). The Vue screens send the version they
loaded, so two operators can't overwrite each other.

### Other model features used here

- `enum :status, %w[open recovered exhausted canceled].index_by(&:itself)` — generates
  `dunning_case.open?`, `DunningCase.open`, etc.
- `normalizes :email, with: ->(email) { email.strip.downcase }` — cleans input on assign.
- `has_secure_password` — bcrypt hashing, `authenticate(password)`.
- `readonly?` overridden in the `AppendOnly` concern — the model refuses updates.

## 8. Services: where the business logic lives

Rails has no "services" folder by default; classic Rails puts logic in fat models. This
project uses **service objects** instead, one class per business operation:

```ruby
# app/services/application_service.rb
class ApplicationService
  def self.call(...)
    new(...).call
  end
end
```

```ruby
Subscriptions::Create.call(customer: customer, plan: plan)
Refunds::Create.call(invoice, amount_cents: 1_500, destination: "original_method", reason: "service_issue")
Reconciliation::Run.call(triggered_by: "admin")
```

Why: each operation (cancel, renew, refund, run a dunning step) is readable in one file,
testable without HTTP, and reusable from controllers, the daily tick, webhooks, the seeds
and the Scenario Lab. The seeds (`app/services/demo/seed.rb`) build 70 days of history by
calling exactly the same services the operator's buttons call.

The React parallel: services are to controllers what custom hooks and plain functions are
to components. Keep the component (controller) about input and output.

Folders are named after the domain: `subscriptions/`, `invoices/`, `plan_changes/`,
`proration/`, `refunds/`, `dunning/`, `reconciliation/`, `webhooks/`, `ticks/`, `demo/`,
`scenarios/`, `dashboard/`.

## 9. Concerns: sharing behavior

A **concern** is a module with Rails sugar (`ActiveSupport::Concern`): methods to mix in,
plus an `included do ... end` block that runs inside the class that includes it (to
declare filters, validations, scopes…).

```ruby
# app/controllers/concerns/idempotent.rb
module Idempotent
  extend ActiveSupport::Concern

  included do
    around_action :with_idempotency_key, if: -> { request.post? && request.headers[HEADER].present? }
  end

  private

  def with_idempotency_key
    # store the first response for this key, replay it for retries
  end
end
```

Concerns in this project:

| Concern | Included in | Job |
|---|---|---|
| `ErrorRendering` | `ApplicationController` | exceptions → JSON errors |
| `Authentication` | `Api::V1::BaseController` | session cookie → `Current.session`, or 401 |
| `Idempotent` | `Api::V1::BaseController` | `Idempotency-Key` replay |
| `Pagination` | list controllers | `page` param → `limit/offset` + `meta` |
| `AppendOnly` | history models | refuse updates and deletes in Ruby |

Closest React idea: a custom hook that several components call, except it is attached to
the class once instead of called inside each function.

## 10. Request-scoped state with `Current`

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :actor
  attribute :session
  attribute :webhook_event
  attribute :scenario_run
  attribute :drop_event_types
end
```

`Current` holds values for the duration of one request (or one job), reset automatically
afterwards. It is React Context for the backend: set once at the edge, read deep inside
without passing it through every function.

- The controller sets `Current.actor = "admin"`; the webhook ingestor sets `"webhook"` and
  `Current.webhook_event`; the daily tick uses `Current.set(actor: "system_job") { ... }`.
- `Audit.record` reads `Current.actor` and `Current.webhook_event`, so every audit row knows
  who did it and which provider event caused it, with no extra arguments anywhere.
- The Scenario Lab sets `Current.scenario_run`, and the fake provider tags every event it
  emits with it.

Use it sparingly: it is global state, and this project keeps it to "who/what caused this".

## 11. Serializers and errors: the API's contract

### Serializers

Rails can render a model directly (`render json: plan`), but that dumps every column. This
project uses tiny serializer classes, so the JSON shape is explicit and stable:

```ruby
# app/serializers/plan_serializer.rb
class PlanSerializer
  def initialize(plan)
    @plan = plan
  end

  def as_json(*)
    {
      id: @plan.id,
      code: @plan.code,
      amount_cents: @plan.amount_cents,
      active: !@plan.archived?,
      archived_at: @plan.archived_at&.iso8601
    }
  end
end
```

`render json:` calls `as_json` on whatever you give it. Field names stay `snake_case` in
JSON, and the TypeScript types in `web/src/api/*.ts` mirror them one to one.

### Errors

```ruby
# app/errors/domain_error.rb
class DomainError < StandardError
  def initialize(message = nil, code: "domain_error", details: {}, http_status: :unprocessable_content)
```

Services raise `DomainError.new("…", code: "refund_exceeds_refundable")`; `ErrorRendering`
turns it into:

```json
{ "error": { "code": "refund_exceeds_refundable", "message": "…", "details": {} } }
```

The frontend switches on `code` (stable) and shows `message` (human). One shape for every
error is what lets `web/src/api/client.ts` build a single `ApiError` class.

## 12. How the billing engine works, in code

A tour of the domain pieces and the Rails techniques behind each. The *why* of each rule is
in the README; here is *where* and *how*.

### The state machine as data

```ruby
# app/models/subscription_state_machine.rb
TRANSITIONS = {
  nil => { "trialing" => %w[subscription_created], "active" => %w[subscription_created] },
  "active" => {
    "past_due" => %w[payment_failed],
    "paused" => %w[customer_requested],
    "canceled" => %w[customer_requested period_ended_after_cancel_request]
  },
  # ...
}
```

A plain Ruby hash, not a gem: the whole lifecycle is readable in one screen, a spec walks
every pair, and the README's Mermaid diagram mirrors it. `Subscriptions::Transition` is the
only code that changes `status`; a `before_update` callback on the model raises if anything
else tries.

### The simulated clock

```ruby
# app/services/billing_clock.rb
def advance!(days:)
  days.times do
    ActiveRecord::Base.transaction do
      current.update!(current_time: before + 1.day)
      Audit.record(event_type: "clock.day_advanced", ...)
      Current.set(actor: "system_job") do
        Ticks::Run.call(at: current.current_time)
      end
    end
  end
end
```

Every piece of code asks `BillingClock.now` (a row in `simulation_clock`) instead of the
real time. A **custom RuboCop cop** (`lib/rubocop/cop/billing/direct_time_access.rb`) fails
the lint if anyone writes `Time.current`. Each simulated day is one transaction running the
daily steps in `app/services/ticks/run.rb` (cancel at period end, end trials, resume
pauses, renew, dunning, retries, reconciliation).

### Append-only history

`billing_events` (the audit log) and a few other tables can't be updated or deleted: the
`AppendOnly` concern refuses it in Ruby, and **SQLite triggers** refuse it in the database
(`lib/database/append_only_triggers.rb`, created by migrations). `Audit.record` refuses to
run outside a transaction, so a change and its audit row always commit together.

### The fake payment provider and webhooks

`app/models/fake_stripe/` is a simulated Stripe living inside the app. The engine only talks
to it through `PaymentGateway` (`app/services/payment_gateway.rb`), and it only answers the
way Stripe does: IDs now, outcomes later as webhook events. Those events are rows in an
outbox (`mocked_webhook_events`), delivered after the transaction commits
(`ActiveRecord.after_all_transactions_commit`) to `Webhooks::Ingest`, the same code path the
real `POST /api/v1/webhooks/stripe` endpoint uses.

The inbox (`webhook_events`) deduplicates by event id with
`INSERT … ON CONFLICT DO NOTHING`, then processes each event once under a row lock.
Handlers live in `app/services/webhooks/handlers/`.

### Money

Every amount is an integer number of cents (`amount_cents`). Proration uses Ruby's
`Rational` (exact fractions, `Rational(21, 31)`) and rounds once per line
(`app/services/proration/calculate.rb`). Floats never touch money.

### Seeds and scenarios

`db/seeds.rb` calls `Demo::Seed`, which travels the clock to 2026-01-05 and replays 70 days
of "stories" through the real services. `app/services/scenarios/*.rb` are the Scenario Lab:
small classes with a step DSL (`customer`, `subscribe`, `advance_days`, `drop_next`,
`expect_that`…) built on plain Ruby methods and blocks. Reading `scenarios/base.rb` is a
good exercise in how far plain Ruby gets you without any framework.

## 13. Authentication

Plan 16 added a demo login. The pieces, all standard Rails 7.1/8:

- `User` uses `has_secure_password` (bcrypt; needs a `password_digest` column) and
  `normalizes :email`.
- `Api::V1::SessionsController#create` calls `User.authenticate_by(email:, password:)`, which
  takes the same time whether the email exists or not, and creates a `sessions` row.
- The browser gets a **signed, HttpOnly cookie** with the session id
  (`cookies.signed[:session_id] = { value:, httponly: true, same_site: :lax, ... }`).
  Signed means Rails can detect tampering (it uses `SECRET_KEY_BASE`); HttpOnly means
  JavaScript can't read it.
- `Authentication#require_authentication` (a `before_action`) finds the session from the
  cookie or answers 401.
- `rate_limit to: 10, within: 3.minutes, only: :create` (Rails 8) slows down guessing.

Compared with the usual SPA approach (JWT in `localStorage`): the token never reaches
JavaScript, so an XSS bug can't steal it, and signing out deletes the row, which really
ends the session. The trade-off is CORS with `credentials: true` and a same-site setup; the
reasoning is in [docs/16-demo-login.md](docs/16-demo-login.md).

## 14. Testing with RSpec and FactoryBot

```ruby
# spec/services/subscriptions/transition_spec.rb
RSpec.describe Subscriptions::Transition do
  before { freeze_clock_at(Time.utc(2026, 10, 10, 9)) }

  let(:subscription) { create(:subscription) }

  it "refuses a move the state machine doesn't allow and writes nothing" do
    expect { described_class.call(subscription, to: "trialing", reason: "customer_requested") }
      .to raise_error(InvalidTransitionError)
    expect(subscription.reload.status).to eq("active")
  end
end
```

| RSpec | Jest/Vitest |
|---|---|
| `describe` / `context` | `describe` |
| `it "does x" do ... end` | `it("does x", () => {...})` |
| `before { ... }` | `beforeEach` |
| `let(:x) { ... }` | a lazily computed, memoized variable per test |
| `expect(x).to eq(y)` | `expect(x).toEqual(y)` |
| `expect { ... }.to raise_error(E)` | `expect(() => ...).toThrow(E)` |
| `expect { ... }.to change(Model, :count).by(1)` | no direct equivalent: runs the block and compares |
| `described_class` | the class named in `describe` |

- **Transactional tests**: each example runs inside a transaction that is rolled back, so
  the database is clean for the next one without truncating tables.
- **FactoryBot** (`spec/factories/*.rb`): `create(:subscription)` inserts a subscription
  with sensible defaults (and its customer and plan); `build(:subscription)` doesn't save;
  traits vary it: `create(:subscription, :trialing)`.
- **Helpers** in `spec/support/`: `freeze_clock_at`, `customer_with_card`, `subscribe`,
  `advance_days` build real data through the real services.
- **Request specs** (`spec/requests/`) hit the full stack through HTTP (`get`, `post ...,
  as: :json`, then `response.parsed_body`). They run signed in as the demo user
  (`spec/support/authentication.rb`) unless tagged `:unauthenticated`.
- The ten Scenario Lab scenarios also run as specs (`spec/services/scenarios/catalog_spec.rb`),
  so the demo can't silently break.

Run one file or one line: `bundle exec rspec spec/services/refunds/create_spec.rb:27`.

## 15. Tooling and daily commands

Run from `api/` (prefix with `mise exec --` if your shell doesn't load mise):

```sh
bin/rails console                 # REPL with the app loaded (the best learning tool here)
bin/rails server -p 3001          # the API alone (bin/dev at the root runs both apps)
bin/rails routes                  # every route
bin/rails db:migrate              # run migrations, update structure.sql
bin/rails db:prepare              # create + load schema + seed if new, else migrate
bin/rails g migration AddXToY     # new migration
bin/rails runner 'p Demo::Summary.call'   # run one line in the app
bin/rails demo:ensure_user        # a rake task (lib/tasks/demo.rake)
bundle exec rspec                 # tests
bin/rubocop                       # lint (includes the custom time cop)
bin/brakeman                      # security static analysis
bin/rails zeitwerk:check          # every file defines the constant its name promises
```

Things to try in the console:

```ruby
BillingClock.now
Subscription.group(:status).count
Subscription.find(3).state_transitions.map { |t| [t.from_status, t.to_status, t.reason] }
BillingEvent.newest_first.limit(5).pluck(:event_type, :actor_type)
Plan.first.update!(amount_cents: 1)     # => raises: price is attr_readonly
BillingEvent.first.destroy               # => raises: append-only
Dashboard::Summary.call
```

## 16. Gotchas for React developers

- **`0` and `""` are truthy.** Use `present?` / `blank?`.
- **No imports, but names must match paths.** A class in the wrong file is a
  `NameError` at runtime, not a compile error. `zeitwerk:check` catches it.
- **Mutation is normal.** Records are mutable objects; `subscription.status = "x"` then
  `save!`. Immutability is opt-in (`.freeze`), which is why constants here end in `.freeze`.
- **`save` vs `save!`.** The non-bang version returns `false` silently. Prefer `!`.
- **Queries are lazy.** `Subscription.where(...)` returns a query, not rows; iterate it
  (or `to_a`) to run it. Calling `.count` twice runs two queries.
- **Callbacks run invisibly** (`after_commit`, `before_update`). If something happens and
  no service called it, look at the model's callbacks.
- **Strings vs symbols.** `params[:id]` and `params["id"]` both work (params allow both),
  but plain hashes don't: `{ a: 1 }["a"]` is `nil`.
- **Time zones.** Rails adds `1.day`, `7.days.ago`, `time.iso8601`. This project never uses
  real time for billing: `BillingClock.now` or the lint fails.

## 17. Exercises

Each one touches a different layer. Run `bundle exec rspec` and `bin/rubocop` after each.

1. **Console warm-up.** Find the customer with the most invoices:
   `Customer.joins(:invoices).group("customers.name").count.max_by { |_, n| n }`.
   Then rewrite it with `order` and `limit` instead of Ruby.
2. **A new field.** Add a `phone` (optional) to customers: migration, `validates … format:`,
   serializer, request spec. Watch `db/structure.sql` change after `db:migrate`.
3. **A new read endpoint.** `GET /api/v1/customers/:id/summary` returning invoice count and
   total paid. Route (member), action, a service in `app/services/customers/`, request spec
   (signed in by default), and check the authentication coverage spec still passes.
4. **A new transition rule.** Allow `paused → canceled` with a new reason
   `"pause_expired"`: change `TRANSITIONS`, run the state machine spec, see what breaks and why.
5. **A new scenario.** Copy `app/services/scenarios/partial_refund.rb`, write a story with
   `expect_that`, register it in `scenarios/catalog.rb`, and watch it appear in the Scenario
   Lab and run in `catalog_spec.rb`.
6. **Break the audit trail on purpose.** Call `Audit.record` outside a transaction in the
   console and read the error; then try `BillingEvent.update_all(event_type: "x")` and see
   the trigger refuse it.

## 18. Where to go next

- [Rails Guides](https://guides.rubyonrails.org/): start with *Active Record Basics*,
  *Active Record Query Interface*, *Action Controller Overview*, *Routing from the Outside
  In*, *Testing Rails Applications*.
- [Ruby in Twenty Minutes](https://www.ruby-lang.org/en/documentation/quickstart/) and
  *Ruby for JavaScript developers* style cheatsheets for syntax.
- [RSpec docs](https://rspec.info/documentation/), [FactoryBot getting
  started](https://github.com/thoughtbot/factory_bot/blob/main/GETTING_STARTED.md).
- This repository's `docs/01`–`16`: each plan explains the decisions behind a feature
  before its code, a good way to read the code with its intent next to it.
