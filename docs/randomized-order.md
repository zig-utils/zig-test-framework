# Randomized test order

Randomized order is opt-in. Use `--shuffle` to generate a seed for the run:

```bash
zig-test --shuffle
```

The selected reporter prints the generated seed at run start. If a test fails,
the human-readable reporters print a replay command as well. Pass that seed to
reproduce the order; `--seed` implies `--shuffle`:

```bash
zig-test --seed 8675309
```

Keep every other order-affecting option the same when replaying a run, including
the test set, filter, shard, execution mode, and suite structure.

## Ordering guarantees

Without `--shuffle` or `--seed`, execution retains declaration or discovery
order.

In sequential programmatic execution, a seed deterministically orders root
suites, each suite's direct tests, and its nested suites. Lifecycle hooks keep
their normal scope: `beforeAll` and `afterAll` still wrap a suite, while
`beforeEach` and `afterEach` still wrap their selected test.

In parallel programmatic execution, the seed determines suite traversal, each
worker queue, and serialized reporter output. Workers claim tests from that
queue in order, but operating-system scheduling means wall-clock start and
completion timing can differ between runs. Reporter order remains reproducible.

In discovery mode, sharding selects files first and randomization orders the
files inside the selected shard. The seed does not change shard membership.
Retries and repetitions stay attached to their logical test or file and do not
trigger another shuffle.

## Metadata

The seed is stored as `random_seed` in JSON `run_start` and `run_end` events,
live UI events, and test-history files. JUnit output records it as a
`random_seed` property on each test suite. A non-randomized run reports a null
seed in JSON-compatible formats and omits the JUnit property.

Programmatic callers can use `RunnerOptions.shuffle` and `RunnerOptions.seed`,
or the matching `LoaderOptions` fields. JSON configuration accepts the same
values under `test`:

```json
{
  "test": {
    "shuffle": true,
    "seed": 8675309
  }
}
```
