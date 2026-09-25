require "rails_helper"

RSpec.describe Api::V1::BaseController, type: :controller do
  controller(described_class) do
    # This spec is about error rendering; authentication has its own request specs.
    allow_unauthenticated_access

    def index
      case params[:failure]
      when "domain" then raise DomainError.new("Plan is archived", code: "plan_archived", details: { plan_id: 1 })
      when "transition" then raise InvalidTransitionError.new("Cannot pause", details: { from: "canceled", to: "paused" })
      when "stale" then raise ActiveRecord::StaleObjectError.new
      when "not_found" then raise ActiveRecord::RecordNotFound, "Couldn't find Plan"
      when "invalid" then raise ActiveRecord::RecordInvalid, invalid_record
      when "missing_param" then params.require(:plan_id)
      end
    end

    private

    def invalid_record
      SimulationClock.new.tap(&:validate)
    end
  end

  def error_for(failure)
    get :index, params: { failure: failure }
    response.parsed_body["error"]
  end

  it "renders domain errors with their own code and details" do
    expect(error_for("domain")).to eq(
      "code" => "plan_archived", "message" => "Plan is archived", "details" => { "plan_id" => 1 }
    )
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "renders invalid transitions as 422 invalid_transition" do
    expect(error_for("transition")).to include("code" => "invalid_transition", "details" => { "from" => "canceled", "to" => "paused" })
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "renders optimistic lock conflicts as 409" do
    expect(error_for("stale")["code"]).to eq("stale_object")
    expect(response).to have_http_status(:conflict)
  end

  it "renders missing records as 404" do
    expect(error_for("not_found")["code"]).to eq("not_found")
    expect(response).to have_http_status(:not_found)
  end

  it "renders validation failures as 422 with field errors" do
    expect(error_for("invalid")).to include("code" => "validation_failed", "details" => { "current_time" => [ "can't be blank" ] })
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "renders missing parameters as 400" do
    expect(error_for("missing_param")["code"]).to eq("bad_request")
    expect(response).to have_http_status(:bad_request)
  end
end
