const utils = @import("utils");
const std = @import("std");
const json = std.json;

pub const MessageChain = struct {
    const Self = @This();

    inner_chain: std.ArrayList(MessageSegment),
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        const arena = std.heap.ArenaAllocator.init(allocator);
        return Self{ .inner_chain = std.ArrayList(MessageSegment).init(allocator), .arena = arena };
    }

    pub fn append(self: *Self, msg: MessageSegment) !void {
        try self.inner_chain.append(msg);
    }

    pub fn chain(self: *Self, other: *const Self) !void {
        try self.inner_chain.appendSlice(other.inner_chain.items);
    }

    pub fn text(self: *Self, t: []const u8) *Self {
        self.inner_chain.append(MessageSegment{ .text = MessageSegment.TextMessage{
            .text = t,
        } }) catch unreachable;
        return self;
    }

    pub fn at(self: *Self, qq: i64) *Self {
        self.inner_chain.append(MessageSegment{ .at = MessageSegment.AtMessage{
            .qq = std.fmt.allocPrint(self.arena.allocator(), "{}", .{qq}) catch unreachable,
            .name = null,
        } }) catch unreachable;
        return self;
    }

    pub fn at_all(self: *Self) *Self {
        self.inner_chain.append(MessageSegment{ .at = MessageSegment.AtMessage{
            .qq = "all",
        } }) catch unreachable;
        return self;
    }

    pub fn toJson(self: *const Self, allocator: std.mem.Allocator) !json.Value {
        var arr = json.Array.init(allocator);

        for (self.inner_chain.items) |m| {
            try arr.append(try m.toJson(allocator));
        }

        return json.Value{ .array = arr };
    }

    pub fn clear(self: *Self) void {
        self.inner_chain.clearAndFree();
    }

    pub fn deinit(self: Self) void {
        self.inner_chain.deinit();
        self.arena.deinit();
    }
};

pub const MessageSegment = union(enum) {
    unknown: UnknownMessage,
    text: TextMessage,
    at: AtMessage,
    image: ImageMessage,

    const UnknownMessage = struct { type: []const u8, value: json.Value };
    const TextMessage = struct { text: []const u8 };
    const AtMessage = struct { qq: []const u8, name: ?[]const u8 };
    const ImageMessage = struct {
        file: []const u8,
        filename: ?[]const u8,
        url: ?[]const u8,
        summary: ?[]const u8,
        sub_type: i64 = 0,
    };

    pub fn fromJson(j: json.Value) ?MessageSegment {
        const root = j.object;
        const t = root.get("type").?.string;
        const data = root.get("data").?;
        if (std.mem.eql(u8, t, "text")) {
            return MessageSegment{ .text = TextMessage{ .text = data.object.get("text").?.string } };
        } else if (std.mem.eql(u8, t, "at")) {
            return MessageSegment{ .at = AtMessage{
                .qq = data.object.get("qq").?.string,
                .name = if (data.object.get("name")) |v| v.string else null,
            } };
        } else if (std.mem.eql(u8, t, "image")) {
            return MessageSegment{
                .image = ImageMessage{
                    .file = data.object.get("file").?.string,
                    .filename = data.object.get("filename").?.string,
                    .url = data.object.get("url").?.string,
                    .summary = data.object.get("summary").?.string,
                    .sub_type = data.object.get("subType").?.integer,
                },
            };
        } else {
            return MessageSegment{ .unknown = UnknownMessage{ .type = t, .value = data } };
        }
    }

    pub fn toJson(self: @This(), allocator: std.mem.Allocator) !json.Value {
        return switch (self) {
            .text => |val| try utils.objectFromValues(allocator, &.{
                .{ "type", json.Value{ .string = "text" } },
                .{ "data", try utils.objectFromValues(allocator, &.{
                    .{ "text", json.Value{ .string = val.text } },
                }) },
            }),
            .at => |val| try utils.objectFromValues(allocator, &.{
                .{ "type", json.Value{ .string = "at" } },
                .{ "data", try utils.objectFromValues(allocator, &.{
                    .{ "qq", json.Value{ .string = val.qq } },
                }) },
            }),
            .image => |val| try utils.objectFromValues(allocator, &.{
                .{ "type", json.Value{ .string = "image" } },
                .{ "data", try utils.objectFromValues(allocator, &.{
                    .{ "file", json.Value{ .string = val.file } },
                }) },
            }),
            .unknown => |val| try utils.objectFromValues(allocator, &.{
                .{ "type", json.Value{ .string = val.type } },
                .{ "data", val.value },
            }),
        };
    }
};

pub const Sender = struct {
    user_id: i64,
    nickname: []const u8,
    sex: []const u8,
    age: ?i32,

    pub fn fromJson(j: json.Value) ?Sender {
        const root = j.object;
        return Sender{
            .user_id = root.get("user_id").?.integer,
            .nickname = root.get("nickname").?.string,
            .sex = root.get("sex").?.string,
            .age = if (root.get("age")) |v| @intCast(v.integer) else null,
        };
    }
};

pub const MessageType = enum {
    private,
    group,

    pub fn fromJson(j: json.Value) ?MessageType {
        const root = j.object;
        const t = root.get("message_type").?.string;
        if (std.mem.eql(u8, t, "private")) {
            return MessageType.private;
        } else if (std.mem.eql(u8, t, "group")) {
            return MessageType.group;
        } else {
            return null;
        }
    }
};

const MessageSubType = enum {
    friend,
    group,
    other,

    pub fn fromJson(j: json.Value) ?MessageSubType {
        const root = j.object;
        const t = root.get("sub_type").?.string;
        if (std.mem.eql(u8, t, "friend")) {
            return MessageSubType.friend;
        } else if (std.mem.eql(u8, t, "group")) {
            return MessageSubType.group;
        } else if (std.mem.eql(u8, t, "other")) {
            return MessageSubType.other;
        } else {
            return null;
        }
    }
};

pub const MessageEvent = struct {
    message_type: MessageType,
    sub_type: ?MessageSubType,
    message_id: i32,
    group_id: ?i64,
    user_id: i64,
    message: MessageChain,
    raw_message: []const u8,
    font: i32,
    sender: Sender,

    pub fn fromJson(allocator: std.mem.Allocator, j: json.Value) ?MessageEvent {
        var message_chain = MessageChain.init(allocator);

        const root = j.object;
        const messages_j = root.get("message").?.array;

        for (messages_j.items) |v| {
            if (MessageSegment.fromJson(v)) |m| {
                message_chain.append(m) catch return null;
            }
        }

        return MessageEvent{
            .message_type = MessageType.fromJson(j).?,
            .sub_type = MessageSubType.fromJson(j),
            .message_id = @intCast(root.get("message_id").?.integer),
            .group_id = if (root.get("group_id")) |v| v.integer else null,
            .user_id = root.get("user_id").?.integer,
            .message = message_chain,
            .raw_message = root.get("raw_message").?.string,
            .font = @intCast(root.get("font").?.integer),
            .sender = Sender.fromJson(root.get("sender").?).?,
        };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        _ = allocator;
        self.message.deinit();
    }
};
