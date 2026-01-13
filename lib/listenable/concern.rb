# frozen_string_literal: true

module Listenable
  extend ActiveSupport::Concern

  CALLBACK_MAP = {
    'created' => :after_create,
    'updated' => :after_update,
    'deleted' => :after_destroy
  }.freeze

  included do
    # Register this class when Listenable is included
    Listenable.register_listener(self)
  end

  class_methods do
    def listen(*hooks, async: false)
      @pending_hooks ||= []

      hooks.each do |hook|
        @pending_hooks << { name: hook.to_s, async: async }
      end
    end

    def pending_hooks
      @pending_hooks || []
    end
  end
end
