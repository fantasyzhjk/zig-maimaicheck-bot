const std = @import("std");
const json = std.json;

pub fn objectFromValues(allocator: std.mem.Allocator, pairs: []const struct { []const u8, json.Value }) !json.Value {
    var map = json.ObjectMap.init(allocator);

    for (pairs) |pair| {
        try map.put(pair[0], pair[1]);
    }

    return json.Value{ .object = map };
}

pub fn splitCommandStart(str: []const u8, command: []const u8) ?[]const u8 {
    // 检查字符串是否以 !、！或 / 开头
    if (str.len == 0) {
        return null;
    }

    var start_pos: usize = 0;

    // 检查各种命令前缀
    if (std.mem.startsWith(u8, str, "!")) {
        start_pos = 1;
    } else if (std.mem.startsWith(u8, str, "！")) {
        start_pos = 3; // UTF-8编码的！占3个字节
    } else if (std.mem.startsWith(u8, str, "/")) {
        start_pos = 1;
    } else {
        return null;
    }

    // 从命令开始位置切出剩余字符串
    const remaining = str[start_pos..];

    // 检查剩余部分是否以command开头
    if (std.mem.startsWith(u8, remaining, command)) {
        return remaining[command.len..];
    } else {
        return null;
    }
}

pub fn checkCommandStart(str: []const u8, command: []const u8) bool {
    // 检查字符串是否以 !、！或 / 开头
    if (str.len == 0) {
        return false;
    }

    var start_pos: usize = 0;

    // 检查各种命令前缀
    if (std.mem.startsWith(u8, str, "!")) {
        start_pos = 1;
    } else if (std.mem.startsWith(u8, str, "！")) {
        start_pos = 3; // UTF-8编码的！占3个字节
    } else if (std.mem.startsWith(u8, str, "/")) {
        start_pos = 1;
    } else {
        return false;
    }

    // 从命令开始位置切出剩余字符串
    const remaining = str[start_pos..];

    // 检查剩余部分是否以command开头
    if (std.mem.startsWith(u8, remaining, command)) {
        return true;
    } else {
        return false;
    }
}
