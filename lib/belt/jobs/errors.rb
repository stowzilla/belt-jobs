# frozen_string_literal: true

module Belt
  module Jobs
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class PayloadTooLargeError < Error; end
    class DisallowedJobError < Error; end
  end
end
