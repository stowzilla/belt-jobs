# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Belt::Jobs::Configuration do
  it 'has a default configuration' do
    expect(Belt::Jobs.configuration).to be_a(described_class)
  end

  it 'accepts configure block' do
    Belt::Jobs.configure do |config|
      config.logger = :test_logger
    end

    expect(Belt::Jobs.configuration.logger).to eq(:test_logger)
  end
end
