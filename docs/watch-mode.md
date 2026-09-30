# Watch mode

Watch mode runs the full discovered suite once, then polls Zig source and test
files after the configured debounce interval. Start it with a test directory:

```bash
zig-test --test-dir tests --watch
```

Type `r` and press Enter at any time to request an explicit full-suite rerun.
Ctrl-C stops the watcher and any UI server cleanly.

## Affected-test selection

Each rerun prints both the selected test and the reason it was selected:

```text
Watch selection:
  - math.test.zig (imports changed source: src/math.zig)
```

The selection rules are conservative:

- A modified or newly added test file runs by itself. Multiple changed tests
  are batched by the debounce interval and run together.
- For a source change, the watcher follows relative `.zig` imports from every
  discovered test, including transitive imports, and runs tests whose import
  graph contains the changed file.
- Named module imports such as `@import("my_app")` cannot be resolved from
  source text alone. If any test has unresolved imports, or a changed source
  file maps to no test, the watcher safely runs the full suite.
- Deleting a test, or renaming one (observed as a delete plus an add), runs the
  full suite so reporters and the live UI receive the new test topology.
- Deleting or renaming an imported source file also falls back to the full
  suite when its dependency graph can no longer be resolved.

The watcher scans the project root for `.zig` changes while using `--test-dir`,
`--pattern`, and recursive-discovery settings to decide which files are tests.
It excludes Git metadata, Zig caches/output, `node_modules`, and `.codex`.

## Debouncing

`--watch-debounce <ms>` controls the polling and batching interval. The default
is 300 milliseconds. A test run is never interrupted: edits made while tests
are running are detected on the next poll and cause another affected run.
