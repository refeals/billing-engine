class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Which subscription and customer an audit event about this record belongs to, so it
  # shows up in their timelines. Subscription and Customer override it for themselves.
  def audit_references
    { subscription_id: try(:subscription_id), customer_id: try(:customer_id) }
  end
end
