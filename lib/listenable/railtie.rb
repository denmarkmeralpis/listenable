# frozen_string_literal: true

module Listenable
  class Railtie < Rails::Railtie
    AFTER_COMMIT_MAP = {
      'created'  => :create,
      'updated'  => :update,
      'destroyed' => :destroy
    }.freeze

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
        Dir[Rails.root.join('app/listeners/**/*.rb')].each do |file|
          require_dependency file
        end

        Listenable.listener_classes.each do |listener_class|
          model_class_name = listener_class.name.sub('Listener', '')
          model_class      = model_class_name.safe_constantize
          next unless model_class

          injected_events =
            model_class.instance_variable_get(:@_listenable_injected_events) || []

          listener_class.pending_hooks.each do |hook_info|
            hook     = hook_info[:name]
            async    = hook_info[:async]
            action   = hook.sub('on_', '')
            method   = "on_#{action}"
            event    = "#{model_class_name.underscore}.#{action}"

            next unless listener_class.respond_to?(method)

            # Inject callback once per model
            unless injected_events.include?(event)
              commit_action = AFTER_COMMIT_MAP[action]
              next unless commit_action

              model_class.after_commit(on: commit_action) do
                next unless Listenable.enabled

                ActiveSupport::Notifications.instrument(
                  event,
                  record_class: self.class,
                  record_id: id
                )
              end

              injected_events << event
              model_class.instance_variable_set(
                :@_listenable_injected_events,
                injected_events
              )
            end

            # Subscribe (only once per reload)
            subscriber = ActiveSupport::Notifications.subscribe(event) do |*args|
              next unless Listenable.enabled

              _name, _start, _finish, _id, payload = args

              if async
                Railtie.handle_async_listener(
                  listener_class,
                  method,
                  payload[:record_class],
                  payload[:record_id]
                )
              else
                Railtie.handle_sync_listener(
                  listener_class,
                  method,
                  payload[:record_class],
                  payload[:record_id]
                )
              end
            end

            Listenable.subscribers << subscriber
          end
        end
      end
    end

    class << self
      def handle_async_listener(listener_class, method, record_class, record_id)
        Concurrent::Promises.future_on(Listenable.async_executor) do
          ActiveRecord::Base.connection_pool.with_connection do
            execute_listener(listener_class, method, record_class, record_id)
          end
        rescue ActiveRecord::ConnectionTimeoutError => e
          Rails.logger&.error(
            "[Listenable] DB pool exhausted for #{listener_class}##{method}: #{e.message}"
          )
        rescue StandardError => e
          log_error(listener_class, method, e)
        end
      end

      def handle_sync_listener(listener_class, method, record_class, record_id)
        execute_listener(listener_class, method, record_class, record_id)
      rescue StandardError => e
        log_error(listener_class, method, e)
        raise
      end

      private

      def execute_listener(listener_class, method, record_class, record_id)
        record = record_class.find_by(id: record_id)

        unless record
          Rails.logger&.warn(
            "[Listenable] #{record_class}##{record_id} not found for #{listener_class}##{method}"
          )
          return
        end

        listener_class.public_send(method, record)
      end

      def log_error(listener_class, method, error)
        Rails.logger&.error(
          "[Listenable] #{listener_class}##{method} failed: " \
          "#{error.message}\n#{error.backtrace.first(5).join("\n")}"
        )
      end
    end
  end
end
