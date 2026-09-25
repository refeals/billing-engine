class CustomerNotification < ApplicationRecord
  include AppendOnly

  belongs_to :customer
  belongs_to :dunning_case, optional: true
  belongs_to :dunning_step, optional: true

  validates :kind, :subject, :body, :sent_at, presence: true

  scope :newest_first, -> { order(sent_at: :desc, id: :desc) }
end
