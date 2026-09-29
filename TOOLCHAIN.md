# Zig toolchain policy

The Zig Test Framework supports the exact Zig development build recorded in
`.zig-version`. Required CI jobs use that version so pull requests are tested
against a reproducible toolchain on `ubuntu-latest`, `macos-latest`, and
`windows-latest`. Windows support follows the Windows version represented by
GitHub's current `windows-latest` hosted runner; the exact Zig build remains the
version pinned in `.zig-version`.

Because the project follows Zig development builds, CI also runs a scheduled
compatibility check against the latest `0.17.0-dev` build. That check is
informational: an upstream API change should produce an intentional toolchain
update rather than unexpectedly blocking unrelated pull requests.

## Updating Zig

1. Replace the version in `.zig-version` with the full output of `zig version`.
2. Run `zig fmt --check .`.
3. Run `zig build`, `zig build test`, and `zig build examples`.
4. Run `zig build-lib -femit-docs src/lib.zig` and remove the generated local
   artifacts after verifying the command succeeds.
5. Summarize required compatibility changes in the pull request and, for a
   release, in the changelog.

The compatibility job can also be run manually from GitHub Actions before
updating the pinned version.
