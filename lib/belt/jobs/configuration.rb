# frozen_string_literal: true

require 'aws-sdk-scheduler'
require 'aws-sdk-sqs'

module Belt
  module Jobs
    class Configuration
      DEFAULT_MAX_PAYLOAD_BYTES = 256 * 1024

      attr_writer :queue_url, :queue_arn, :scheduler_role_arn, :scheduler_dlq_arn,
                  :schedule_group_name, :aws_region
      attr_accessor :logger, :metrics, :sqs_client, :scheduler_client,
                    :allowed_job_classes, :max_payload_bytes

      def initialize
        @logger = nil
        @metrics = nil
        @sqs_client = nil
        @scheduler_client = nil
        @allowed_job_classes = nil
        @max_payload_bytes = DEFAULT_MAX_PAYLOAD_BYTES
      end

      def queue_url
        @queue_url || ENV.fetch('BELT_JOBS_QUEUE_URL', nil)
      end

      def queue_arn
        @queue_arn || ENV.fetch('BELT_JOBS_QUEUE_ARN', nil)
      end

      def scheduler_role_arn
        @scheduler_role_arn || ENV.fetch('BELT_JOBS_SCHEDULER_ROLE_ARN', nil)
      end

      def scheduler_dlq_arn
        @scheduler_dlq_arn || ENV.fetch('BELT_JOBS_SCHEDULER_DLQ_ARN', nil)
      end

      def schedule_group_name
        @schedule_group_name || ENV['BELT_JOBS_SCHEDULE_GROUP_NAME'] || 'belt-jobs'
      end

      def aws_region
        @aws_region || ENV['AWS_REGION'] || 'us-east-1'
      end

      def sqs
        @sqs ||= sqs_client || Aws::SQS::Client.new(region: aws_region)
      end

      def scheduler
        @scheduler ||= scheduler_client || Aws::Scheduler::Client.new(region: aws_region)
      end

      def validate_queue!
        return if present?(queue_url)

        raise ConfigurationError, 'BELT_JOBS_QUEUE_URL is required to enqueue jobs'
      end

      def validate_scheduler!
        missing = {
          'BELT_JOBS_QUEUE_ARN' => queue_arn,
          'BELT_JOBS_SCHEDULER_ROLE_ARN' => scheduler_role_arn
        }.reject { |_name, value| present?(value) }.keys
        return if missing.empty?

        raise ConfigurationError, "#{missing.join(', ')} required for delays over 15 minutes"
      end

      def allowed_job_class_names
        configured = Array(allowed_job_classes).filter_map do |entry|
          entry.is_a?(Class) ? entry.name : entry.to_s.strip
        end.reject(&:empty?)
        return configured unless configured.empty?

        ActiveJob::Base.descendants.filter_map(&:name).reject { |name| name == 'ApplicationJob' }
      end

      def resolved_logger
        logger || (Belt::Observability::Logger if defined?(Belt::Observability::Logger))
      end

      def resolved_metrics
        metrics || (Belt::Observability::Metrics if defined?(Belt::Observability::Metrics))
      end

      private

      def present?(value)
        !value.nil? && !value.to_s.empty?
      end
    end
  end
end
