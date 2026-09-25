# The back-office operator. The demo has exactly one (Demo::User); there is no sign-up.
class User < ApplicationRecord
  has_secure_password

  has_many :sessions, dependent: :delete_all

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
end
