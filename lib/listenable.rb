# frozen_string_literal: true

require 'active_support'
require 'active_support/concern'
require 'active_support/notifications'
require 'concurrent'
require 'set'

require_relative 'listenable/version'
require_relative 'listenable/concern'
require_relative 'listenable/railtie' if defined?(Rails)

module Listenable
  mattr_accessor :enabled, default: true

  # Connection pool safety configuration
  mattr_accessor :connection_checkout_timeout, default: 5 # seconds
  mattr_accessor :max_thread_pool_ratio, default: 0.25 # 25% of connection pool
  mattr_accessor :max_thread_pool_size, default: 3 # absolute max threads

  class Error < StandardError; end
  class ConnectionPoolExhausted < Error; end

  class << self
    attr_writer :async_executor

    # Registry of all listener classes (better than ObjectSpace scan)
    def listener_classes
      @listener_classes ||= Set.new
    end

    # Register a listener class when Listenable is included
    def register_listener(klass)
      listener_classes.add(klass) if klass.name && !klass.name.empty?
    end

    # Clear registry on reload
    def clear_listeners!
      @listener_classes = Set.new
    end

    # Track active subscribers to prevent memory leaks on reload
    def subscribers
      @subscribers ||= []
    end

    # Calculate a safe thread pool size based on connection pool
    # Very conservative: use configurable ratio of pool (default 25%)
    def default_thread_pool_size
      return 2 unless defined?(ActiveRecord::Base)

      pool_size = ActiveRecord::Base.connection_pool.size
      # Use configured ratio of pool, but at least 1 thread, max configured limit
      [[pool_size * max_thread_pool_ratio, 1].max, max_thread_pool_size].min.to_i
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

      # Clear listener registry for fresh reload
      clear_listeners!

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
