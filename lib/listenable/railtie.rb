# frozen_string_literal: true

module Listenable
  class Railtie < Rails::Railtie
    initializer "listenable.load" do
      Rails.application.config.to_prepare do
        # Load all listeners (recursive, supports namespaced)
        Dir[Rails.root.join("app/listeners/**/*.rb")].each { |f| require_dependency f }

        # Find all listener classes
        ObjectSpace.each_object(Class).select { |klass| klass < Listenable }.each do |listener_class|
          model_class_name = listener_class.name.sub("Listener", "")
          model_class      = model_class_name.safe_constantize
          next unless model_class

          listener_class.pending_hooks.each do |hook|
            action   = hook.sub("on_", "")
            callback = Listenable::CALLBACK_MAP[action] or next
            method   = "on_#{action}"
            event    = "#{model_class_name.underscore}.#{action}"

            # Unsubscribe duplicates
            ActiveSupport::Notifications.notifier.listeners_for(event).each do |subscriber|
              ActiveSupport::Notifications.unsubscribe(subscriber)
            end

            # Inject AR callback once per model/event
            injected_events = model_class.instance_variable_get(:@_listenable_injected_events) || []
            unless injected_events.include?(event)
              model_class.send(callback) do
                next unless Listenable.enabled
                ActiveSupport::Notifications.instrument(event, record: self)
              end
              injected_events << event
              model_class.instance_variable_set(:@_listenable_injected_events, injected_events)
            end

            # Subscribe listener (runtime-guarded)
            if listener_class.respond_to?(method)
              ActiveSupport::Notifications.subscribe(event) do |*args|
                next unless Listenable.enabled
                _name, _start, _finish, _id, payload = args
                listener_class.public_send(method, payload[:record])
              end
            end
          end
        end
      end
    end
  end
end
