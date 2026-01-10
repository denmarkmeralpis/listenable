# frozen_string_literal: true

require 'spec_helper'
require 'support/rails_dummy'

RSpec.describe 'Listenable Railtie integration' do
  before do
    UserListener.sync_called = nil
    UserListener.async_called = nil
    UserListener.async_user_id = nil
  end

  it 'fires sync listener on record create' do
    User.create!(name: 'Test User')
    expect(UserListener.sync_called).to eq(true)
  end

  it 'fires async listener on record update' do
    user = User.create!(name: 'Test User')
    user.update!(name: 'Updated User')
    sleep 0.2 # allow async listener to run
    expect(UserListener.async_called).to eq(true)
  end

  it 'reloads record in async listener with proper connection management' do
    user = User.create!(name: 'Test User')
    user.update!(name: 'Updated User')
    sleep 0.1 # allow async listener to run

    # Verify the async listener received the correct reloaded record
    expect(UserListener.async_user_id).to eq(user.id)
  end

  it 'handles deleted records gracefully in async listeners' do
    user = User.create!(name: 'Test User')
    user_id = user.id

    # Update and immediately delete
    user.update!(name: 'Updated')
    user.destroy

    sleep 0.1 # allow async listener to run

    # Should not crash, just log a warning
    expect(UserListener.async_called).to be_nil # Record not found, so method not called
  end
end
