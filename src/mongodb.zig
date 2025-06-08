const std = @import("std");
const json = std.json;
const ts = @import("timestamp");

pub const MongoObjectId = struct {
    @"$oid": []const u8,

    pub fn fromBytes(bytes: [12]u8, allocator: std.mem.Allocator) !MongoObjectId {
        // 将 12 字节转换为 24 字符的十六进制字符串
        const hex_str = try allocator.alloc(u8, 24);
        for (bytes, 0..) |byte, i| {
            _ = std.fmt.bufPrint(hex_str[i * 2 .. i * 2 + 2], "{x:0>2}", .{byte}) catch unreachable;
        }

        return MongoObjectId{
            .@"$oid" = hex_str,
        };
    }

    pub fn toString(self: MongoObjectId) []const u8 {
        return self.@"$oid";
    }

    pub fn toBytes(self: MongoObjectId) ![12]u8 {
        if (self.@"$oid".len != 24) {
            return error.InvalidObjectIdLength;
        }

        var bytes: [12]u8 = undefined;
        for (0..12) |i| {
            const hex_part = self.@"$oid"[i * 2 .. i * 2 + 2];
            bytes[i] = std.fmt.parseInt(u8, hex_part, 16) catch return error.InvalidHexCharacter;
        }

        return bytes;
    }
};

pub const BsonConverter = struct {
    const c = @cImport({
        @cInclude("mongoc/mongoc.h");
    });

    // 从 BSON 文档直接转换为 Zig struct（不经过 JSON）
    pub fn fromBson(allocator: std.mem.Allocator, bson_doc: *const c.bson_t, comptime T: type) !T {
        var result: T = undefined;

        // 使用 comptime 反射获取结构体字段信息
        const fields = std.meta.fields(T);

        // 初始化迭代器
        var iter: c.bson_iter_t = undefined;
        if (!c.bson_iter_init(&iter, bson_doc)) {
            return error.InvalidBsonDocument;
        }

        // 为每个结构体字段查找对应的 BSON 字段
        inline for (fields) |field| {
            var field_iter: c.bson_iter_t = undefined;
            if (c.bson_iter_init_find(&field_iter, bson_doc, field.name.ptr)) {
                const field_ptr = &@field(result, field.name);
                try readBsonField(&field_iter, field_ptr, allocator, field.type);
            } else {
                // 如果字段不存在，根据类型设置默认值
                try setDefaultValue(&@field(result, field.name), field.type, allocator);
            }
        }

        return result;
    }

    // 从 BSON 迭代器读取字段值
    fn readBsonField(iter: *c.bson_iter_t, field_ptr: anytype, allocator: std.mem.Allocator, comptime FieldType: type) !void {
        const bson_type = c.bson_iter_type(iter);

        switch (@typeInfo(FieldType)) {
            .pointer => |ptr_info| {
                if (ptr_info.child == u8) {
                    // 字符串类型
                    if (bson_type == c.BSON_TYPE_UTF8) {
                        var len: u32 = undefined;
                        const str_value = c.bson_iter_utf8(iter, &len);

                        // 分配内存并复制字符串
                        const owned_str = try allocator.dupe(u8, str_value[0..len]);
                        field_ptr.* = owned_str;
                    } else {
                        return error.TypeMismatch;
                    }
                }
            },
            .int => {
                switch (FieldType) {
                    i32 => {
                        switch (bson_type) {
                            c.BSON_TYPE_INT32 => field_ptr.* = c.bson_iter_int32(iter),
                            c.BSON_TYPE_INT64 => field_ptr.* = @intCast(c.bson_iter_int64(iter)),
                            c.BSON_TYPE_DOUBLE => field_ptr.* = @intFromFloat(c.bson_iter_double(iter)),
                            c.BSON_TYPE_DATE_TIME => field_ptr.* = @intCast(@divTrunc(c.bson_iter_date_time(iter), 1000)),
                            else => return error.TypeMismatch,
                        }
                    },
                    i64 => {
                        switch (bson_type) {
                            c.BSON_TYPE_INT32 => field_ptr.* = c.bson_iter_int32(iter),
                            c.BSON_TYPE_INT64 => field_ptr.* = c.bson_iter_int64(iter),
                            c.BSON_TYPE_DOUBLE => field_ptr.* = @intFromFloat(c.bson_iter_double(iter)),
                            c.BSON_TYPE_DATE_TIME => field_ptr.* = c.bson_iter_date_time(iter),
                            else => return error.TypeMismatch,
                        }
                    },
                    else => return error.UnsupportedIntType,
                }
            },
            .float => {
                if (bson_type == c.BSON_TYPE_DOUBLE) {
                    field_ptr.* = @floatCast(c.bson_iter_double(iter));
                } else if (bson_type == c.BSON_TYPE_INT32) {
                    field_ptr.* = @floatFromInt(c.bson_iter_int32(iter));
                } else if (bson_type == c.BSON_TYPE_INT64) {
                    field_ptr.* = @floatFromInt(c.bson_iter_int64(iter));
                } else if (bson_type == c.BSON_TYPE_DATE_TIME) {
                    // 日期转换为浮点数时间戳（秒）
                    field_ptr.* = @floatFromInt(@divTrunc(c.bson_iter_date_time(iter), 1000));
                } else {
                    return error.TypeMismatch;
                }
            },
            .bool => {
                if (bson_type == c.BSON_TYPE_BOOL) {
                    field_ptr.* = c.bson_iter_bool(iter);
                } else {
                    return error.TypeMismatch;
                }
            },
            .@"struct" => {
                // 处理嵌套结构体
                if (bson_type == c.BSON_TYPE_DATE_TIME and FieldType == ts.Timestamp) {
                    // 直接处理 BSON 日期时间类型
                    const timestamp_ms = c.bson_iter_date_time(iter);
                    field_ptr.* = ts.Timestamp.fromUnixMillis(@intCast(timestamp_ms));
                } else if (bson_type == c.BSON_TYPE_OID and FieldType == MongoObjectId) {
                    // 直接处理 BSON ObjectId 类型
                    const oid_ptr = c.bson_iter_oid(iter);
                    var oid_bytes: [12]u8 = undefined;
                    @memcpy(&oid_bytes, @as([*]const u8, @ptrCast(oid_ptr))[0..12]);
                    field_ptr.* = try MongoObjectId.fromBytes(oid_bytes, allocator);
                } else if (bson_type == c.BSON_TYPE_DOCUMENT) {
                    var sub_iter: c.bson_iter_t = undefined;
                    if (c.bson_iter_recurse(iter, &sub_iter)) {
                        // 创建子文档
                        const sub_doc = c.bson_new();
                        defer c.bson_destroy(sub_doc);

                        // 从迭代器重建 BSON 文档
                        while (c.bson_iter_next(&sub_iter)) {
                            try copyBsonField(sub_doc, &sub_iter);
                        }

                        // 递归解析嵌套结构体
                        field_ptr.* = try fromBson(allocator, sub_doc, FieldType);
                    } else {
                        return error.InvalidNestedDocument;
                    }
                } else {
                    return error.TypeMismatch;
                }
            },
            .array => |array_info| {
                // 处理数组类型
                if (bson_type == c.BSON_TYPE_ARRAY) {
                    var array_iter: c.bson_iter_t = undefined;
                    if (c.bson_iter_recurse(iter, &array_iter)) {
                        var array_list = std.ArrayList(array_info.child).init(allocator);
                        defer array_list.deinit();

                        while (c.bson_iter_next(&array_iter)) {
                            var item: array_info.child = undefined;
                            try readBsonField(&array_iter, &item, allocator, array_info.child);
                            try array_list.append(item);
                        }

                        field_ptr.* = try array_list.toOwnedSlice();
                    } else {
                        return error.InvalidArray;
                    }
                } else {
                    return error.TypeMismatch;
                }
            },
            .optional => |opt_info| {
                // 处理可选类型
                if (bson_type == c.BSON_TYPE_NULL) {
                    field_ptr.* = null;
                } else {
                    var value: opt_info.child = undefined;
                    try readBsonField(iter, &value, allocator, opt_info.child);
                    field_ptr.* = value;
                }
            },
            else => {
                @compileError("不支持的字段类型: " ++ @typeName(FieldType));
            },
        }
    }

    // 复制 BSON 字段到新文档
    fn copyBsonField(doc: *c.bson_t, iter: *c.bson_iter_t) !void {
        const key = c.bson_iter_key(iter);
        const bson_type = c.bson_iter_type(iter);

        switch (bson_type) {
            c.BSON_TYPE_UTF8 => {
                var len: u32 = undefined;
                const str_value = c.bson_iter_utf8(iter, &len);
                _ = c.bson_append_utf8(doc, key, -1, str_value, @intCast(len));
            },
            c.BSON_TYPE_INT32 => {
                const int_value = c.bson_iter_int32(iter);
                _ = c.bson_append_int32(doc, key, -1, int_value);
            },
            c.BSON_TYPE_INT64 => {
                const int_value = c.bson_iter_int64(iter);
                _ = c.bson_append_int64(doc, key, -1, int_value);
            },
            c.BSON_TYPE_DOUBLE => {
                const double_value = c.bson_iter_double(iter);
                _ = c.bson_append_double(doc, key, -1, double_value);
            },
            c.BSON_TYPE_BOOL => {
                const bool_value = c.bson_iter_bool(iter);
                _ = c.bson_append_bool(doc, key, -1, bool_value);
            },
            c.BSON_TYPE_DATE_TIME => {
                const date_value = c.bson_iter_date_time(iter);
                _ = c.bson_append_date_time(doc, key, -1, date_value);
            },
            // 添加 ObjectId 处理
            c.BSON_TYPE_OID => {
                const oid_ptr = c.bson_iter_oid(iter);
                _ = c.bson_append_oid(doc, key, -1, oid_ptr);
            },
            else => {
                // 其他类型暂时跳过
            },
        }
    }

    // 设置默认值
    fn setDefaultValue(field_ptr: anytype, comptime FieldType: type, allocator: std.mem.Allocator) !void {
        _ = allocator;

        switch (@typeInfo(FieldType)) {
            .pointer => |ptr_info| {
                if (ptr_info.child == u8) {
                    field_ptr.* = "";
                }
            },
            .int => {
                field_ptr.* = 0;
            },
            .float => {
                field_ptr.* = 0.0;
            },
            .bool => {
                field_ptr.* = false;
            },
            .optional => {
                field_ptr.* = null;
            },
            .@"struct" => {
                // 对于结构体，需要递归初始化
                field_ptr.* = std.mem.zeroes(FieldType);
            },
            else => {
                field_ptr.* = std.mem.zeroes(FieldType);
            },
        }
    }

    // 从 Zig struct 创建 BSON 文档
    pub fn toBson(value: anytype) !*c.bson_t {
        const T = @TypeOf(value);
        const doc = c.bson_new();

        // 使用 comptime 反射遍历字段
        inline for (std.meta.fields(T)) |field| {
            const field_value = @field(value, field.name);
            try appendFieldToBson(doc, field.name, field_value);
        }

        return doc;
    }

    fn appendFieldToBson(doc: *c.bson_t, field_name: []const u8, value: anytype) !void {
        const T = @TypeOf(value);

        switch (@typeInfo(T)) {
            .pointer => |ptr_info| {
                if (ptr_info.child == u8 or (@typeInfo(ptr_info.child) == .array and @typeInfo(ptr_info.child).array.child == u8)) {
                    // 字符串类型
                    _ = c.bson_append_utf8(doc, field_name.ptr, @intCast(field_name.len), value.ptr, @intCast(value.len));
                }
            },
            .int => {
                switch (T) {
                    i32 => {
                        _ = c.bson_append_int32(doc, field_name.ptr, @intCast(field_name.len), value);
                    },
                    i64 => {
                        _ = c.bson_append_int64(doc, field_name.ptr, @intCast(field_name.len), value);
                    },
                    else => {
                        // 其他整数类型转换为 i32 或 i64
                        if (@sizeOf(T) <= @sizeOf(i32)) {
                            _ = c.bson_append_int32(doc, field_name.ptr, @intCast(field_name.len), @intCast(value));
                        } else {
                            _ = c.bson_append_int64(doc, field_name.ptr, @intCast(field_name.len), @intCast(value));
                        }
                    },
                }
            },
            .float => {
                switch (T) {
                    f32, f64 => {
                        _ = c.bson_append_double(doc, field_name.ptr, @intCast(field_name.len), @floatCast(value));
                    },
                    else => {
                        _ = c.bson_append_double(doc, field_name.ptr, @intCast(field_name.len), @floatCast(value));
                    },
                }
            },
            .bool => {
                _ = c.bson_append_bool(doc, field_name.ptr, @intCast(field_name.len), value);
            },
            .@"struct" => {
                if (T == ts.Timestamp) {
                    // 时间戳类型
                    const timestamp_ms = value.toUnixMillis();
                    _ = c.bson_append_date_time(doc, field_name.ptr, @intCast(field_name.len), timestamp_ms);
                } else if (T == MongoObjectId) {
                    // ObjectId 类型
                    const oid_bytes = value.toBytes();
                    var oid: c.bson_oid_t = undefined;
                    @memcpy(@as([*]u8, @ptrCast(&oid))[0..12], &oid_bytes);
                    _ = c.bson_append_oid(doc, field_name.ptr, @intCast(field_name.len), &oid);
                } else {
                    // 嵌套结构体，递归处理
                    const sub_doc = c.bson_new();
                    defer c.bson_destroy(sub_doc);
                    inline for (std.meta.fields(T)) |sub_field| {
                        const sub_value = @field(value, sub_field.name);
                        try appendFieldToBson(sub_doc, sub_field.name, sub_value);
                    }
                    _ = c.bson_append_document(doc, field_name.ptr, @intCast(field_name.len), sub_doc);
                }
            },
            .array => {
                // 处理数组类型
                const array_doc = c.bson_new();
                defer c.bson_destroy(array_doc);

                for (value, 0..) |item, i| {
                    var index_buf: [32]u8 = undefined;
                    const index_str = std.fmt.bufPrint(&index_buf, "{d}", .{i}) catch unreachable;
                    try appendFieldToBson(array_doc, index_str, item);
                }

                _ = c.bson_append_array(doc, field_name.ptr, @intCast(field_name.len), array_doc);
            },
            .optional => {
                // 处理可选类型
                if (value) |val| {
                    try appendFieldToBson(doc, field_name, val);
                } else {
                    _ = c.bson_append_null(doc, field_name.ptr, @intCast(field_name.len));
                }
            },
            else => {
                @compileError("不支持的字段类型: " ++ @typeName(T));
            },
        }
    }
};

pub const MongoDB = struct {
    const c = @cImport({
        @cInclude("mongoc/mongoc.h");
    });

    const Self = @This();

    pub fn init() Self {
        c.mongoc_init();
        return Self{};
    }

    pub fn getClient(self: *const Self, uri: []const u8) !MongoClient {
        _ = self;
        const p = c.mongoc_client_new(uri.ptr) orelse {
            return error.FailedToCreateClient;
        };
        return MongoClient{ .ptr = p };
    }

    pub fn deinit(self: Self) void {
        _ = self;
        c.mongoc_cleanup();
    }
};

pub const MongoClient = struct {
    const c = @cImport({
        @cInclude("mongoc/mongoc.h");
    });

    ptr: *c.mongoc_client_t,

    const Self = @This();

    pub fn getCollection(self: *Self, db: []const u8, collection: []const u8) !MongoConnection {
        const p = c.mongoc_client_get_collection(self.ptr, db.ptr, collection.ptr) orelse {
            return error.FailedToGetCollection;
        };
        return MongoConnection{ .ptr = p };
    }

    pub fn deinit(self: Self) void {
        c.mongoc_client_destroy(self.ptr);
    }
};

pub const MongoConnection = struct {
    const c = @cImport({
        @cInclude("mongoc/mongoc.h");
    });

    ptr: *c.mongoc_collection_t,

    const Self = @This();

    pub fn findOne(
        self: *Self,
        filter: anytype,
        allocator: std.mem.Allocator,
        comptime ResultType: type,
    ) !?ResultType {
        // 创建查询过滤器
        const filter_doc = try BsonConverter.toBson(filter);
        defer c.bson_destroy(filter_doc);

        // 执行查询
        const cursor = c.mongoc_collection_find_with_opts(self.ptr, filter_doc, null, null);
        if (cursor == null) {
            return error.InvalidArgument;
        }
        defer c.mongoc_cursor_destroy(cursor);

        var doc_ptr: ?*const c.bson_t = null;
        if (c.mongoc_cursor_next(cursor, @ptrCast(&doc_ptr))) {
            if (doc_ptr) |doc| {
                return try BsonConverter.fromBson(allocator, doc, ResultType);
            }
        }

        return null;
    }

    pub fn find(
        self: *Self,
        filter: anytype,
        allocator: std.mem.Allocator,
        comptime ResultType: type,
    ) ![]ResultType {
        var results = std.ArrayList(ResultType).init(allocator);

        // 创建查询过滤器
        const filter_doc = try BsonConverter.toBson(filter);
        defer c.bson_destroy(filter_doc);

        // 执行查询
        const cursor = c.mongoc_collection_find_with_opts(self.ptr, filter_doc, null, null);
        defer c.mongoc_cursor_destroy(cursor);

        var doc_ptr: ?*const c.bson_t = null;
        while (c.mongoc_cursor_next(cursor, @ptrCast(&doc_ptr))) {
            if (doc_ptr) |doc| {
                const result = try BsonConverter.fromBson(allocator, doc, ResultType);
                try results.append(result);
            }
        }

        return results.toOwnedSlice();
    }

    pub fn deinit(self: Self) void {
        c.mongoc_collection_destroy(self.ptr);
    }
};
