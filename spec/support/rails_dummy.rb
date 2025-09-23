# frozen_string_literal: true

require 'active_record'
require 'rails'
require 'ostruct'
require 'concurrent'
require 'listenable/railtie'

module Rails
  def self.root
    Pathname.new(File.expand_path('../..', __dir__))
  end

  def self.application
    @application ||= begin
      app = Object.new
      def app.config
        @config ||= OpenStruct.new
      end
      app
    end
  end
end

class OpenStruct
  def to_prepare(&block)
    block.call
  end
end

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.define(version: 1) do
  create_table :users, force: true do |t|
    t.string :name
  end
end

class User < ActiveRecord::Base; end

class UserListener
  include Listenable

  listen :on_created
  listen :on_updated, async: true

  class << self
    attr_accessor :sync_called, :async_called

    def on_created(_)
      self.sync_called = true
    end

    def on_updated(_)
      self.async_called = true
    end
  end
end

initializer = Listenable::Railtie.initializers.find { |i| i.name == 'listenable.load' }
initializer.run(Rails.application)
