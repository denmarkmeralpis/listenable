# frozen_string_literal: true

RSpec.describe Listenable do
  it "has a version number" do
    expect(Listenable::VERSION).not_to be nil
  end
end
