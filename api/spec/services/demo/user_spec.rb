require "rails_helper"

RSpec.describe Demo::User do
  it "creates the demo user once" do
    first = described_class.ensure!
    second = described_class.ensure!

    expect(second).to eq(first)
    expect(User.count).to eq(1)
    expect(first.authenticate(described_class::PASSWORD)).to be_truthy
  end

  it "restores the published password if it was changed" do
    described_class.ensure!.update!(password: "something-else")

    user = described_class.ensure!

    expect(user.authenticate(described_class::PASSWORD)).to be_truthy
  end
end
