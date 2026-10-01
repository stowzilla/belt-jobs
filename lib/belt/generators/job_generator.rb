# frozen_string_literal: true

require 'fileutils'
require 'yaml'
require_relative 'jobs_generator'
require_relative '../jobs'

module Belt
  module Generators
    class JobGenerator
      def self.description
        'Generate an Active Job class (optionally recurring)'
      end

      def self.run(args)
        return print_help if args.include?('--help') || args.include?('-h')

        new(args).generate
      end

      def self.destroy(args)
        new(args).destroy
      end

      def self.print_help
        puts <<~HELP
          Generate an Active Job class.

          Usage: belt generate job NAME [options]

          Options:
            --queue NAME           Active Job queue name (default: default)
            --schedule SCHEDULE    cron(...), rate(...), "every N minutes", or "every day at 9am"
            --timezone ZONE        EventBridge schedule timezone (default: UTC)
            --force                Overwrite an existing job

          Examples:
            belt g job nightly_cleanup
            belt g job daily_digest --schedule "every day at 9am" --timezone America/New_York
            belt d job daily_digest
        HELP
      end

      def initialize(args)
        @options = parse(args)
        @name = @options.delete(:name)
        @force = @options.delete(:force)
      end

      def generate
        abort_with_usage unless @name
        JobsGenerator.run([]) unless File.exist?('lambda/jobs/application_job.rb')
        destination = "lambda/jobs/#{underscored_name}_job.rb"
        if File.exist?(destination) && !@force
          puts "  skip    #{destination} (already exists, use --force to overwrite)"
        else
          FileUtils.mkdir_p(File.dirname(destination))
          File.write(destination, job_source)
          puts "  create  #{destination}"
        end
        add_recurring_schedule if @options[:schedule]
        puts "\n✓ Generated #{class_name}"
      end

      def destroy
        abort_with_usage unless @name
        destination = "lambda/jobs/#{underscored_name}_job.rb"
        FileUtils.rm_f(destination)
        remove_recurring_schedule
        puts "\n✓ Removed #{class_name}"
      end

      private

      def parse(args)
        options = { queue: 'default', timezone: 'UTC', force: false }
        index = 0
        while index < args.length
          argument = args[index]
          case argument
          when '--queue', '--schedule', '--timezone'
            index += 1
            options[argument.delete_prefix('--').to_sym] = args[index]
          when /\A--(queue|schedule|timezone)=(.*)\z/
            options[Regexp.last_match(1).to_sym] = Regexp.last_match(2)
          when '--force'
            options[:force] = true
          else
            raise Belt::Jobs::ConfigurationError, "unknown option #{argument}" if argument.start_with?('-')

            options[:name] ||= argument
          end
          index += 1
        end
        options
      end

      def underscored_name
        @name.to_s.gsub('::', '/').gsub(/([a-z\d])([A-Z])/, '\\1_\\2').tr('-', '_').downcase.sub(/_job\z/, '')
      end

      def class_name
        "#{underscored_name.split('/').map do |part|
          part.split('_').map(&:capitalize).join
        end.join('::')}Job"
      end

      def schedule_key
        underscored_name.tr('/', '_')
      end

      def job_source
        modules = class_name.split('::')
        klass = modules.pop
        indent = ''
        source = +"# frozen_string_literal: true\n\n"
        modules.each do |mod|
          source << "#{indent}module #{mod}\n"
          indent += '  '
        end
        source << <<~RUBY.gsub(/^/, indent)
          class #{klass} < ApplicationJob
            queue_as :#{@options[:queue]}

            def perform(*args)
              # Do work here. Jobs are at-least-once; keep this method idempotent.
            end
          end
        RUBY
        modules.reverse_each do
          indent = indent[0...-2]
          source << "#{indent}end\n"
        end
        source
      end

      def add_recurring_schedule
        path = 'config/recurring.yml'
        config = File.exist?(path) ? (YAML.safe_load_file(path, aliases: true) || {}) : {}
        config[schedule_key] = {
          'class' => class_name,
          'args' => [],
          'schedule' => Belt::Jobs::Schedule.compile(@options[:schedule]),
          'timezone' => @options[:timezone],
          'queue' => @options[:queue],
          'enabled' => true
        }
        Belt::Jobs::RecurringConfig.new(config).validate!
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, YAML.dump(config))
        puts "  update  #{path}"
      end

      def remove_recurring_schedule
        path = 'config/recurring.yml'
        return unless File.exist?(path)

        config = YAML.safe_load_file(path, aliases: true) || {}
        return unless config.delete(schedule_key)

        File.write(path, YAML.dump(config))
        puts "  update  #{path}"
      end

      def abort_with_usage
        raise Belt::Jobs::ConfigurationError, 'Usage: belt generate job NAME [options]'
      end
    end
  end
end
