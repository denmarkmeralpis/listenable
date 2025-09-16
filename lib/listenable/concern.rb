# frozen_string_literal: true

module Listenable
  CALLBACK_MAP = {
    "created" => :after_create,
    "updated" => :after_update,
    "deleted" => :after_destroy
  }.freeze

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def listen(*hooks)
      @pending_hooks ||= []
      @pending_hooks.concat(hooks.map(&:to_s))
    end

    def pending_hooks
      @pending_hooks || []
    end
  end
end
