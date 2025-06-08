const uuid = @import("uuid");
const utils = @import("utils");
const message = @import("message.zig");
const std = @import("std");
const json = std.json;
const String = @import("string").String;

pub const DynamicApiReturn = struct {
    status: []const u8,
    retcode: i64,
    data: json.Value,
    echo: []const u8,

    pub fn fromJson(value: json.Value) ?DynamicApiReturn {
        const root = value.object;
        return DynamicApiReturn{
            .retcode = if (root.get("retcode")) |v| v.integer else return null,
            .echo = if (root.get("echo")) |v| v.string else return null,
            .data = if (root.get("data")) |v| v else return null,
            .status = if (root.get("status")) |v| v.string else return null,
        };
    }
};

pub const DynamicApiRequest = struct {
    action: []const u8,
    params: ?json.Value,
    echo: []const u8,

    pub fn toJson(self: *const @This(), allocator: std.mem.Allocator) !json.Value {
        if (self.params) |params| {
            return try utils.objectFromValues(allocator, &.{
                .{ "action", json.Value{ .string = self.action } },
                .{ "params", params },
                .{ "echo", json.Value{ .string = self.echo } },
            });
        } else {
            return try utils.objectFromValues(allocator, &.{
                .{ "action", json.Value{ .string = self.action } },
                .{ "echo", json.Value{ .string = self.echo } },
            });
        }
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

// TODD: get_group_member_info

pub const GetGroupInfo = struct {
    pub const action = "get_group_info";
    group_id: i64,
    no_cache: bool = false,

    pub fn toJson(self: *const @This(), allocator: std.mem.Allocator) !?json.Value {
        return try utils.objectFromValues(allocator, &.{
            .{ "group_id", json.Value{ .integer = self.group_id } },
            .{ "no_cache", json.Value{ .bool = self.no_cache } },
        });
    }

    pub const Ret = struct {
        group_id: i64,
        group_name: String,
        member_count: i64,
        max_member_count: i64,

        pub fn fromJson(value: json.Value, allocator: std.mem.Allocator) !Ret {
            const root = value.object;
            return Ret{
                .group_id = root.get("group_id").?.integer,
                .group_name = try String.init_with_contents(allocator, root.get("group_name").?.string),
                .member_count = root.get("member_count").?.integer,
                .max_member_count = root.get("max_member_count").?.integer,
            };
        }

        pub fn deinit(self: Ret) void {
            var s = self.group_name;
            s.deinit();
        }
    };
};

pub const GetStatus = struct {
    pub const action = "get_status";

    pub fn toJson(self: *const @This(), allocator: std.mem.Allocator) !?json.Value {
        _ = self;
        _ = allocator;
        return null;
    }

    pub const Ret = struct {
        online: bool,
        good: bool,
        memory: i64,

        pub fn fromJson(value: json.Value, allocator: std.mem.Allocator) !Ret {
            _ = allocator;
            const root = value.object;
            return Ret{
                .online = root.get("online").?.bool,
                .good = root.get("good").?.bool,
                .memory = root.get("memory").?.integer,
            };
        }
    };
};

pub const PrivateMessageReq = struct {
    pub const action = "send_private_msg";

    user_id: i64,
    message: *const message.MessageChain,

    pub fn toJson(self: *const @This(), allocator: std.mem.Allocator) !?json.Value {
        return try utils.objectFromValues(allocator, &.{
            .{ "user_id", json.Value{ .integer = self.user_id } },
            .{ "message", try self.message.toJson(allocator) },
            .{ "auto_escape", json.Value{ .bool = false } },
        });
    }

    pub const Ret = struct {
        message_id: i64,

        pub fn fromJson(value: json.Value, allocator: std.mem.Allocator) !Ret {
            _ = allocator;
            const root = value.object;
            if (root.get("message_id")) |message_id| {
                return Ret{ .message_id = message_id.integer };
            } else {
                return error.InvalidReturn;
            }
        }
    };
};

pub const GroupMessageReq = struct {
    pub const action = "send_group_msg";

    group_id: i64,
    message: *const message.MessageChain,

    pub fn toJson(self: *const @This(), allocator: std.mem.Allocator) !?json.Value {
        return try utils.objectFromValues(allocator, &.{
            .{ "group_id", json.Value{ .integer = self.group_id } },
            .{ "message", try self.message.toJson(allocator) },
            .{ "auto_escape", json.Value{ .bool = false } },
        });
    }

    pub const Ret = struct {
        message_id: i64,

        pub fn fromJson(value: json.Value, allocator: std.mem.Allocator) !Ret {
            _ = allocator;
            const root = value.object;
            if (root.get("message_id")) |message_id| {
                return Ret{ .message_id = message_id.integer };
            } else {
                return error.InvalidReturn;
            }
        }
    };
};
