module Api
  module V1
    class BaseController < ApplicationController
      include Idempotent

      # There is no authentication (single back-office operator), so every API request
      # is attributed to the admin.
      before_action { Current.actor = "admin" }
    end
  end
end
