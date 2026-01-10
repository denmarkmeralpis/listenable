# frozen_string_literal: true

module Listenable
  class Railtie < Rails::Railtie
    initializer 'listenable.load' do
      Rails.application.config.to_prepare do
        # Load all listeners (recursive, supports namespaced)
        Dir[Rails.root.join('app/listeners/**/*.rb')].each { |f| require_dependency f }

        # Find all listener classes
        ObjectSpace.each_object(Class).select { |klass| klass < Listenable }.each do |listener_class|
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

            ActiveSupport::Notifications.subscribe(event) do |*args|
              next unless Listenable.enabled

              _name, _start, _finish, _id, payload = args
              record = payload[:record]

              if async
                # Pass only the record ID and class to avoid connection pool issues
                record_id = record.id
                record_class = record.class

                # Use bounded thread pool to prevent spawning unlimited threads
                Concurrent::Promises.future_on(Listenable.async_executor) do
                  # Wrap in connection pool management to prevent connection exhaustion
                  ActiveRecord::Base.connection_pool.with_connection do
                    # Reload the record in this thread's connection
                    reloaded_record = record_class.find_by(id: record_id)

                    if reloaded_record
                      listener_class.public_send(method, reloaded_record)
                    elsif defined?(Rails) && Rails.logger
                      Rails.logger.warn(
                        "[Listenable] Record #{record_class}##{record_id} not found for #{listener_class}##{method}"
                      )
                    end
                  end
                rescue StandardError => e
                  if defined?(Rails) && Rails.logger
                    Rails.logger.error("[Listenable] #{listener_class}##{method} failed: #{e.message}")
                    Rails.logger.error(e.backtrace.join("\n"))
                  end
                  raise e # Re-raise so the promise chain can handle it
                end.rescue do |e|
                  if defined?(Rails) && Rails.logger
                    Rails.logger.error("[Listenable] Promise failed for #{listener_class}##{method}: #{e.message}")
                  end
                end
              else
                listener_class.public_send(method, record)
              end
            end
          end
        end
      end
    end
  end
end
