const std = @import("std");

test "selected test passes" {
    try std.testing.expect(true);
}

test "unselected test fails" {
    return error.ShouldHaveBeenFiltered;
}
