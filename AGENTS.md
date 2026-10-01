# AGENTS.md — belt-jobs

This is the Belt Active Job plugin. Host apps own their job classes and generated Terraform; runtime behavior stays in this gem.

## Public contract

- `ApplicationJob < ActiveJob::Base`
- `perform_now`, `perform_later`, `set(wait:)`, `set(wait_until:)`
- `retry_on`, `discard_on`, callbacks, and Active Job serialization
- `belt g jobs`, `belt d jobs`, `belt g job NAME`, `belt d job NAME`

Immediate and <=900-second delays use SQS. Longer delays use one-time EventBridge Scheduler schedules targeting the same queue. Recurring Terraform schedules also target SQS. Execution is at least once.

## Layout

| Path | Responsibility |
|---|---|
| `lib/belt/jobs/queue_adapter.rb` | Active Job enqueue and delay routing |
| `lib/belt/jobs/worker.rb` | allowlisted execution + partial batch failures |
| `lib/belt/jobs/lambda_handler.rb` | Lambda Loadout lifecycle |
| `lib/belt/jobs/schedule.rb` | friendly schedule compiler |
| `lib/belt/jobs/recurring_config.rb` | recurring YAML validation |
| `lib/belt/generators/jobs_generator.rb` | shared infra installer/destroyer |
| `lib/belt/generators/job_generator.rb` | singular class/schedule generator |
| `lib/belt/jobs/templates/` | host-owned Terraform/config/Lambda files |

Belt discovers both generator files by path and class name; do not add a separate registry.

## Development

```sh
bundle install
bundle exec rspec
bundle exec rubocop
bundle exec rake build
```

For generator smoke testing, create a temporary standard Belt app module containing `infrastructure/modules/app/main.tf` and `lambda/config/environment.rb`, invoke the generators from that root, run `terraform fmt -check`, then exercise both destroy paths.

## Invariants

1. Never exceed the configured 256 KiB serialized payload cap.
2. Keep the exact 900-second SQS/Scheduler routing boundary.
3. Validate a job class name against loaded Active Job descendants before constant resolution.
4. Return only failed SQS message IDs in `batchItemFailures`.
5. Scheduler targets SQS, never Lambda directly.
6. Recurring config accepts job classes and JSON-like args only—never eval or arbitrary commands.
7. Generator-owned host edits must be marked and reversible.
8. Preserve `retry_on` / `discard_on` by executing through Active Job.

## Deferred beyond 0.0.1

FIFO queues, numeric priority, distributed keyed concurrency, workflows/chains, dynamic schedule CRUD/UI, and automatic DLQ redrive are intentionally out of scope.
