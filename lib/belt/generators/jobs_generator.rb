# frozen_string_literal: true

require 'erb'
require 'fileutils'

module Belt
  module Generators
    class JobsGenerator
      TEMPLATE_DIR = File.expand_path('../jobs/templates', __dir__)
      APP_MODULE = 'infrastructure/modules/app/main.tf'
      ENVIRONMENT = 'lambda/config/environment.rb'
      JOBS_MODULE_MARKER = /\n?# belt-jobs:module:begin\n.*?# belt-jobs:module:end\n?/m
      ENV_REFS_MARKER = /\s*# belt-jobs:env-refs:begin\n.*?# belt-jobs:env-refs:end/m
      SHARED_IAM_MARKER = /\s*# belt-jobs:shared-iam:begin\n.*?# belt-jobs:shared-iam:end/m
      BOOT_MARKER = /\n# belt-jobs:boot:begin\n.*?# belt-jobs:boot:end\n?/m

      def self.description
        'Install Active Job on SQS + Lambda with delayed and recurring schedules'
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
          Install Active Job infrastructure for a Belt application.

          Usage: belt generate jobs [options]

          Options:
            --force               Overwrite generated files
            -h, --help            Show this help

          Creates:
            infrastructure/modules/jobs/   SQS, DLQs, Scheduler, IAM, alarms
            config/lambda/jobs.yml         Worker Lambda config and SQS trigger
            config/recurring.yml           Recurring jobs map
            lambda/jobs.rb                 SQS Lambda entry point
            lambda/jobs/application_job.rb Active Job base class

          The generator also wires the jobs module, Lambda environment references,
          producer IAM, shared job packaging, and app boot into the standard Belt app module.

          Examples:
            belt g jobs
            belt g job nightly_cleanup
            belt d jobs
        HELP
      end

      def initialize(args)
        @force = args.include?('--force')
      end

      def generate
        generate_files
        wire_app_module
        wire_environment
        puts <<~SUCCESS

          ✓ Jobs installed!

          Generate a job:
            belt g job nightly_cleanup
            belt g job daily_digest --schedule "every day at 9am" --timezone America/New_York

          Then deploy normally:
            belt deploy <env>
        SUCCESS
      end

      def destroy
        FileUtils.rm_rf('infrastructure/modules/jobs')
        FileUtils.rm_rf('lambda/jobs')
        %w[config/lambda/jobs.yml config/recurring.yml lambda/jobs.rb].each do |path|
          FileUtils.rm_f(path)
        end
        unwire_app_module
        unwire_environment
        puts "\n✓ Jobs removed!"
      end

      private

      def generate_files
        {
          'terraform/main.tf.erb' => 'infrastructure/modules/jobs/main.tf',
          'terraform/variables.tf.erb' => 'infrastructure/modules/jobs/variables.tf',
          'terraform/outputs.tf.erb' => 'infrastructure/modules/jobs/outputs.tf',
          'config/jobs.yml.erb' => 'config/lambda/jobs.yml',
          'config/recurring.yml.erb' => 'config/recurring.yml',
          'lambda/jobs.rb.erb' => 'lambda/jobs.rb',
          'lambda/application_job.rb.erb' => 'lambda/jobs/application_job.rb'
        }.each { |template, destination| write_template(template, destination) }
      end

      def wire_app_module
        return warn_missing(APP_MODULE) unless File.exist?(APP_MODULE)

        content = File.read(APP_MODULE)
        original = content.dup
        unless content.include?('# belt-jobs:module:begin')
          block = <<~HCL
            # belt-jobs:module:begin
            module "jobs" {
              source      = "../jobs"
              app_name    = var.app_name
              environment = var.environment
              aws_region  = var.aws_region
            }
            # belt-jobs:module:end

          HCL
          content.sub!('resource "conveyor_belt" "main" {', "#{block}resource \"conveyor_belt\" \"main\" {")
        end

        unless content.include?('# belt-jobs:env-refs:begin')
          content.sub!(/^(\s*)lambda_env_refs\s*=\s*var\.lambda_env_refs\s*$/) do
            indent = Regexp.last_match(1)
            <<~HCL.chomp
              #{indent}# belt-jobs:env-refs:begin
              #{indent}lambda_env_refs = merge(var.lambda_env_refs, {
              #{indent}  belt_jobs_queue_url          = module.jobs.queue_url
              #{indent}  belt_jobs_queue_arn          = module.jobs.queue_arn
              #{indent}  belt_jobs_scheduler_role_arn = module.jobs.scheduler_role_arn
              #{indent}  belt_jobs_scheduler_dlq_arn  = module.jobs.scheduler_dlq_arn
              #{indent}  belt_jobs_schedule_group     = module.jobs.schedule_group_name
              #{indent}})
              #{indent}# belt-jobs:env-refs:end
            HCL
          end
        end

        unless content.include?('shared_iam_policy_arns')
          content.sub!(/\n}\s*\z/, <<~HCL)

              # belt-jobs:shared-iam:begin
              shared_iam_policy_arns = [module.jobs.producer_policy_arn]
              # belt-jobs:shared-iam:end
            }
          HCL
        end

        content.sub!(/lambda_shared_dirs\s*=\s*\[([^\]]*)\]/) do |match|
          next match if match.include?('"jobs"')

          "#{match.sub(/\]\z/, ', "jobs"]')} # belt-jobs:shared-dir"
        end
        write_update(APP_MODULE, original, content)
      end

      def wire_environment
        return warn_missing(ENVIRONMENT) unless File.exist?(ENVIRONMENT)

        content = File.read(ENVIRONMENT)
        return if content.include?('jobs_dir =') || content.include?('# belt-jobs:boot:begin')

        original = content.dup
        content << <<~RUBY

          # belt-jobs:boot:begin
          jobs_dir = File.join(__dir__, '..', 'jobs')
          all_jobs = Dir[File.join(jobs_dir, '**', '*.rb')].sort
          application_job = all_jobs.find { |file| File.basename(file) == 'application_job.rb' }
          require application_job if application_job
          (all_jobs - [application_job].compact).each { |file| require file }
          # belt-jobs:boot:end
        RUBY
        write_update(ENVIRONMENT, original, content)
      end

      def unwire_app_module
        return unless File.exist?(APP_MODULE)

        content = File.read(APP_MODULE)
        original = content.dup
        content.gsub!(JOBS_MODULE_MARKER, '')
        content.gsub!(ENV_REFS_MARKER, "\n  lambda_env_refs = var.lambda_env_refs")
        content.gsub!(SHARED_IAM_MARKER, '')
        content.gsub!(/,\s*"jobs"\]\s*# belt-jobs:shared-dir/, ']')
        write_update(APP_MODULE, original, content)
      end

      def unwire_environment
        return unless File.exist?(ENVIRONMENT)

        content = File.read(ENVIRONMENT)
        original = content.dup
        content.gsub!(BOOT_MARKER, "\n")
        write_update(ENVIRONMENT, original, content)
      end

      def write_template(template, destination)
        if File.exist?(destination) && !@force
          puts "  skip    #{destination} (already exists)"
          return
        end

        source = File.join(TEMPLATE_DIR, template)
        FileUtils.mkdir_p(File.dirname(destination))
        File.write(destination, ERB.new(File.read(source), trim_mode: '-').result(binding))
        puts "  create  #{destination}"
      end

      def write_update(path, original, content)
        return if original == content

        File.write(path, content)
        puts "  update  #{path}"
      end

      def warn_missing(path)
        puts "  warn    #{path} not found; wire the jobs module manually"
      end
    end
  end
end
