module Demo
  # Demo data for a fictional gym and studio software company, built the way real data would
  # be: through the services, one simulated day at a time. Nothing is inserted directly, so
  # the audit trail, the provider's event history and the invoices all agree, and
  # reconciliation starts at zero differences.
  #
  # The calendar is fixed (START plus a list of daily stories), so every run ends in the same
  # state: something in every subscription status and every dunning stage.
  class Seed < ApplicationService
    START = Time.utc(2026, 1, 5, 9)
    LAST_DAY = 70

    def call
      Current.set(actor: "admin") do
        BillingClock.travel_to!(START)
        @plans = Catalog.ensure!
        @subscriptions = {}

        (0..LAST_DAY).each do |day|
          stories.fetch(day, []).each { |story| instance_exec(&story) }
          BillingClock.advance!(days: 1) if day < LAST_DAY
        end
        # The days end with reconciliation; one more pass on the final state.
        Reconciliation::Run.call(triggered_by: "system_job")
      end
      Summary.call
    end

    private

    # day => what happens that day. Monthly periods started on day 0 renew on days 31 and 59.
    def stories
      {
        0 => [
          -> { studio(:flow, "Flow Yoga Loft", plan: "starter") },           # trial, converts on day 14
          -> { studio(:iron, "Iron Temple Gym", plan: "studio_pro") },
          -> { studio(:pulse, "Pulse Pilates", plan: "studio") },            # upgrades on day 20
          -> { studio(:harbor, "Harbor CrossFit", plan: "studio_pro") },     # downgrades on day 25
          -> { studio(:lotus, "Lotus Barre", plan: "studio") },              # refunds on day 15
          -> { studio(:summit, "Summit Climbing", plan: "studio_annual") },
          -> { studio(:northside, "Northside Boxing", plan: "studio") },     # paused on day 10
          -> { studio(:tidal, "Tidal Swim School", plan: "studio") },        # paused days 40–55
          -> { studio(:kinetic, "Kinetic Dance Co", plan: "studio") },       # canceled on day 30
          -> { studio(:oak, "Oak Street Spin", plan: "studio") },            # cancel scheduled on day 60
          # Card valid through February: the renewal on day 59 (March) fails as expired.
          -> { studio(:zen, "Zen Den Meditation", plan: "studio", exp: [ 2, 2026 ]) }
        ],
        10 => [
          -> { pause(:northside) },
          -> { studio(:peak, "Peak Performance Lab", plan: "studio", card: "pm_card_chargeDeclined") } # exhausted on day 24
        ],
        15 => [
          -> { refund(:lotus, 1_500, "original_method") },
          -> { refund(:lotus, 1_000, "credit_balance") }
        ],
        20 => [
          -> { change_plan(:pulse, "studio_pro") },
          -> { studio(:canyon, "Canyon Trail Runners", plan: "starter") }
        ],
        25 => [ -> { change_plan(:harbor, "studio") } ],
        30 => [
          -> { cancel(:kinetic) },
          -> { studio(:riverbend, "Riverbend Martial Arts", plan: "studio", card: "pm_card_chargeDeclined") }
        ],
        34 => [ -> { fix_card(:riverbend) } ], # recovers during dunning
        40 => [ -> { pause(:tidal, resumes_on_day: 55) } ],
        45 => [
          -> { studio(:metro, "Metro Muay Thai", plan: "studio_pro") },
          -> { studio(:brightside, "Brightside Bootcamp", plan: "studio") }
        ],
        60 => [ -> { cancel(:oak, at_period_end: true) } ],
        62 => [ -> { studio(:grit, "Grit Garage", plan: "starter") } ],             # still in trial at the end
        64 => [ -> { change_plan(:metro, "studio") } ],                            # downgrade: credit left on balance
        65 => [ -> { studio(:nova, "Nova Aerial Arts", plan: "studio", card: "pm_card_chargeDeclined") } ], # retried
        66 => [ -> { studio(:bloom, "Bloom Prenatal Yoga", plan: "starter", card: nil) } ], # trial, no card yet
        69 => [ -> { studio(:cedar, "Cedar Row Rowing", plan: "studio", card: "pm_card_chargeDeclinedInsufficientFunds") } ] # just failed
      }
    end

    def studio(key, name, plan:, card: "pm_card_visa", exp: [ 12, 2028 ])
      customer = Customers::Create.call(name: name, email: "billing@#{key}.studio.test")
      PaymentMethods::Attach.call(customer, token: card, exp_month: exp[0], exp_year: exp[1]) if card
      @subscriptions[key] = Subscriptions::Create.call(customer: customer, plan: @plans.fetch(plan))
    end

    def subscription(key)
      @subscriptions.fetch(key).reload
    end

    def change_plan(key, plan_code)
      target = subscription(key)
      plan = @plans.fetch(plan_code)
      quote = PlanChanges::Quote.new(subscription: target, to_plan: plan, strategy: "immediate")
      PlanChanges::Apply.call(target, lock_version: target.lock_version, to_plan: plan, strategy: "immediate",
        proration_date: quote.proration_date)
    end

    def pause(key, resumes_on_day: nil)
      target = subscription(key)
      Subscriptions::Pause.call(target, lock_version: target.lock_version, resumes_at: resumes_on_day && START + resumes_on_day.days)
    end

    def cancel(key, at_period_end: false)
      target = subscription(key)
      Subscriptions::Cancel.call(target, lock_version: target.lock_version, at_period_end: at_period_end)
    end

    def refund(key, amount_cents, destination)
      invoice = subscription(key).invoices.paid.order(:id).first
      Refunds::Create.call(invoice, amount_cents: amount_cents, destination: destination, reason: "service_issue")
    end

    def fix_card(key)
      PaymentMethods::Attach.call(subscription(key).customer, token: "pm_card_visa", exp_month: 12, exp_year: 2028, make_default: true)
    end
  end
end
