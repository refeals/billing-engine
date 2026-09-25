namespace :demo do
  desc "Create the demo user, or restore its credentials"
  task ensure_user: :environment do
    Demo::User.ensure!
  end
end
