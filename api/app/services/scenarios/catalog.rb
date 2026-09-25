module Scenarios
  # Every canned scenario, in the order the Scenario Lab shows them.
  module Catalog
    def self.all
      [
        HappyPath, FailedPaymentRecovery, FullDunning, DuplicateWebhook, OutOfOrderEvents,
        LostWebhook, UpgradeMidCycle, DowngradeWithCredit, ExpiredCard, PartialRefund
      ]
    end

    def self.fetch(key)
      all.find { |scenario| scenario.key == key } ||
        raise(ActiveRecord::RecordNotFound, "Unknown scenario #{key.inspect}")
    end
  end
end
