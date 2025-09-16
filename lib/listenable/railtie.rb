# frozen_string_literal: true

module Listenable
  class Railtie < Rails::Railtie
    initializer "listenable.load" do
      Rails.application.config.to_prepare do
        # Load all listeners (supports nested paths)
        Dir[Rails.root.join("app/listeners/**/*.rb")].each { |f| require_dependency f }

        # Wire models + listeners
        ObjectSpace.each_object(Class).select { |klass| klass < Listenable }.each do |listener_class|
          model_class_name = listener_class.name.sub("Listener", "")
          model_class = model_class_name.safe_constantize
          next unless model_class

          listener_class.pending_hooks.each do |hook|
            action   = hook.sub("on_", "")
            callback = Listenable::CALLBACK_MAP[action] or next
            method   = "on_#{action}"
            event    = "#{model_class_name.underscore}.#{action}"

            # Avoid duplicate subscriptions on reload
            ActiveSupport::Notifications.notifier.listeners_for(event).each do |subscriber|
              ActiveSupport::Notifications.unsubscribe(subscriber)
            end

            # Inject ActiveRecord callback
            model_class.send(callback) do
              ActiveSupport::Notifications.instrument(event, record: self)
            end

            # Subscribe listener
            next unless listener_class.respond_to?(method)

            ActiveSupport::Notifications.subscribe(event) do |*args|
              _name, _start, _finish, _id, payload = args
              listener_class.public_send(method, payload[:record])
            end
          end
        end
      end
    end
  end
end
