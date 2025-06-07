const std = @import("std");
const json = std.json;
const time = std.time;
const fmt = std.fmt;

// 时间戳类型
pub const Timestamp = struct {
    unix_seconds: u64,
    nanoseconds: u32 = 0,

    // 从 Unix 时间戳（秒）创建
    pub fn fromUnixSeconds(seconds: u64) Timestamp {
        return Timestamp{ .unix_seconds = seconds };
    }

    // 从 Unix 时间戳（毫秒）创建
    pub fn fromUnixMillis(millis: u64) Timestamp {
        return Timestamp{
            .unix_seconds = @divTrunc(millis, 1000),
            .nanoseconds = @intCast((@mod(millis, 1000)) * 1_000_000),
        };
    }

    // 从 Unix 时间戳（微秒）创建
    pub fn fromUnixMicros(micros: u64) Timestamp {
        return Timestamp{
            .unix_seconds = @divTrunc(micros, 1_000_000),
            .nanoseconds = @intCast((@mod(micros, 1_000_000)) * 1000),
        };
    }

    // 从浮点数 Unix 时间戳创建
    pub fn fromUnixFloat(timestamp: f64) Timestamp {
        const seconds = @as(u64, @intFromFloat(@trunc(timestamp)));
        const fractional = timestamp - @trunc(timestamp);
        const nanos = @as(u32, @intFromFloat(fractional * 1_000_000_000));

        return Timestamp{
            .unix_seconds = seconds,
            .nanoseconds = nanos,
        };
    }

    // 从当前时间创建
    pub fn now() Timestamp {
        const timestamp = time.timestamp();
        return Timestamp{ .unix_seconds = timestamp };
    }

    // 转换为浮点数
    pub fn toFloat(self: Timestamp) f64 {
        return @as(f64, @floatFromInt(self.unix_seconds)) +
            @as(f64, @floatFromInt(self.nanoseconds)) / 1_000_000_000.0;
    }

    // 转换为毫秒
    pub fn toMillis(self: Timestamp) u64 {
        return self.unix_seconds * 1000 + @divTrunc(self.nanoseconds, 1_000_000);
    }

    // 转换为微秒
    pub fn toMicros(self: Timestamp) u64 {
        return self.unix_seconds * 1_000_000 + @divTrunc(self.nanoseconds, 1000);
    }

    // 格式化为可读字符串
    pub fn format(
        self: Timestamp,
        comptime fmt_str: []const u8,
        options: fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (std.mem.eql(u8, fmt_str, "iso")) {
            // ISO 8601 格式 (简化版)
            const epoch_seconeds = time.epoch.EpochSeconds{ .secs = self.unix_seconds };
            const epoch_day = epoch_seconeds.getEpochDay();
            const year_day = epoch_day.calculateYearDay();
            const month_day = year_day.calculateMonthDay();

            const seconds_in_day = @mod(self.unix_seconds, time.s_per_day);
            const hours = @divTrunc(seconds_in_day, time.s_per_hour);
            const minutes = @divTrunc(@mod(seconds_in_day, time.s_per_hour), time.s_per_min);
            const seconds = @mod(seconds_in_day, time.s_per_min);

            try writer.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{ year_day.year, month_day.month.numeric(), month_day.day_index + 1, hours, minutes, seconds });

            if (self.nanoseconds > 0) {
                try writer.print(".{d:0>9}", .{self.nanoseconds});
            }
            try writer.writeAll("Z");
        } else if (std.mem.eql(u8, fmt_str, "unix")) {
            try writer.print("{d}", .{self.unix_seconds});
        } else if (std.mem.eql(u8, fmt_str, "float")) {
            try writer.print("{d:.6}", .{self.toFloat()});
        } else if (std.mem.eql(u8, fmt_str, "millis")) {
            try writer.print("{d}", .{self.toMillis()});
        } else {
            // 默认格式：iso
            try format(self, "iso", options, writer);
        }
    }
};

// 从 JSON 值解析时间戳
pub const TimestampParser = struct {
    pub fn parseFromJson(value: json.Value) !Timestamp {
        return switch (value) {
            .integer => |int| Timestamp.fromUnixSeconds(@intCast(int)),
            .float => |float| Timestamp.fromUnixFloat(float),
            .string => |str| parseFromString(str),
            else => error.InvalidTimestampFormat,
        };
    }

    pub fn parseFromString(str: []const u8) !Timestamp {
        // 尝试解析不同格式的字符串时间戳

        // 1. 纯数字字符串（Unix 时间戳）
        if (std.fmt.parseInt(u64, str, 10)) |unix_seconds| {
            // 判断是秒还是毫秒（通过长度判断）
            if (str.len <= 10) {
                return Timestamp.fromUnixSeconds(unix_seconds);
            } else if (str.len == 13) {
                return Timestamp.fromUnixMillis(unix_seconds);
            } else if (str.len == 16) {
                return Timestamp.fromUnixMicros(unix_seconds);
            }
        } else |_| {}

        // 2. 浮点数字符串
        if (std.fmt.parseFloat(f64, str)) |float_timestamp| {
            return Timestamp.fromUnixFloat(float_timestamp);
        } else |_| {}

        // 3. ISO 8601 格式 (简化解析)
        if (parseIso8601(str)) |timestamp| {
            return timestamp;
        } else |_| {}

        return error.UnknownTimestampFormat;
    }

    // 简化的 ISO 8601 解析器
    fn parseIso8601(str: []const u8) !Timestamp {
        // 支持格式：2024-12-05T10:30:45Z 或 2024-12-05T10:30:45.123Z
        if (str.len < 19) return error.InvalidIsoFormat;

        // 解析年月日
        const year = try std.fmt.parseInt(u16, str[0..4], 10);
        const month = try std.fmt.parseInt(u8, str[5..7], 10);
        const day = try std.fmt.parseInt(u8, str[8..10], 10);

        // 解析时分秒
        const hour = try std.fmt.parseInt(u64, str[11..13], 10);
        const minute = try std.fmt.parseInt(u64, str[14..16], 10);
        const second = try std.fmt.parseInt(u64, str[17..19], 10);

        // 构建时间（简化版，不考虑闰年等复杂情况）
        const days_since_epoch = try calculateDaysSinceEpoch(year, month, day);
        const seconds_in_day = hour * 3600 + minute * 60 + second;
        const unix_seconds = days_since_epoch * 86400 + seconds_in_day;

        var nanoseconds: u32 = 0;

        // 解析毫秒/微秒/纳秒
        if (str.len > 20 and str[19] == '.') {
            var end_idx: usize = 20;
            while (end_idx < str.len and std.ascii.isDigit(str[end_idx])) {
                end_idx += 1;
            }

            const frac_str = str[20..end_idx];
            if (frac_str.len > 0) {
                const frac_value = try std.fmt.parseInt(u32, frac_str, 10);
                // 根据小数位数转换为纳秒
                nanoseconds = switch (frac_str.len) {
                    1 => frac_value * 100_000_000, // 0.1s
                    2 => frac_value * 10_000_000, // 0.01s
                    3 => frac_value * 1_000_000, // 0.001s (毫秒)
                    4 => frac_value * 100_000, // 0.0001s
                    5 => frac_value * 10_000, // 0.00001s
                    6 => frac_value * 1_000, // 0.000001s (微秒)
                    7 => frac_value * 100, // 0.0000001s
                    8 => frac_value * 10, // 0.00000001s
                    9 => frac_value, // 0.000000001s (纳秒)
                    else => frac_value, // 超过纳秒精度，截断
                };
            }
        }

        return Timestamp{
            .unix_seconds = unix_seconds,
            .nanoseconds = nanoseconds,
        };
    }

    // 简化的天数计算（不考虑闰年）
    fn calculateDaysSinceEpoch(year: u16, month: u8, day: u8) !u64 {
        // 1970年1月1日是 Unix 纪元
        const epoch_year = 1970;

        var days: u64 = 0;

        // 计算年份差异的天数
        if (year >= epoch_year) {
            for (epoch_year..year) |y| {
                days += if (isLeapYear(@intCast(y))) 366 else 365;
            }
        } else {
            return error.InvalidDays; // 简化处理，不支持1970年之前
        }

        // 计算月份的天数
        const days_in_month = [12]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        for (1..month) |m| {
            days += days_in_month[m - 1];
            if (m == 2 and isLeapYear(year)) {
                days += 1; // 闰年2月多一天
            }
        }

        // 加上当月的天数
        days += day - 1; // day 是从1开始的

        return days;
    }

    fn isLeapYear(year: u16) bool {
        return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
    }
};
