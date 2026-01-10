# frozen_string_literal: true

require 'active_support'
require 'active_support/concern'
require 'active_support/notifications'
require 'concurrent'

require_relative 'listenable/version'
require_relative 'listenable/concern'
require_relative 'listenable/railtie' if defined?(Rails)

module Listenable
  mattr_accessor :enabled, default: true
  mattr_accessor :async_executor

  class Error < StandardError; end

  # Calculate a safe thread pool size based on connection pool
  # Very conservative: use only 1/4 of pool (min 1, max 3)
  def self.default_thread_pool_size
    if defined?(ActiveRecord::Base)
      pool_size = ActiveRecord::Base.connection_pool.size
      # Use 25% of pool, but at least 1 thread, max 3 threads
      [[pool_size / 4, 1].max, 3].min
    else
      2  # Fallback if ActiveRecord not available
    end
  end

  # Thread pool executor for async listeners
  # Auto-scales to 25% of connection pool (very conservative)
  def self.async_executor
    @@async_executor ||= Concurrent::ThreadPoolExecutor.new(
      min_threads: 0,
      max_threads: default_thread_pool_size,
      max_queue: 10_000,
      fallback_policy: :caller_runs
    )
  end

  def self.reset_async_executor!
    @@async_executor&.shutdown
    @@async_executor&.wait_for_termination(5)
    @@async_executor = nil
  end
end
