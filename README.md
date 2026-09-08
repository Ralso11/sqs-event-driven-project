# SQS Event-Driven Project

**Live API:** https://fvr39tj3pd.execute-api.eu-central-1.amazonaws.com/task

📖 Want the full, beginner-friendly walkthrough of every step, command,
and decision made in this project? See
[PROJECT_GUIDE.md](./PROJECT_GUIDE.md).

## What is this project, in one sentence?

Two independent Lambda functions connected only by an SQS message
queue — a producer that submits tasks via an API, and a consumer that
automatically processes them, with neither function ever calling the
other directly.

## Why this project exists

The tenth project in this series, and the first to demonstrate
**event-driven, decoupled architecture**. Every earlier serverless
project used a request/response pattern: a client calls an API, waits,
and gets an answer immediately. Real production systems very often
need the opposite — accept work quickly, process it independently, and
survive one part being slow or temporarily down without losing
anything. This project demonstrates that pattern concretely.

## How it works

```
POST /task {"task": "..."}
      -> producer Lambda sends the task to an SQS queue
      -> producer responds immediately - it never waits for processing
      -> (separately, automatically) SQS triggers the consumer Lambda
      -> consumer processes the task independently
```

## Architecture

- **SQS queue** — holds messages until a consumer is ready for them.
  If the consumer were ever down, messages simply wait safely instead
  of being lost.
- **Producer Lambda** — triggered via API Gateway, only has permission
  to `sqs:SendMessage` — nothing else.
- **Consumer Lambda** — triggered automatically by an **event source
  mapping**, not by any API call. Only has permission to
  `ReceiveMessage`/`DeleteMessage`/`GetQueueAttributes` — the exact
  opposite permission set from the producer.
- **No direct connection between producer and consumer** — they only
  ever interact through the queue, proving genuine decoupling.

## Problems & fixes — quick reference

| Problem | Why it happened | How it was fixed |
|---|---|---|
| `.gitignore` and `backend.tf` created in the wrong folder (home directory instead of the project) | A `cd ..` command went one level further up than intended after an interrupted paste | Removed the misplaced files and recreated them in the correct location, verified with a full file listing before committing |

Otherwise, this project's infrastructure deployed cleanly on the first
real attempt.

## Cost notes

Very low cost to leave running: SQS, Lambda, and API Gateway are all
pay-per-use with generous free tiers, and there's no idle server
component anywhere in this architecture. No `destroy.yml` was needed
for this reason.

## Proof it actually works

Tested end-to-end, not just deployed and assumed:
1. `curl -X POST .../task` with a sample task — producer responded
   immediately with confirmation.
2. Checked the consumer's CloudWatch logs directly afterward — found
   `Processing task: send welcome email`, confirming the consumer woke
   up and processed the message automatically, with no direct call to
   it at any point.

## How to reproduce this project

1. Install Git and Terraform.
2. Create a GitHub repo, clone it locally.
3. Write two small Lambda functions: a producer that calls
   `sqs.send_message(...)`, and a consumer that reads `event["Records"]`
   (the shape AWS automatically hands SQS messages to a function in).
4. Write Terraform for: an SQS queue, two separate IAM roles with
   opposite, minimal permissions, both Lambda functions, an
   `aws_lambda_event_source_mapping` connecting the queue to the
   consumer, and an API Gateway connected only to the producer.
5. Create a dedicated IAM user with `AWSLambda_FullAccess`,
   `AmazonAPIGatewayAdministrator`, `AmazonSQSFullAccess`, plus a
   scoped custom policy for IAM role and state bucket access.
6. Store the keys as GitHub Secrets, set up a protected environment
   with required reviewers, build the pipeline manual-trigger-only.
7. Push, manually trigger `apply`, approve, and test by submitting a
   task via `curl` and checking the consumer's CloudWatch logs.

## What's next (possible future additions)

- [ ] Add a Dead Letter Queue (DLQ) for messages that repeatedly fail
      to process.
- [ ] Increase `batch_size` so the consumer processes multiple
      messages per invocation.
- [ ] Add a second consumer subscribed to the same queue, to
      demonstrate load distribution across multiple workers.
