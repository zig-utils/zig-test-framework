# Contributing to Zig Test Framework

Thank you for your interest in contributing to the Zig Test Framework! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Commit Messages](#commit-messages)
- [Pull Request Process](#pull-request-process)
- [Release Process](#release-process)

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow
- Follow the Zig community guidelines

## Getting Started

### Prerequisites

- Zig 0.15.1 or later
- Git
- Basic understanding of testing frameworks (Jest, Vitest, or similar)

### Development Setup

1. **Fork the repository**
   ```bash
   # Clone your fork
   git clone https://github.com/YOUR_USERNAME/zig-test-framework.git
   cd zig-test-framework
   ```

2. **Add upstream remote**
   ```bash
   git remote add upstream https://github.com/ORIGINAL_OWNER/zig-test-framework.git
   ```

3. **Build the project**
   ```bash
   zig build
   ```

4. **Run tests**
   ```bash
   zig build test
   zig build examples
   ```

## Project Structure

```
zig-test-framework/
├── src/                    # Core framework source code
│   ├── assertions.zig      # Assertion library
│   ├── suite.zig           # Test suite management (describe/it)
│   ├── test_runner.zig     # Test execution engine
│   ├── reporter.zig        # Test reporters (Spec, Dot, JSON)
│   ├── matchers.zig        # Advanced matchers
│   ├── mock.zig            # Mocking and spying
│   ├── cli.zig             # Command-line interface
│   ├── lib.zig             # Public API exports
│   └── main.zig            # CLI entry point
├── tests/                  # Framework self-tests
├── examples/               # Usage examples
├── .github/                # CI/CD and templates
├── build.zig               # Build configuration
├── build.zig.zon           # Package manifest
└── README.md               # Documentation
```

## Development Workflow

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Write code following our coding standards
   - Add tests for new functionality
   - Update documentation as needed

3. **Test your changes**
   ```bash
   # Run all tests
   zig build test

   # Run examples
   zig build examples

   # Format code
   zig fmt src/ tests/ examples/
   ```

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add amazing feature"
   ```

5. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Create a Pull Request**
   - Go to GitHub and create a PR
   - Fill out the PR template
   - Link any related issues

## Coding Standards

### Zig Style Guide

Follow the official [Zig Style Guide](https://ziglang.org/documentation/master/#Style-Guide):

- **Indentation**: 4 spaces (no tabs)
- **Line length**: Aim for 100 characters, max 120
- **Naming**:
  - `camelCase` for functions and variables
  - `PascalCase` for types
  - `SCREAMING_SNAKE_CASE` for constants
- **Comments**: Use `//` for single-line, `///` for doc comments

### Framework Conventions

1. **Error Handling**
   - Use Zig's error unions (`!T`)
   - Provide clear error messages
   - Document error conditions

2. **Memory Management**
   - Always accept an allocator parameter
   - Clean up resources in `deinit()`
   - Test for memory leaks

3. **Public API**
   - Add doc comments (`///`) for all public functions
   - Export through `lib.zig`
   - Maintain backward compatibility

4. **Testing**
   - Write tests for all new features
   - Use inline tests in modules when appropriate
   - Add integration tests in `tests/` directory

### Example Code Style

```zig
/// Checks if a value is truthy
/// Returns an assertion that succeeds if the value is truthy
pub fn toBeTruthy(self: Self) !void {
    const is_truthy = switch (@typeInfo(T)) {
        .bool => self.actual,
        .optional => self.actual != null,
        .int => self.actual != 0,
        else => true,
    };

    if (self.negated) {
        if (is_truthy) {
            std.debug.print("\nExpected value to be falsy\n", .{});
            return AssertionError.AssertionFailed;
        }
    } else {
        if (!is_truthy) {
            std.debug.print("\nExpected value to be truthy\n", .{});
            std.debug.print("  Received: {any}\n", .{self.actual});
            return AssertionError.AssertionFailed;
        }
    }
}
```

## Testing

### Running Tests

```bash
# All framework tests
zig build test

# Run examples
zig build examples

# Specific test file (if needed)
zig test src/assertions.zig
```

### Writing Tests

1. **Unit Tests** - Test individual functions in isolation
   ```zig
   test "toBe should compare primitive values" {
       const allocator = std.testing.allocator;
       try expect(allocator, 5).toBe(5);
       try expect(allocator, true).toBe(true);
   }
   ```

2. **Integration Tests** - Test multiple components together
   ```zig
   test "runner executes suite with hooks" {
       // Test setup, execution, teardown flow
   }
   ```

3. **Example Tests** - Demonstrate usage
   - Add to `examples/` directory
   - Show real-world scenarios

### Test Coverage

- Aim for >80% code coverage
- Test both success and failure cases
- Test edge cases and error conditions
- Verify memory cleanup

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- **feat**: New feature
- **fix**: Bug fix
- **docs**: Documentation changes
- **style**: Code style changes (formatting, etc.)
- **refactor**: Code refactoring
- **perf**: Performance improvements
- **test**: Adding or updating tests
- **chore**: Maintenance tasks

### Examples

```bash
# Feature
feat(assertions): add toThrow error assertion

# Bug fix
fix(reporter): correct color output on Windows

# Documentation
docs(readme): update installation instructions

# Multiple changes
feat(matchers): add toBeCloseTo for floating-point comparison

Implements toBeCloseTo matcher for comparing floating-point
numbers with configurable precision.

Closes #123
```

## Pull Request Process

### Before Submitting

- [ ] Tests pass (`zig build test`)
- [ ] Examples work (`zig build examples`)
- [ ] Code is formatted (`zig fmt`)
- [ ] Documentation is updated
- [ ] CHANGELOG.md is updated (for significant changes)
- [ ] No memory leaks
- [ ] Commits follow convention

### PR Template

Fill out the PR template completely:
- Description of changes
- Related issues
- Testing performed
- Breaking changes (if any)

### Review Process

1. Maintainer reviews your PR
2. Address any feedback
3. Once approved, PR will be merged
4. Delete your feature branch

### Merging

- PRs require at least one approval
- All tests must pass
- No merge conflicts
- Follow-up issues created for future work

## Release Process

### Version Numbering

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

### Release Steps

1. Update version in `build.zig.zon`
2. Update CHANGELOG.md
3. Create git tag: `git tag -a v1.2.3 -m "Release 1.2.3"`
4. Push tag: `git push origin v1.2.3`
5. GitHub Actions will create the release

## Getting Help

- **Issues**: Search existing issues or create a new one
- **Discussions**: Use GitHub Discussions for questions
- **Zig Community**: Join the Zig Discord or Ziggit forums

## Recognition

Contributors will be recognized in:
- CHANGELOG.md for their contributions
- GitHub contributors page
- Release notes

Thank you for contributing to Zig Test Framework! 🎉
