# frozen_string_literal: true

module Listenable
  class Railtie < Rails::Railtie
    # Cleanup on Rails reload to prevent memory leaks
    config.to_prepare do
      Listenable.cleanup!
    end

    # Graceful shutdown on Rails exit
    config.after_initialize do
      at_exit do
        Listenable.shutdown_async_executor!
      end
    end

    initializer 'listenable.load' do
      Rails.application.config.to_prepare do
        # Load all listeners (recursive, supports namespaced)
        listener_files = Dir[Rails.root.join('app/listeners/**/*.rb')]
        listener_files.each { |f| require_dependency f }

        # Find all listener classes
        listener_classes = ObjectSpace.each_object(Class).select { |klass| klass < Listenable }
        listener_classes.each do |listener_class|
          model_class_name = listener_class.name.sub('Listener', '')
          model_class      = model_class_name.safe_constantize
          next unless model_class

          listener_class.pending_hooks.each do |hook_info|
            hook     = hook_info[:name]
            async    = hook_info[:async]
            action   = hook.sub('on_', '')
            callback = Listenable::CALLBACK_MAP[action] or next
            method   = "on_#{action}"
            event    = "#{model_class_name.underscore}.#{action}"

            # unsubscribe old subscribers
            ActiveSupport::Notifications.notifier.listeners_for(event).each do |subscriber|
              ActiveSupport::Notifications.unsubscribe(subscriber)
            end

            injected_events = model_class.instance_variable_get(:@_listenable_injected_events) || []
            unless injected_events.include?(event)
              model_class.send(callback) do
                next unless Listenable.enabled

                ActiveSupport::Notifications.instrument(event, record: self)
              end
              injected_events << event
              model_class.instance_variable_set(:@_listenable_injected_events, injected_events)
            end

            next unless listener_class.respond_to?(method)

            # Subscribe and track subscriber for cleanup
            subscriber = ActiveSupport::Notifications.subscribe(event) do |*args|
              next unless Listenable.enabled

              _name, _start, _finish, _id, payload = args
              record = payload[:record]

              if async
                Railtie.handle_async_listener(listener_class, method, record)
              else
                Railtie.handle_sync_listener(listener_class, method, record)
              end
            end

            # Track subscriber for cleanup on reload
            Listenable.subscribers << subscriber
          end
        end
      end
    end

    class << self
      # Handle async listener with proper error handling and connection management
      def handle_async_listener(listener_class, method, record)
        # Extract minimal data to pass to thread
        record_id = record.id
        record_class = record.class

        # Use bounded thread pool to prevent spawning unlimited threads
        Concurrent::Promises.future_on(Listenable.async_executor) do
          # Wrap in connection pool management to prevent connection exhaustion
          ActiveRecord::Base.connection_pool.with_connection do
            execute_listener(listener_class, method, record_class, record_id)
          rescue StandardError => e
            log_error(listener_class, method, e)
          end
        end.rescue do |e|
          Rails.logger&.error(
            "[Listenable] Promise failed for #{listener_class}##{method}: #{e.message}"
          )
        end
      end

      # Handle sync listener with proper error handling
      def handle_sync_listener(listener_class, method, record)
        listener_class.public_send(method, record)
      rescue StandardError => e
        log_error(listener_class, method, e)
        raise # Re-raise for sync listeners to maintain transaction integrity
      end

      private

      def execute_listener(listener_class, method, record_class, record_id)
        reloaded_record = record_class.find_by(id: record_id)

        if reloaded_record
          listener_class.public_send(method, reloaded_record)
        else
          Rails.logger&.warn(
            "[Listenable] Record #{record_class}##{record_id} not found for #{listener_class}##{method}"
          )
        end
      end

      def log_error(listener_class, method, error)
        Rails.logger&.error(
          "[Listenable] #{listener_class}##{method} failed: #{error.message}\n#{error.backtrace.first(5).join("\n")}"
        )
      end
    end
  end
end
