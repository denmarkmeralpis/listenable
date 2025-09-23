# frozen_string_literal: true

require 'spec_helper'
require 'support/rails_dummy'

RSpec.describe 'Listenable Railtie integration' do
  before do
    UserListener.sync_called = nil
    UserListener.async_called = nil
  end

  it 'fires sync listener on record create' do
    User.create!(name: 'Test User')
    expect(UserListener.sync_called).to eq(true)
  end

  it 'fires async listener on record update' do
    user = User.create!(name: 'Test User')
    user.update!(name: 'Updated User')
    sleep 0.05 # allow async listener to run
    expect(UserListener.async_called).to eq(true)
  end
end
