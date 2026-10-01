# frozen_string_literal: true

require 'yaml'

module Belt
  module Jobs
    class RecurringConfig
      JOB_CLASS = /\A[A-Z]\w*(?:::[A-Z]\w*)*\z/

      def self.load(path)
        raw = File.exist?(path) ? YAML.safe_load_file(path, aliases: true) : {}
        new(raw || {})
      rescue Psych::Exception => e
        raise ConfigurationError, "invalid recurring jobs YAML: #{e.message}"
      end

      attr_reader :entries

      def initialize(entries)
        @entries = entries
      end

      def validate!
        raise ConfigurationError, 'recurring jobs config must be a map' unless entries.is_a?(Hash)

        entries.each do |name, entry|
          validate_entry!(name, entry)
        end
        self
      end

      private

      def validate_entry!(name, entry)
        raise ConfigurationError, "recurring job #{name.inspect} must be a map" unless entry.is_a?(Hash)

        job_class = entry['class'] || entry[:class]
        schedule = entry['schedule'] || entry[:schedule]
        arguments = entry.fetch('args', entry.fetch(:args, []))
        timezone = entry.fetch('timezone', entry.fetch(:timezone, 'UTC'))

        unless job_class.to_s.match?(JOB_CLASS)
          raise ConfigurationError, "recurring job #{name.inspect} has an invalid class"
        end

        Schedule.compile(schedule)
        raise ConfigurationError, "recurring job #{name.inspect} args must be an array" unless arguments.is_a?(Array)
        return unless timezone.to_s.empty?

        raise ConfigurationError, "recurring job #{name.inspect} timezone cannot be blank"
      end
    end
  end
end
