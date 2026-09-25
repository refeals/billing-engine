module Api
  module V1
    class BaseController < ApplicationController
      include ActionController::Cookies
      include Authentication
      include Idempotent

      # A single back-office operator: every signed-in request is attributed to the admin.
      before_action { Current.actor = "admin" }
    end
  end
end
