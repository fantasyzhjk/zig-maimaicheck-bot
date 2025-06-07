const std = @import("std");
const uuid = @import("uuid");
const json = std.json;
const ts = @import("timestamp");
const meta_event = @import("meta_event.zig");
pub const message = @import("message.zig");
pub const action = @import("action.zig");

pub const MetaEvent = meta_event.MetaEvent;
pub const MessageEvent = message.MessageEvent;
pub const MessageChain = message.MessageChain;

pub const Event = struct {
    time: ts.Timestamp,
    self_id: i64,
    post_data: EventData,

    pub fn fromJson(allocator: std.mem.Allocator, j: json.Value) ?Event {
        const root = j.object;
        const time = ts.TimestampParser.parseFromJson(root.get("time") orelse return null) catch return null;
        const self_id = root.get("self_id").?.integer;
        const post_data = EventData.fromJson(allocator, j).?;

        return Event{ .time = time, .self_id = self_id, .post_data = post_data };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        self.post_data.deinit(allocator);
    }
};

pub const EventData = union(enum) {
    meta: MetaEvent,
    message: MessageEvent,

    pub fn fromJson(allocator: std.mem.Allocator, j: json.Value) ?EventData {
        const root = j.object;

        const event_type = root.get("post_type").?.string;
        if (std.mem.eql(u8, event_type, "meta_event")) {
            return EventData{ .meta = meta_event.MetaEvent.fromJson(j).? };
        } else if (std.mem.eql(u8, event_type, "message")) {
            return EventData{ .message = message.MessageEvent.fromJson(allocator, j).? };
        } else {
            return null;
        }
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        switch (self) {
            .message => self.message.deinit(allocator),
            else => {},
        }
    }
};
