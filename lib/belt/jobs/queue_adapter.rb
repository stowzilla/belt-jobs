# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'time'

module Belt
  module Jobs
    class QueueAdapter
      MAX_SQS_DELAY_SECONDS = 15 * 60

      def initialize(configuration = Belt::Jobs.configuration)
        @configuration = configuration
      end

      def enqueue(job)
        enqueue_at(job, Time.now.to_f)
      end

      def enqueue_at(job, timestamp)
        payload = JSON.generate(job.serialize)
        validate_payload!(payload)
        delay = [timestamp.to_f - Time.now.to_f, 0].max

        provider_job_id = if delay <= MAX_SQS_DELAY_SECONDS
                            enqueue_sqs(payload, delay.ceil)
                          else
                            enqueue_scheduler(job, payload, timestamp)
                          end
        job.provider_job_id = provider_job_id if job.respond_to?(:provider_job_id=)
        metric('JobEnqueued', queue: job.queue_name)
        provider_job_id
      end

      private

      attr_reader :configuration

      def enqueue_sqs(payload, delay_seconds)
        configuration.validate_queue!
        response = configuration.sqs.send_message(
          queue_url: configuration.queue_url,
          message_body: payload,
          delay_seconds: delay_seconds
        )
        response.message_id
      end

      def enqueue_scheduler(job, payload, timestamp)
        configuration.validate_scheduler!
        target = {
          arn: configuration.queue_arn,
          role_arn: configuration.scheduler_role_arn,
          input: payload
        }
        if configuration.scheduler_dlq_arn && !configuration.scheduler_dlq_arn.empty?
          target[:dead_letter_config] = { arn: configuration.scheduler_dlq_arn }
        end

        response = configuration.scheduler.create_schedule(
          name: schedule_name(job),
          group_name: configuration.schedule_group_name,
          schedule_expression: "at(#{Time.at(timestamp).utc.strftime('%Y-%m-%dT%H:%M:%S')})",
          schedule_expression_timezone: 'UTC',
          flexible_time_window: { mode: 'OFF' },
          action_after_completion: 'DELETE',
          target: target
        )
        response.schedule_arn
      end

      def schedule_name(job)
        "belt-job-#{job.job_id.to_s.gsub(/[^a-zA-Z0-9_-]/, '')}-#{SecureRandom.hex(4)}"[0, 64]
      end

      def validate_payload!(payload)
        return if payload.bytesize <= configuration.max_payload_bytes

        raise PayloadTooLargeError,
              "serialized job is #{payload.bytesize} bytes; maximum is #{configuration.max_payload_bytes}"
      end

      def metric(name, **dimensions)
        configuration.resolved_metrics&.track_event(name, **dimensions)
      end
    end
  end
end
