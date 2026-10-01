# Changelog

## 0.0.1 - 2026-09-30

### Added

- Active Job queue adapter backed by SQS for immediate and <=15-minute delayed jobs.
- One-time EventBridge Scheduler delivery for longer `wait` / `wait_until` jobs.
- Lambda worker with loaded-class allowlisting and per-record `batchItemFailures`.
- Belt Lambda Loadout logging and `JobEnqueued`, `JobSucceeded`, and `JobFailed` metrics.
- `belt g jobs` installer for SQS, execution and Scheduler DLQs, IAM, alarms, Lambda config, and reversible host wiring.
- `belt g job NAME` generator with queue, friendly/native schedule, and timezone options.
- Validated `config/recurring.yml` definitions compiled to EventBridge Scheduler resources.
- 256 KiB payload limit and documented at-least-once/idempotency contract.
