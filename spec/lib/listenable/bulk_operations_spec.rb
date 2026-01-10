# frozen_string_literal: true

require 'spec_helper'
require 'support/rails_dummy'

RSpec.describe 'Listenable bulk operations' do
  before do
    UserListener.sync_called = nil
    UserListener.async_called = nil
    UserListener.async_user_id = nil
  end

  it 'handles bulk updates without exhausting connection pool' do
    # Create 100 users to simulate real bulk import
    users = 100.times.map { |i| User.create!(name: "User #{i}") }

    # Update all users (triggers async listeners)
    # With conservative thread pool, this should queue and process safely
    users.each_with_index do |user, i|
      user.update!(name: "Updated User #{i}")
    end

    # Wait for async operations to complete
    sleep 2.0

    # Verify no connection pool errors occurred
    expect(UserListener.async_called).to eq(true)

    # Verify thread pool prevented unlimited spawning
    executor = Listenable.async_executor
    expect(executor).to be_a(Concurrent::ThreadPoolExecutor)
    # Should auto-scale to 25% of pool size (min 1, max 3)
    expect(executor.max_length).to be >= 1
    expect(executor.max_length).to be <= 3
  end

  it 'auto-scales thread pool to 25% of connection pool size' do
    executor = Listenable.async_executor
    pool_size = ActiveRecord::Base.connection_pool.size
    expected_threads = [[pool_size / 4, 1].max, 3].min

    # Thread pool should be 25% of connection pool (min 1, max 3)
    expect(executor.max_length).to eq(expected_threads)
    expect(Listenable.default_thread_pool_size).to eq(expected_threads)

    # Should have large queue capacity for bulk operations
    expect(executor.max_queue).to eq(10_000)

    # Should fall back to caller_runs when queue is full
    expect(executor.fallback_policy).to eq(:caller_runs)
  end
end
