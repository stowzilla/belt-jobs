# frozen_string_literal: true

require 'json'

module Belt
  module Jobs
    class Worker
      def initialize(configuration = Belt::Jobs.configuration)
        @configuration = configuration
      end

      def call(event:, context: nil)
        failures = records(event).filter_map do |record|
          process_record(record, context: context) ? nil : { 'itemIdentifier' => message_id(record) }
        end
        { 'batchItemFailures' => failures }
      end

      private

      attr_reader :configuration

      def records(event)
        event['Records'] || event[:Records] || []
      end

      def process_record(record, context:)
        payload = JSON.parse(record['body'] || record[:body] || '')
        job_class = job_class_name(payload)
        ensure_allowed!(job_class)

        log(:info, 'Job started', job_class: job_class, message_id: message_id(record))
        recurring_payload?(payload) ? perform_recurring(payload.fetch('belt_jobs')) : ActiveJob::Base.execute(payload)
        metric('JobSucceeded', job_class: job_class)
        log(:info, 'Job completed', job_class: job_class, message_id: message_id(record))
        true
      rescue StandardError => e
        metric('JobFailed', job_class: defined?(job_class) ? job_class : 'unknown')
        log(:error, 'Job failed', e, message_id: message_id(record), request_id: context&.aws_request_id)
        false
      end

      def recurring_payload?(payload)
        payload['belt_jobs'].is_a?(Hash)
      end

      def job_class_name(payload)
        recurring_payload?(payload) ? payload.dig('belt_jobs', 'job_class') : payload['job_class']
      end

      def ensure_allowed!(job_class)
        return if job_class.is_a?(String) && configuration.allowed_job_class_names.include?(job_class)

        raise DisallowedJobError, "job class #{job_class.inspect} is not allowed"
      end

      def perform_recurring(payload)
        klass = constantize(payload.fetch('job_class'))
        raise DisallowedJobError, "#{klass.name} is not an Active Job class" unless klass <= ActiveJob::Base

        job = klass.new(*Array(payload['arguments']))
        job.queue_name = payload['queue'] if payload['queue']
        job.perform_now
      end

      def constantize(name)
        name.split('::').inject(Object) { |scope, constant| scope.const_get(constant, false) }
      rescue NameError
        raise DisallowedJobError, "job class #{name.inspect} is not defined"
      end

      def message_id(record)
        record['messageId'] || record[:messageId] || 'unknown'
      end

      def metric(name, **dimensions)
        configuration.resolved_metrics&.track_event(name, **dimensions)
      end

      def log(level, message, exception = nil, **context)
        logger = configuration.resolved_logger
        return unless logger

        if exception
          logger.public_send(level, message, exception,
                             **context)
        else
          logger.public_send(level, message, **context)
        end
      end
    end
  end
end
