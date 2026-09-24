require "rails_helper"

RSpec.describe BillingEvent do
  describe "validations" do
    it "accepts a namespaced event type" do
      expect(build(:billing_event, event_type: "subscription.transitioned")).to be_valid
    end

    it "rejects an event type without a namespace" do
      expect(build(:billing_event, event_type: "transitioned")).not_to be_valid
    end

    it "rejects an unknown actor" do
      expect(build(:billing_event, actor_type: "intern")).not_to be_valid
    end
  end

  describe "append-only guarantees" do
    let!(:event) { create(:billing_event) }
    let(:connection) { described_class.lease_connection }

    it "refuses updates through the model" do
      expect { event.update!(event_type: "clock.reset") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "refuses update_column, which skips validations and callbacks" do
      expect { event.update_column(:event_type, "clock.reset") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "refuses destroy and delete through the model" do
      expect { event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { event.delete }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    # The paths below skip model callbacks entirely; only the database triggers stop them.
    it "refuses update_all and delete_all at the database level" do
      expect { described_class.update_all(event_type: "clock.reset") }
        .to raise_error(ActiveRecord::StatementInvalid, /billing_events is append-only/)
      expect { described_class.delete_all }
        .to raise_error(ActiveRecord::StatementInvalid, /billing_events is append-only/)
    end

    it "refuses raw SQL updates and deletes" do
      expect { connection.execute("UPDATE billing_events SET event_type = 'clock.reset'") }
        .to raise_error(ActiveRecord::StatementInvalid, /billing_events is append-only/)
      expect { connection.execute("DELETE FROM billing_events") }
        .to raise_error(ActiveRecord::StatementInvalid, /billing_events is append-only/)
    end

    it "keeps the row unchanged after every attempt" do
      [ -> { described_class.update_all(event_type: "clock.reset") }, -> { described_class.delete_all } ].each do |attempt|
        attempt.call
      rescue ActiveRecord::StatementInvalid
        nil
      end

      expect(event.reload.event_type).to eq("clock.day_advanced")
    end
  end
end
