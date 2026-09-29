# Retries, repeats, and flaky tests

The runner records each execution of a logical test as an attempt. An attempt
contains its one-based number, repetition number, status, duration, and error
message. Registered tests and discovered test files use the same model.

## Command-line use

```bash
# One initial attempt plus as many as two retries after failure
zig-test --test-dir tests --retry 2

# Require every selected test to pass 100 times
zig-test --test-dir tests --filter parser --repeat 100

# Make a recovered failure fail the overall run in CI
zig-test --test-dir tests --retry 2 --fail-on-flaky
```

`--retries` is an alias for `--retry`. A retry count is the number of
*additional* attempts after a failure. `--repeat N` requires N successful
repetitions; each repetition receives its own retry budget. Attempt history is
ordered across all repetitions.

Discovery operates at test-file granularity because each file is an external
`zig test` process. Programmatic mode operates at individual-test granularity.

## Outcomes and exit status

- `passed`: every attempt passed without a retry.
- `flaky`: at least one attempt failed, but a retry recovered and all required
  repetitions eventually passed.
- `failed`: one repetition exhausted its retry budget.
- `skipped`: the test was not selected for execution.

Failed tests always make the process exit unsuccessfully. Flaky tests succeed
by default so retries can recover an intermittent failure. `--fail-on-flaky`
changes that policy and returns an unsuccessful exit status when any test is
flaky.

`--bail` is evaluated after retries, so one failed attempt does not stop the
run. The runner stops scheduling only after a logical test exhausts its retry
budget. The timeout is evaluated independently for every attempt; a timed-out
attempt may be retried.

When retries or repeats are configured for registered tests, execution is
sequential even if parallel mode was requested. This preserves deterministic
attempt ordering and hook behavior.

## Programmatic configuration

Set defaults for a registered-test run with `RunnerOptions`:

```zig
const options = ztf.RunnerOptions{
    .retries = 2,
    .repeat = 10,
    .fail_on_flaky = true,
};
const passed = try ztf.runTestsWithOptions(allocator, registry, options);
```

An individual registered test can override the run-level retry count:

```zig
try suite.addTest(
    ztf.TestCase.init("eventually consistent", testEventuallyConsistent)
        .withRetries(5),
);
```

`LoaderOptions` exposes the same `retries`, `repeat`, and `fail_on_flaky`
fields for callers that run discovered files directly. Strict JSON
configuration uses the corresponding fields in the `test` object:

```json
{
  "test": {
    "retries": 2,
    "repeat": 10,
    "fail_on_flaky": true
  }
}
```

## Reporter data

The spec and dot reporters show flaky results separately from passes. JSON test
objects include an `attempts` array with `number`, `repetition`, `status`, and
`durationNs` fields plus an optional `error`. The JSON summary includes a
`flaky` count. JUnit output includes the flaky count on `<testsuites>` and emits
ordered attempt data in each retried test case's `<system-out>` element.
