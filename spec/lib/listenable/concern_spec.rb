# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Listenable do
  before { Listenable.enabled = true }

  it 'accepts listen without async' do
    klass = Class.new do
      include Listenable

      listen :on_created
    end

    expect { klass }.not_to raise_error
  end

  it 'accepts listen with async' do
    klass = Class.new do
      include Listenable

      listen :on_created, :on_updated, async: true
    end

    expect { klass }.not_to raise_error
  end
end
