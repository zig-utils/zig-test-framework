# JSON event protocol

The framework exposes one versioned event model for the JSON reporter, live UI,
and saved test history. Protocol version 1 uses this envelope for every event:

```json
{
  "protocol_version": 1,
  "type": "test_end",
  "data": {
    "name": "adds two numbers",
    "suite": "math",
    "status": "passed",
    "duration_ns": 42000,
    "error_message": null
  }
}
```

All strings are encoded by Zig's standard JSON serializer. Consumers should
decode JSON rather than depending on whitespace or object-field order.

## Transports

- The JSON reporter writes an ordered JSON array of event envelopes.
- The live UI sends each envelope as a server-sent event. The SSE event name is
  the same as the envelope's `type`.
- Test-history files contain an ordered JSON array using the same envelopes.

Events preserve execution order. A run begins with `run_start` and finishes
with `run_end`; suite and test start/end events are nested in between. Retry
events are emitted in attempt order immediately before their `test_end`.

## Version 1 events

| Type | Data fields |
| --- | --- |
| `run_start` | `total`, optional `random_seed` |
| `run_end` | `total`, `passed`, `flaky`, `failed`, `skipped`, `duration_ns`, optional `random_seed` |
| `suite_start`, `suite_end` | `name` |
| `test_start` | `name`, optional `suite` |
| `test_end` | `name`, optional `suite`, `status`, `duration_ns`, optional `error_message` |
| `hook` | `kind`, optional `suite`, optional `test_name`, `status`, `duration_ns`, optional `error_message` |
| `output` | `stream`, `text`, optional `test_name` |
| `retry` | `name`, `attempt`, `repetition`, `status`, `duration_ns`, optional `error_message` |
| `coverage` | optional `line_percent`, `function_percent`, `branch_percent`, `report_path` |

Statuses are `pending`, `running`, `passed`, `flaky`, `failed`, or `skipped`.
Hook kinds are `before_all`, `before_each`, `after_each`, or `after_all`.
Output streams are `stdout` or `stderr`.

Optional fields are serialized as `null` when no value is available. Durations
are unsigned integer nanoseconds. Percentages are numbers from 0 through 100.
When randomized ordering is enabled, both run events carry the reproducible
unsigned integer seed.

## Compatibility policy

`protocol_version` is the major wire-format version. Version 1 may gain new
event types, enum values, and optional data fields without changing the version.
Consumers must ignore event types and fields they do not understand. Existing
fields will not change meaning or type within a major version.

Removing or renaming an event or field, changing a field's type or semantics,
or changing the envelope shape requires a new major version. Producers emit one
major version per stream. Consumers should reject an unsupported major version
with a clear error instead of interpreting it as an older version.

## Zig API

`event_protocol.Event` is the tagged union for all event types, and
`event_protocol.encodeAlloc` returns a standards-compliant encoded envelope.
The root module also exports these as `ProtocolEvent` and `protocol_version`.
