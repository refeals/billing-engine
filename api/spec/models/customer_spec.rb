require "rails_helper"

RSpec.describe Customer do
  it "normalizes the email so uniqueness ignores case and spaces" do
    create(:customer, email: "Owner@StudioFlow.test")

    duplicate = build(:customer, email: "  owner@studioflow.TEST ")

    expect(duplicate.email).to eq("owner@studioflow.test")
    expect(duplicate).not_to be_valid
  end

  it "rejects a malformed email" do
    expect(build(:customer, email: "not-an-email")).not_to be_valid
  end

  it "searches by name or email, case-insensitively" do
    flow = create(:customer, name: "Studio Flow", email: "flow@example.test")
    create(:customer, name: "Iron Gym", email: "iron@example.test")

    expect(described_class.search("FLOW")).to eq([ flow ])
    expect(described_class.search("flow@")).to eq([ flow ])
  end

  it "finds terms containing an underscore" do
    underscored = create(:customer, email: "studio_flow@example.test")
    create(:customer, email: "studioxflow@example.test")

    expect(described_class.search("studio_flow")).to eq([ underscored ])
  end

  it "treats LIKE wildcards in the query as plain text" do
    create(:customer, name: "Studio Flow")

    expect(described_class.search("%")).to be_empty
  end

  it "points audit events at itself" do
    customer = create(:customer)
    expect(customer.audit_references).to eq(customer_id: customer.id, subscription_id: nil)
  end
end
