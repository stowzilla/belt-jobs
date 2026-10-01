# belt-jobs

Active Job for Belt applications on AWS Lambda: SQS-backed execution, delayed jobs, recurring EventBridge schedules, DLQs, alarms, and Rails-style generators.

## Installation

```ruby
# Gemfile
gem "belt-jobs", "0.0.1"
```

```sh
bundle install
belt g jobs
belt g job nightly_cleanup
```

`belt g jobs` installs and wires the queue, worker Lambda, Scheduler IAM, recurring schedules, DLQs, alarms, and `ApplicationJob`. `belt g job` auto-installs that shared infrastructure if needed.

## Active Job API

Generated jobs are ordinary Active Job classes:

```ruby
class NightlyCleanupJob < ApplicationJob
  queue_as :default
  retry_on Net::ReadTimeout, wait: :polynomially_longer, attempts: 5

  def perform(account_id)
    # Keep jobs idempotent: SQS and Lambda provide at-least-once delivery.
  end
end
```

Use the standard API from controllers, models, the console, or other jobs:

```ruby
NightlyCleanupJob.perform_now(account.id)
NightlyCleanupJob.perform_later(account.id)
NightlyCleanupJob.set(wait: 10.minutes).perform_later(account.id)
NightlyCleanupJob.set(wait_until: tomorrow.noon).perform_later(account.id)
```

Immediate jobs and delays up to 15 minutes use SQS directly. Longer delays create a one-time EventBridge Scheduler schedule that deletes itself after delivery. Every path targets the same SQS queue and worker Lambda.

## Recurring jobs

Generate and schedule in one command:

```sh
belt g job daily_digest \
  --schedule "every day at 9am" \
  --timezone America/New_York
```

Supported friendly schedules are `every N minutes|hours|days` and `every day at 9am` / `daily 09:00`. Native AWS `cron(...)` and `rate(...)` expressions are accepted directly. The generator writes `config/recurring.yml`:

```yaml
daily_digest:
  class: DailyDigestJob
  args: []
  schedule: cron(0 9 * * ? *)
  timezone: America/New_York
  queue: default
  enabled: true
```

Recurring arguments must be YAML/JSON values. There is deliberately no arbitrary `command:` evaluation.

## Generated files

```text
infrastructure/modules/jobs/       SQS, DLQs, Scheduler, IAM, alarms
config/lambda/jobs.yml             15-minute worker + partial batch failures
config/recurring.yml               recurring definitions
lambda/jobs.rb                     Lambda entrypoint
lambda/jobs/application_job.rb     app-owned Active Job base
lambda/jobs/*_job.rb               generated jobs
```

The installer updates the standard `infrastructure/modules/app/main.tf` and `lambda/config/environment.rb`. It is idempotent, supports `--force`, and `belt d jobs` removes its files and marked wiring. `belt d job NAME` removes one class and its recurring entry.

## Configuration

Terraform supplies production settings through environment variables. Tests and unusual deployments can configure the runtime directly:

```ruby
Belt::Jobs.configure do |config|
  config.queue_url = "https://sqs.us-east-1.amazonaws.com/123/jobs"
  config.queue_arn = "arn:aws:sqs:us-east-1:123:jobs"
  config.scheduler_role_arn = "arn:aws:iam::123:role/jobs-scheduler"
  config.allowed_job_classes = [NightlyCleanupJob]
end
Belt::Jobs.configure_active_job!
```

| Environment variable | Purpose |
|---|---|
| `BELT_JOBS_QUEUE_URL` | SQS enqueue URL |
| `BELT_JOBS_QUEUE_ARN` | Scheduler target ARN |
| `BELT_JOBS_SCHEDULER_ROLE_ARN` | Role Scheduler assumes to send to SQS |
| `BELT_JOBS_SCHEDULER_DLQ_ARN` | Failed Scheduler delivery queue |
| `BELT_JOBS_SCHEDULE_GROUP_NAME` | Group for one-time and recurring schedules |

By default, the worker allowlists the loaded concrete `ApplicationJob` descendants before resolving a class name. Set `allowed_job_classes` to tighten this further.

## Reliability contract

- Delivery is **at least once**. Job code must be idempotent.
- `retry_on`, `discard_on`, callbacks, serialization, and `perform_now` are Active Job behavior.
- Handled `retry_on` errors enqueue a replacement and acknowledge the current SQS record.
- Unhandled, malformed, or disallowed records are returned in `batchItemFailures`; SQS retries them and then moves them to the execution DLQ.
- Serialized payloads are capped at 256 KiB. Prefer IDs over large object graphs.
- Jobs have Lambda's 900-second execution ceiling.
- Long and recurring schedules have EventBridge Scheduler's one-minute delivery precision.
- The generated worker uses bounded concurrency and emits Belt `JobEnqueued`, `JobSucceeded`, and `JobFailed` metrics.

## Removing

```sh
belt d job nightly_cleanup
belt d jobs
```

## Development

```sh
bundle install
bundle exec rspec
bundle exec rubocop
bundle exec rake build
```

## License

MIT
