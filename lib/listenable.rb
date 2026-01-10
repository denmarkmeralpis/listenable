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

  class Error < StandardError; end

  class << self
    attr_writer :async_executor

    # Track active subscribers to prevent memory leaks on reload
    def subscribers
      @subscribers ||= []
    end

    # Calculate a safe thread pool size based on connection pool
    # Very conservative: use only 1/4 of pool (min 1, max 3)
    def default_thread_pool_size
      return 2 unless defined?(ActiveRecord::Base)

      pool_size = ActiveRecord::Base.connection_pool.size
      # Use 25% of pool, but at least 1 thread, max 3 threads
      [[pool_size / 4, 1].max, 3].min
    end

    # Thread pool executor for async listeners
    # Auto-scales to 25% of connection pool (very conservative)
    def async_executor
      @async_executor ||= Concurrent::ThreadPoolExecutor.new(
        min_threads: 0,
        max_threads: default_thread_pool_size,
        max_queue: 10_000,
        fallback_policy: :caller_runs,
        idletime: 60 # Threads idle for 60s are cleaned up
      )
    end

    # Cleanup all subscribers and shutdown thread pool
    # Called on Rails reload to prevent memory leaks
    def cleanup!
      # Unsubscribe all tracked subscribers
      subscribers.each do |subscriber|
        ActiveSupport::Notifications.unsubscribe(subscriber)
      rescue StandardError => e
        Rails.logger&.warn("[Listenable] Failed to unsubscribe: #{e.message}")
      end
      @subscribers = []

      # Shutdown thread pool gracefully
      shutdown_async_executor!
    end

    # Graceful shutdown of thread pool
    def shutdown_async_executor!
      return unless @async_executor

      @async_executor.shutdown
      unless @async_executor.wait_for_termination(10)
        Rails.logger&.warn('[Listenable] Thread pool shutdown timeout, forcing kill')
        @async_executor.kill
      end
      @async_executor = nil
    end

    # For testing - immediate shutdown
    def reset_async_executor!
      return unless @async_executor

      @async_executor.shutdown
      @async_executor.kill unless @async_executor.wait_for_termination(5)
      @async_executor = nil
    end
  end
end
