const uuid = @import("uuid");
const utils = @import("utils");
const message = @import("message.zig");
const std = @import("std");
const json = std.json;

pub const DynamicApiRequest = struct {
    action: []const u8,
    params: json.Value,
    echo: []const u8,

    pub fn toJson(self: @This(), allocator: std.mem.Allocator) !json.Value {
        return try utils.objectFromValues(allocator, &.{
            .{ "action", json.Value{ .string = self.action } },
            .{ "params", self.params },
            .{ "echo", json.Value{ .string = self.echo } },
        });
    }
};

pub fn new(comptime H: type, h: H, allocator: std.mem.Allocator) !DynamicApiRequest {
    const u = try uuid.generateSecureUUID();
    return DynamicApiRequest{
        .action = H.action,
        .params = try h.toJson(allocator),
        .echo = try u.toCompactString(allocator),
    };
}

pub const PrivateMessageReq = struct {
    pub const action = "send_private_msg";

    user_id: i64,
    message: *const message.MessageChain,

    pub fn toJson(self: @This(), allocator: std.mem.Allocator) !json.Value {
        return try utils.objectFromValues(allocator, &.{
            .{ "user_id", json.Value{ .integer = self.user_id } },
            .{ "message", try self.message.toJson(allocator) },
            .{ "auto_escape", json.Value{ .bool = false } },
        });
    }
};

pub const GroupMessageReq = struct {
    pub const action = "send_group_msg";

    group_id: i64,
    message: *const message.MessageChain,

    pub fn toJson(self: @This(), allocator: std.mem.Allocator) !json.Value {
        return try utils.objectFromValues(allocator, &.{
            .{ "group_id", json.Value{ .integer = self.group_id } },
            .{ "message", try self.message.toJson(allocator) },
            .{ "auto_escape", json.Value{ .bool = false } },
        });
    }
};
