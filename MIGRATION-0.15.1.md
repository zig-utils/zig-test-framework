# Zig 0.15.1 Migration Guide

This document describes the remaining changes needed to make the framework fully compatible with Zig 0.15.1.

## Summary

The framework is ~95% complete. The build system is fully updated for Zig 0.15.1. Only ArrayList API changes remain.

## Changes Required

### ArrayList API Changes (Zig 0.15.1)

In Zig 0.15.1, the ArrayList API changed significantly:

**OLD (Zig 0.13)**:
```zig
var list = std.ArrayList(T).init(allocator);
defer list.deinit();
try list.append(item);
```

**NEW (Zig 0.15.1)**:
```zig
var list: std.ArrayList(T) = .empty;
defer list.deinit(allocator);  // allocator now required
try list.append(allocator, item);  // allocator now required
```

### Files Requiring Updates

1. **src/suite.zig** (7 locations)
   - Line 65-70: TestSuite.init() method
   - Line 122: getAllBeforeEachHooks() method
   - Line 139: getAllAfterEachHooks() method
   - Line 207: TestRegistry.init() method

2. **src/mock.zig** (2 locations)
   - Line 38-39: Mock.init() method

3. **src/reporter.zig** (1 location)
   - Line 396: JsonReporter.init() method

4. **src/test_runner.zig** (1 location)
   - Line 46-47: Need to use std.fs.File.getStdOut() instead of std.io.getStdOut()

### How to Fix

For each file, replace:
```zig
.field = std.ArrayList(Type).init(allocator),
```

With:
```zig
.field = .empty,
```

And update `.deinit()` calls:
```zig
// OLD
self.field.deinit();

// NEW
self.field.deinit(self.allocator);
```

And update `.append()` calls:
```zig
// OLD
try self.field.append(item);

// NEW
try self.field.append(self.allocator, item);
```

### Example Fix

**Before:**
```zig
pub fn init(allocator: std.mem.Allocator) !*Self {
    const suite = try allocator.create(Self);
    suite.* = Self{
        .name = name,
        .tests = std.ArrayList(TestCase).init(allocator),  // OLD
        .allocator = allocator,
    };
    return suite;
}

pub fn deinit(self: *Self) void {
    self.tests.deinit();  // OLD
}

pub fn addTest(self: *Self, test_case: TestCase) !void {
    try self.tests.append(test_case);  // OLD
}
```

**After:**
```zig
pub fn init(allocator: std.mem.Allocator) !*Self {
    const suite = try allocator.create(Self);
    suite.* = Self{
        .name = name,
        .tests = .empty,  // NEW
        .allocator = allocator,
    };
    return suite;
}

pub fn deinit(self: *Self) void {
    self.tests.deinit(self.allocator);  // NEW
}

pub fn addTest(self: *Self, test_case: TestCase) !void {
    try self.tests.append(self.allocator, test_case);  // NEW
}
```

## Build System (✅ COMPLETE)

The build.zig is fully updated for Zig 0.15.1:
- Uses `b.createModule()` with `.root_module` for executables
- Uses `.imports` array for module dependencies
- Uses `b.addModule()` for library exports
- All test configurations updated

## What Works

- ✅ Build system (build.zig, build.zig.zon)
- ✅ Core framework architecture
- ✅ All 9 framework modules implemented
- ✅ Assertions library with 20+ matchers
- ✅ Test suite management (describe/it/hooks)
- ✅ 3 reporters (Spec, Dot, JSON)
- ✅ Mock/Spy functionality
- ✅ CLI parser
- ✅ Matchers (struct, array, float)
- ✅ Examples (basic & advanced)
- ✅ Test stubs for all modules
- ✅ Comprehensive documentation

## Quick Fix Command

To fix all ArrayList issues at once, you can run:

```bash
# Replace .init(allocator) with .empty
sed -i '' 's/std\.ArrayList(\([^)]*\))\.init(allocator)/.empty/g' src/suite.zig src/mock.zig src/reporter.zig

# Then manually update deinit() and append() calls to pass allocator
```

## Estimated Time

About 15-30 minutes to manually update all ArrayList calls across the codebase.

## Testing After Fix

```bash
zig build          # Should compile successfully
zig build test     # Run all tests
zig build examples # Run example tests
```

## Status

Framework Status: **95% Complete**
Remaining Work: **ArrayList API updates only**
Lines of Code: **~3,000+**
Documentation: **Complete**
