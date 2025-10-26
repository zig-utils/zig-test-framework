# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned Features
- Snapshot testing
- Async/await test support
- Test timeout handling
- Code coverage reporting
- Watch mode for file changes
- Parameterized tests (it.each)
- Property-based testing integration

## [0.1.0] - 2025-01-XX

### Added
- Initial release of Zig Test Framework
- Core test runner with describe/it syntax
- Comprehensive assertion library with expect()
- Test hooks (beforeEach, afterEach, beforeAll, afterAll)
- Multiple reporters (Spec, Dot, JSON)
- Mock and Spy functionality for function testing
- Advanced matchers for floats, arrays, and structs
- CLI with filtering and reporter options
- Nested describe block support
- Test filtering with .skip() and .only()
- Colorized output support
- String assertions (toBe, toContain, toStartWith, toEndWith)
- Comparison assertions (toBeGreaterThan, toBeLessThan, etc.)
- Optional/nullable value assertions (toBeNull, toBeDefined)
- Negation support with .not() modifier
- Build system integration with build.zig
- Comprehensive documentation and examples

### Technical Details
- Minimum Zig version: 0.13.0
- No external dependencies
- Full allocator support for memory safety
- Type-safe assertion API
- Extensible reporter system

[Unreleased]: https://github.com/zig-utils/zig-test-framework/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/zig-utils/zig-test-framework/releases/tag/v0.1.0
