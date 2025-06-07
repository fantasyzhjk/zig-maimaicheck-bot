const std = @import("std");
const json = std.json;

pub fn objectFromValues(allocator: std.mem.Allocator, pairs: []const struct { []const u8, json.Value }) !json.Value {
    var map = json.ObjectMap.init(allocator);

    for (pairs) |pair| {
        try map.put(pair[0], pair[1]);
    }

    return json.Value{ .object = map };
}
