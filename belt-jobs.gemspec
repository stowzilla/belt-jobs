# frozen_string_literal: true

require_relative 'lib/belt/jobs/version'

Gem::Specification.new do |spec|
  spec.name          = 'belt-jobs'
  spec.version       = Belt::Jobs::VERSION
  spec.authors       = ['Stowzilla']
  spec.email         = ['andy@stowzilla.com', 'adam@stowzilla.com']

  spec.summary       = 'Active Job and scheduled jobs for Belt applications on AWS Lambda'
  spec.description   = 'A Belt plugin that runs Active Job on AWS Lambda with SQS, ' \
                       'EventBridge Scheduler, recurring schedules, retries, and DLQs.'
  spec.homepage      = 'https://github.com/stowzilla/belt-jobs'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.3'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*', 'LICENSE', 'README.md', 'CHANGELOG.md', 'AGENTS.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'activejob', '= 8.1.4'
  spec.add_dependency 'aws-sdk-scheduler', '= 1.51.0'
  spec.add_dependency 'aws-sdk-sqs', '= 1.119.0'
  spec.add_dependency 'belt', '= 0.4.7'
end
