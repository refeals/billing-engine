module Demo
  # The one operator of the live demo. The credentials are public on purpose (the login
  # screen shows them): the login exists to show a real authentication flow, not to keep
  # anyone out. The web app repeats them in src/api/session.ts.
  module User
    EMAIL = "demo@billing-engine.dev"
    PASSWORD = "demo-billing-2026"
    NAME = "Demo Operator"

    # Idempotent: creates the user, or restores its password and name if they changed. Runs
    # from the seeds and from the Docker entrypoint, so an existing database gets the user
    # without a reseed.
    def self.ensure!
      user = ::User.find_or_initialize_by(email: EMAIL)
      user.name = NAME
      user.password = PASSWORD unless user.persisted? && user.authenticate(PASSWORD)
      user.save! if user.changed?
      user
    end
  end
end
