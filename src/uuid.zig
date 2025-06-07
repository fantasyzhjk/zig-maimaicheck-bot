const std = @import("std");
const crypto = std.crypto;
const print = std.debug.print;

var global_prng: ?std.rand.DefaultPrng = null;

pub fn getGlobalRandom() std.rand.Random {
    if (global_prng == null) {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch {
            // 如果获取系统随机数失败，使用时间戳作为种子
            seed = @intCast(std.time.timestamp());
        };
        global_prng = std.rand.DefaultPrng.init(seed);
    }
    return global_prng.?.random();
}

// UUID 结构体定义
const UUID = struct {
    bytes: [16]u8,

    const Self = @This();

    // 从字节数组创建 UUID
    pub fn fromBytes(bytes: [16]u8) Self {
        return Self{ .bytes = bytes };
    }

    // 转换为字符串格式 (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
    pub fn toString(self: Self, allocator: std.mem.Allocator) ![]u8 {
        const result = try allocator.alloc(u8, 36);
        _ = std.fmt.bufPrint(result, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            self.bytes[0],  self.bytes[1],  self.bytes[2],  self.bytes[3],
            self.bytes[4],  self.bytes[5],  self.bytes[6],  self.bytes[7],
            self.bytes[8],  self.bytes[9],  self.bytes[10], self.bytes[11],
            self.bytes[12], self.bytes[13], self.bytes[14], self.bytes[15],
        }) catch unreachable;
        return result;
    }

    // 转换为紧凑字符串格式 (不带连字符)
    pub fn toCompactString(self: Self, allocator: std.mem.Allocator) ![]u8 {
        const result = try allocator.alloc(u8, 32);
        _ = std.fmt.bufPrint(result, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            self.bytes[0],  self.bytes[1],  self.bytes[2],  self.bytes[3],
            self.bytes[4],  self.bytes[5],  self.bytes[6],  self.bytes[7],
            self.bytes[8],  self.bytes[9],  self.bytes[10], self.bytes[11],
            self.bytes[12], self.bytes[13], self.bytes[14], self.bytes[15],
        }) catch unreachable;
        return result;
    }

    // 从字符串解析 UUID
    pub fn fromString(str: []const u8) !Self {
        if (str.len != 36) return error.InvalidUUIDLength;

        var bytes: [16]u8 = undefined;
        var byte_idx: usize = 0;
        var i: usize = 0;

        while (i < str.len and byte_idx < 16) {
            if (str[i] == '-') {
                i += 1;
                continue;
            }

            if (i + 1 >= str.len) return error.InvalidUUIDFormat;

            const hex_str = str[i .. i + 2];
            bytes[byte_idx] = std.fmt.parseInt(u8, hex_str, 16) catch return error.InvalidHexDigit;

            byte_idx += 1;
            i += 2;
        }

        if (byte_idx != 16) return error.IncompleteUUID;

        return Self{ .bytes = bytes };
    }
};

// 方案1: UUID v4 (随机生成)
pub fn generateUUIDv4(random: std.Random) UUID {
    var bytes: [16]u8 = undefined;
    random.bytes(&bytes);

    // 设置版本号为 4 (随机)
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // 设置变体位
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    return UUID.fromBytes(bytes);
}

// 方案2: 基于时间戳的简单 UUID (不完全符合标准，但实用)
pub fn generateTimeBasedUUID(random: std.Random) UUID {
    var bytes: [16]u8 = undefined;

    // 前8字节使用时间戳
    const timestamp = std.time.timestamp();
    std.mem.writeInt(u64, bytes[0..8], @bitCast(timestamp), .big);

    // 后8字节使用随机数
    random.bytes(bytes[8..]);

    return UUID.fromBytes(bytes);
}

// 方案3: 使用系统熵生成更安全的 UUID
pub fn generateSecureUUID() !UUID {
    var bytes: [16]u8 = undefined;
    try std.posix.getrandom(&bytes);

    // 设置版本号为 4
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // 设置变体位
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    return UUID.fromBytes(bytes);
}

// 方案4: 基于哈希的 UUID v5 (需要命名空间和名称)
pub fn generateUUIDv5(namespace: UUID, name: []const u8) UUID {
    var hasher = crypto.hash.Sha1.init(.{});
    hasher.update(&namespace.bytes);
    hasher.update(name);

    var hash: [20]u8 = undefined;
    hasher.final(&hash);

    var bytes: [16]u8 = undefined;
    @memcpy(&bytes, hash[0..16]);

    // 设置版本号为 5
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    // 设置变体位
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    return UUID.fromBytes(bytes);
}

// UUID 生成器结构体
pub const UUIDGenerator = struct {
    random: std.Random,

    const Self = @This();

    pub fn init() Self {
        var prng = std.Random.DefaultPrng.init(blk: {
            var seed: u64 = undefined;
            std.posix.getrandom(std.mem.asBytes(&seed)) catch {
                // 如果获取系统随机数失败，使用时间戳作为种子
                seed = @intCast(std.time.timestamp());
            };
            break :blk seed;
        });
        return Self{
            .random = prng.random(),
        };
    }

    pub fn next(self: *Self) UUID {
        return generateUUIDv4(self.random);
    }

    pub fn nextSecure() !UUID {
        return generateSecureUUID();
    }

    pub fn nextTimeBased(self: *Self) UUID {
        return generateTimeBasedUUID(self.random);
    }
};

// 一些预定义的命名空间 UUID (RFC 4122)
const NAMESPACE_DNS = UUID.fromBytes([_]u8{ 0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1, 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8 });
const NAMESPACE_URL = UUID.fromBytes([_]u8{ 0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1, 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8 });

// 实用工具函数
pub const uuid_utils = struct {
    // 批量生成 UUID
    pub fn generateBatch(allocator: std.mem.Allocator, count: usize) ![]UUID {
        const uuids = try allocator.alloc(UUID, count);
        var generator = UUIDGenerator.init();

        for (uuids) |*uuid| {
            uuid.* = generator.next();
        }

        return uuids;
    }

    // 检查 UUID 是否为空
    pub fn isEmpty(uuid: UUID) bool {
        for (uuid.bytes) |byte| {
            if (byte != 0) return false;
        }
        return true;
    }

    // 创建空 UUID
    pub fn empty() UUID {
        return UUID.fromBytes([_]u8{0} ** 16);
    }

    // 比较两个 UUID
    pub fn equals(a: UUID, b: UUID) bool {
        return std.mem.eql(u8, &a.bytes, &b.bytes);
    }
};
