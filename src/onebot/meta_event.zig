const std = @import("std");
const json = std.json;

pub const MetaEvent = union(enum) {
    lifecycle: LifeCycleMetaEvent,
    heartbeat: HeartBeatMetaEvent,

    const LifeCycleMetaEvent = enum {
        enable,
        disable,
        connect,

        pub fn fromJson(j: json.Value) ?LifeCycleMetaEvent {
            const root = j.object;
            const sub_type = root.get("sub_type").?.string;
            if (std.mem.eql(u8, sub_type, "enable")) {
                return LifeCycleMetaEvent.enable;
            } else if (std.mem.eql(u8, sub_type, "disable")) {
                return LifeCycleMetaEvent.disable;
            } else if (std.mem.eql(u8, sub_type, "connect")) {
                return LifeCycleMetaEvent.connect;
            } else {
                return null;
            }
        }
    };

    const HeartBeatMetaEvent = struct {
        status: json.Value,
        interval: i64,

        pub fn fromJson(j: json.Value) ?HeartBeatMetaEvent {
            const root = j.object;
            return HeartBeatMetaEvent{ .status = root.get("status").?, .interval = root.get("interval").?.integer };
        }
    };

    pub fn fromJson(j: json.Value) ?MetaEvent {
        const root = j.object;
        const meta_event_type = root.get("meta_event_type").?.string;

        if (std.mem.eql(u8, meta_event_type, "lifecycle")) {
            return MetaEvent{ .lifecycle = LifeCycleMetaEvent.fromJson(j).? };
        } else if (std.mem.eql(u8, meta_event_type, "heartbeat")) {
            return MetaEvent{ .heartbeat = HeartBeatMetaEvent.fromJson(j).? };
        } else {
            return null;
        }
    }
};
