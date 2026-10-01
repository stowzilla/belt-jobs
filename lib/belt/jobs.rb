# frozen_string_literal: true

require 'active_job'
require 'belt'

require_relative 'jobs/version'
require_relative 'jobs/errors'
require_relative 'jobs/configuration'
require_relative 'jobs/schedule'
require_relative 'jobs/recurring_config'
require_relative 'jobs/queue_adapter'
require_relative 'jobs/worker'
require_relative 'jobs/lambda_handler'

module Belt
  module Jobs
    class << self
      attr_writer :configuration

      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
      end

      def configure_active_job!
        ActiveJob::Base.queue_adapter = QueueAdapter.new(configuration)
      end

      def reset_configuration!
        @configuration = Configuration.new
      end
    end
  end
end
