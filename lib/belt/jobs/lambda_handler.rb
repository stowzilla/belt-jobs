# frozen_string_literal: true

require 'lambda_loadout'

module Belt
  module Jobs
    module LambdaHandler
      def lambda_handler(event:, context:)
        service_name = ENV['ACTION'] || context.function_name.split('-').last
        logger = LambdaLoadout::Logger.new(service: service_name)
        metrics = LambdaLoadout::Metrics.new(
          namespace: ENV['BELT_METRICS_NAMESPACE'] || 'Belt',
          service: service_name
        )
        Belt::Observability::Logger.instance = logger
        Belt::Observability::Metrics.instance = metrics

        LambdaLoadout.with_logging_and_metrics(
          logger,
          metrics,
          context,
          event: event,
          error_notification_config: { sns_topic_arn: ENV.fetch('ERROR_NOTIFICATION_TOPIC_ARN', nil) }
        ) do
          Worker.new.call(event: event, context: context)
        end
      end
    end
  end
end
