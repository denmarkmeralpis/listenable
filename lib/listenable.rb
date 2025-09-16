# frozen_string_literal: true

require "active_support"
require "active_support/concern"
require "active_support/notifications"

require_relative "listenable/version"
require_relative "listenable/concern"
require_relative "listenable/railtie" if defined?(Rails)

module Listenable
  class Error < StandardError; end
  # Your code goes here...
end
