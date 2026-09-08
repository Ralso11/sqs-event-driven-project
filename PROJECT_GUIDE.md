# The Complete Guide to This Project
### (Written so anyone, even with zero background, can understand it)

This is the tenth project in a portfolio series. It assumes the basics
from earlier guides (Git, GitHub, Terraform, CI/CD, Lambda, API
Gateway) are already familiar. This one is entirely about
**event-driven, decoupled architecture** — a genuinely different way of
connecting two pieces of software than anything used so far.

---

## Part 1 — Request/response vs event-driven: the core difference

Every earlier serverless project in this portfolio followed the same
shape: a client sends a request, a Lambda function runs immediately,
and the client waits for a response. This is called **request/response**
— simple, predictable, but it has a real weakness: the client is
*stuck waiting* the whole time, and if the function is slow or briefly
unavailable, the request can fail entirely.

**Event-driven architecture works differently.** Instead of calling the
next piece of work directly, a system drops a message describing that
work into a **queue**, and moves on immediately. Something else, on its
own schedule, picks that message up whenever it's ready. This project
builds exactly that: a "producer" that queues work, and a "consumer"
that processes it — with the two **never directly connected**.

## Part 2 — Why this matters in practice

Imagine an e-commerce checkout: when someone places an order, you might
need to charge their card, send a confirmation email, update inventory,
and notify a warehouse — four separate things. If all four had to
happen before the customer's browser gets a response, a slow email
service would make the whole checkout feel broken. With a queue
instead: the order gets confirmed instantly, and each of those four
tasks happens independently, at its own pace, without blocking anything
else — and if the email service is briefly down, the message just waits
in the queue instead of the task being lost entirely.

## Part 3 — The producer: fire, and don't wait

```python
def handler(event, context):
    body = json.loads(event.get("body") or "{}")
    task = body.get("task", "no task specified")

    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps({"task": task})
    )

    return {"statusCode": 200, ...}
```

The function's job ends the instant `send_message` succeeds. It has no
idea when — or even whether — the task actually gets processed
afterward; that's not its concern. This is the essence of decoupling:
the producer's responsibility is narrow and complete on its own.

## Part 4 — The consumer: triggered, not called

```python
def handler(event, context):
    for record in event["Records"]:
        body = json.loads(record["body"])
        task = body.get("task", "unknown task")
        print(f"Processing task: {task}")
    return {"statusCode": 200}
```

Notice what's **missing** compared to every other Lambda function built
so far: no API Gateway, no direct trigger from user action at all.
`event["Records"]` is a shape AWS constructs automatically and hands to
this function whenever SQS messages are ready. Nothing in this code
ever asks "are there any messages?" — AWS handles that watching
entirely; the function is simply invoked when there's something to do.

## Part 5 — The event source mapping: the actual wiring

```hcl
resource "aws_lambda_event_source_mapping" "sqs_to_consumer" {
  event_source_arn = aws_sqs_queue.tasks.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 1
}
```

This single resource is what makes the automatic triggering happen —
without it, messages would sit in the queue forever, and the consumer
function would never run at all, no matter how many messages arrived.
`batch_size = 1` means each invocation handles exactly one message;
setting it higher would let one invocation process several messages at
once (a real tradeoff between processing efficiency and per-message
isolation, which is why it's a simple, changeable number rather than
hardcoded).

## Part 6 — Opposite permissions for opposite jobs

```hcl
# Producer can only send
resource "aws_iam_role_policy" "producer_sqs_send" {
  policy = jsonencode({
    Statement = [{ Action = "sqs:SendMessage", Resource = ... }]
  })
}

# Consumer can only receive/delete
resource "aws_iam_role_policy" "consumer_sqs_receive" {
  policy = jsonencode({
    Statement = [{
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource = ...
    }]
  })
}
```

This is least-privilege applied precisely to each function's actual
job: the producer genuinely never needs to read from the queue, and the
consumer genuinely never needs to send to it. Giving either function
the other's permission would work technically, but it would be
needlessly broad — exactly the kind of over-permissioning that
"principle of least privilege" exists to prevent.

## Part 7 — Proving the decoupling is real, not just architectural claim

Testing this project required two completely separate checks, because
the two functions genuinely don't talk to each other:
1. `curl -X POST .../task` — confirms the *producer* half works,
   returning an immediate success response.
2. Checking the **consumer's own CloudWatch logs**, separately —
   confirms the *consumer* half worked, entirely independently, with
   no shared response or direct connection to check in one place.

Finding `Processing task: send welcome email` in those logs, with no
direct call ever made to the consumer function, is the actual proof
this pattern works — a fundamentally different kind of verification
than checking an API response, because there's no single response that
covers the whole flow.

## Part 8 — A small navigation mistake, and the recovery habit worth repeating

While setting up the project's supporting files, a `cd ..` command
(following an interrupted, earlier attempt) moved one directory level
further up than intended — landing in the home folder instead of the
project root. `.gitignore` and `backend.tf` were created there by
mistake, invisible to the actual project.

**The fix wasn't guesswork** — running `find . -type f` from the
project root listed every actual file in the project, immediately
making clear which files existed and where, before anything was
committed. This is the same "verify precisely what's wrong before
assuming or reacting" habit that resolved a lost-folder scare in an
earlier project — worth treating as a standing practice whenever a
terminal session feels like it's drifted from where you expect it to
be.

## Part 9 — Command/concept glossary (new items vs previous projects)

| Term | Plain-language meaning |
|---|---|
| Event-driven architecture | A system where components react to events/messages rather than calling each other directly |
| Producer | The part of a system that creates work and hands it off, without waiting for it to finish |
| Consumer | The part of a system that picks up and processes work independently |
| SQS (Simple Queue Service) | AWS's managed message queue — holds messages until something is ready to process them |
| Event source mapping | The AWS resource that automatically triggers a Lambda function when new items appear in a source (like an SQS queue) |
| Decoupling | Designing two components so neither depends on directly calling or knowing about the other |

## Part 10 — How to explain this project in an interview

> "I built an event-driven system with two Lambda functions connected
> only through an SQS queue — a producer that accepts tasks via an API
> and queues them, and a consumer that's automatically triggered
> whenever a message arrives, with no direct connection between the
> two. I scoped each function's IAM permissions to exactly its own job
> — the producer can only send messages, the consumer can only receive
> and delete them. Testing this required checking two completely
> separate things — the producer's API response, and the consumer's
> CloudWatch logs — since there's no single response that proves the
> whole flow worked, which is a real difference from the request/response
> APIs I'd built before this."

That story demonstrates understanding of a genuinely different, widely
used architectural pattern — and shows you know when and why you'd
reach for it over a simple direct API call.

---

*This document, together with the repo's README.md, covers everything
needed to fully understand, explain, and rebuild this project.*
