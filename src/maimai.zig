const std = @import("std");
const log = std.log;
const json = std.json;
const mongodb = @import("mongodb.zig");
const ts = @import("timestamp");

pub const ArcadeInfo = struct {
    _id: mongodb.MongoObjectId,
    city_name: []const u8,
    arcade_name: []const u8,
    nickname: []const u8,
    console_name: []const u8,
    arcade_num: i32,
    update_id: []const u8,
    update_time: ts.Timestamp,
};

pub const CityInfo = struct {
    _id: mongodb.MongoObjectId,
    province_name: []const u8,
    city_name: []const u8,
};

pub const GroupInfo = struct {
    _id: mongodb.MongoObjectId,
    group_id: []const u8,
    city_name: []const u8,
};
