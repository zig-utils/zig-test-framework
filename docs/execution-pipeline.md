# Unified execution pipeline

The framework has two plan producers and two executor implementations, but one
execution contract.

1. Programmatic registration or file discovery produces a `TestPlan`.
2. A registered-test or external-process executor consumes that plan.
3. The executor emits typed `LifecycleEvent` values through `EventStream`.
4. A selected reporter consumes the events and a shared `TestResults` summary.

`PlanItem.registered` retains the suite and test-case pointers needed for hooks
and in-process execution. `PlanItem.discovered` retains the discovered file used
by the external `zig test` executor. `PlanItem.identity()` gives extensions a
common stable identity without erasing executor-specific information.

## Shared lifecycle and results

Both executors emit run, suite, and test start/end events. Discovered files are
represented as one synthetic suite and test result per external process. This
means spec, dot, JSON, TAP, and JUnit reporters receive the same lifecycle and
summary model in either mode. `ReporterSet` is the single factory for built-in
reporters, including the configured JUnit output path.

`ExecutionPolicy` owns common filtering, bail, and timeout decisions:

- Registered tests match filters directly by test name. Discovery forwards the
  same filter to `zig test`, where Zig applies it to names inside each file.
- Bail stops scheduling after the shared result model records a failure. Work
  already started by a parallel batch cannot be cancelled. With retries, bail
  is evaluated only after the retry budget is exhausted.
- A global timeout compares elapsed execution time with the same policy in both
  executors on every attempt. It marks an over-budget attempt failed after
  control returns; it does not yet terminate an in-process function or external
  child process.
- Every logical result owns ordered attempt history. A failure followed by a
  successful retry is classified as `flaky`, distinct from an ordinary pass.
- Optional randomized execution uses one run seed across the selected plan.
  The seed is carried by reporters and `TestResults`; see
  [Randomized test order](randomized-order.md) for mode-specific guarantees.
- Summaries always come from `TestResults`, rather than executor-local counters.

## Extension points

New plan producers should append `PlanItem` values. New executors should emit
`LifecycleEvent` values and update `TestResults`. New reporters can continue to
implement `Reporter.VTable`; `EventStream` adapts the typed lifecycle to that
stable callback interface.

The lifecycle structures remain format-independent. The JSON reporter, live UI,
and test history adapt them to the public, versioned
[JSON event protocol](json-event-protocol.md), so integrations share one wire
model without coupling the execution API to JSON.

## Migration

Existing programmatic APIs remain source compatible:

- `TestRunner.init`, `runTests`, and `runTestsWithOptions` are unchanged.
- `RunnerOptions` gains optional reporter, timeout, retry, repeat, flaky-exit,
  shuffle, and seed
  fields with backward-compatible defaults.
- `runDiscoveredTests` and `LoaderOptions` remain available; optional reporter,
  JUnit path, timeout, retry, repeat, flaky-exit, shuffle, seed, and writer fields default to
  the previous spec behavior.

CLI hosts can inject a stdout writer with `reporter_writer`. Embedded callers
may leave it unset; reporter output then uses stderr so it cannot corrupt Zig's
stdout-based test protocol.

Code that implements a custom execution path can migrate incrementally by first
building a `TestPlan`, then routing callbacks through `EventStream`. Existing
custom reporters require no migration.
