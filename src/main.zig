const std = @import("std");

const onebot = @import("onebot/onebot.zig");
const ts = @import("timestamp");
const ws = @import("websocket");
const mongodb = @import("mongodb.zig");
const maimai = @import("maimai.zig");
const utils = @import("utils");
const String = @import("string").String;
const chanz = @import("chanz.zig");
const rc = @import("rc.zig");

pub const std_options = std.Options{ .log_scope_levels = &[_]std.log.ScopeLevel{
    .{ .scope = .websocket, .level = .info },
} };

pub const RetWrapper = struct { ret: onebot.action.DynamicApiReturn, arena: rc.Arc(std.heap.ArenaAllocator) };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();

    // init mongodb
    const db = mongodb.MongoDB.init();
    defer db.deinit();

    const uri_string = "mongodb://localhost:27017";
    var client = try db.getClient(uri_string);
    defer client.deinit();

    var server = try ws.Server(Handler).init(allocator, .{
        .port = 9224,
        .address = "127.0.0.1",
        .handshake = .{
            .timeout = 3,
            .max_size = 1024,
            // since we aren't using hanshake.headers
            // we can set this to 0 to save a few bytes.
            .max_headers = 0,
        },
    });

    // 获取集合
    var groupinfo = try client.getCollection("maimaicheckbot", "groupinfo");
    defer groupinfo.deinit();

    var cityinfo = try client.getCollection("maimaicheckbot", "cityinfo");
    defer cityinfo.deinit();

    var arcadeinfo = try client.getCollection("maimaicheckbot", "arcadeinfo");
    defer arcadeinfo.deinit();

    var channel = chanz.Chan(RetWrapper).init(allocator);
    defer channel.deinit();

    // Arbitrary (application-specific) data to pass into each handler
    // Pass void ({}) into listen if you have none
    var app = App{ .allocator = allocator, .thread_pool = undefined, .channel = channel, .city_info = &cityinfo, .group_info = &groupinfo, .arcade_info = &arcadeinfo };

    try app.thread_pool.init(.{ .allocator = app.allocator });
    defer app.thread_pool.deinit();

    // this blocks
    try server.listen(&app);
}

// This is your application-specific wrapper around a websocket connection
const Handler = struct {
    app: *App,
    conn: *ws.Conn,

    // You must define a public init function which takes
    pub fn init(h: *ws.Handshake, conn: *ws.Conn, app: *App) !Handler {
        // `h` contains the initial websocket "handshake" request
        // It can be used to apply application-specific logic to verify / allow
        // the connection (e.g. valid url, query string parameters, or headers)

        _ = h; // we're not using this in our simple case

        return .{
            .app = app,
            .conn = conn,
        };
    }

    fn writeAction(self: *Handler, comptime H: type, h: anytype) !H.Ret {
        var arena = std.heap.ArenaAllocator.init(self.app.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const req = try onebot.action.new(H, h, allocator);
        const jreq = try req.toJson(allocator);
        var string = String.init(allocator);
        try std.json.stringify(jreq, .{}, string.writer());
        try self.conn.writeText(string.str());
        const ret = try self.app.channel.recv();
        defer if (ret.arena.releaseUnwrap()) |v| v.deinit();
        if (std.mem.eql(u8, ret.ret.echo, req.echo)) {
            switch (@typeInfo(H.Ret)) {
                .void => {
                    return;
                },
                .@"struct" => {
                    return try H.Ret.fromJson(ret.ret.data, self.app.allocator);
                },
                else => {
                    return error.InvalidReturnType;
                },
            }
        } else {
            return error.InvalidReturn;
        }
    }

    fn writeMessage(self: *Handler, h: anytype) !i64 {
        const H = @TypeOf(h);
        const ret = try self.writeAction(H, h);
        return ret.message_id;
    }

    fn privateMessage(self: *Handler, e: onebot.MessageEvent) !void {
        var arena = std.heap.ArenaAllocator.init(self.app.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        if (e.user_id == 1071814607) {
            if (utils.splitCommandStart(e.raw_message, "jt")) |value| {
                const city_name = std.mem.trim(u8, value, " \n");
                const arcades = try self.app.arcade_info.find(.{ .city_name = city_name }, allocator, maimai.ArcadeInfo);

                var total_people: i32 = 0;
                var result = String.init(allocator);
                const writer = result.writer();

                _ = try writer.write("机厅在线人数：\n");
                for (arcades) |arcade| {
                    total_people += arcade.arcade_num;
                    try writer.print("{s}: {}人, 上传时间: {time}, 上传者：{s}\n", .{
                        arcade.nickname, // 店名
                        arcade.arcade_num, // 人数
                        arcade.update_time, // 上传时间
                        arcade.update_id, // 上传者
                    });
                }
                try writer.print("{s}一共有{}人正在出勤。", .{ city_name, total_people });

                var chain = onebot.MessageChain.init(allocator);
                defer chain.deinit();
                _ = try self.writeMessage(onebot.action.PrivateMessageReq{
                    .user_id = e.user_id,
                    .message = chain.text(result.str()),
                });
            } else {
                const ret = try self.writeAction(onebot.action.GetStatus, onebot.action.GetStatus{});
                std.debug.print("{}", .{ret});
                var chain = onebot.MessageChain.init(self.app.allocator);
                defer chain.deinit();
                try chain.text("我在复读：").chain(&e.message);
                _ = try self.writeMessage(onebot.action.PrivateMessageReq{
                    .user_id = e.user_id,
                    .message = &chain,
                });
            }
        }
    }

    fn groupMessage(self: *Handler, e: onebot.MessageEvent) !void {
        var arena = std.heap.ArenaAllocator.init(self.app.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        if (e.group_id.? == 195135404) {
            if (utils.checkCommandStart(e.raw_message, "ginfo")) {
                const ret = try self.writeAction(onebot.action.GetGroupInfo, onebot.action.GetGroupInfo{ .group_id = e.group_id.? });
                defer ret.deinit();
                std.debug.print("{}", .{ret});

                var s = String.init(allocator);
                const writer = s.writer();

                try writer.print("[{}] {s} ({})", .{ ret.group_id, ret.group_name.str(), ret.member_count });

                var chain = onebot.MessageChain.init(self.app.allocator);
                defer chain.deinit();

                _ = try self.writeMessage(onebot.action.GroupMessageReq{
                    .group_id = e.group_id.?,
                    .message = chain.text(s.str()),
                });
            }
        }
    }

    fn processMessage(self: *Handler, e: onebot.MessageEvent, arena: rc.Arc(std.heap.ArenaAllocator)) void {
        defer if (arena.releaseUnwrap()) |v| v.deinit();
        switch (e.message_type) {
            .private => {
                std.log.info("收到来自 {} 的私聊消息：{s}", .{ e.user_id, e.raw_message });
                self.privateMessage(e) catch |err| {
                    std.log.info("出现未知错误：{any}", .{err});
                };
            },
            .group => {
                std.log.info("收到来自 {} 里 {} 的群聊消息：{s}", .{ e.group_id.?, e.user_id, e.raw_message });
                self.groupMessage(e) catch |err| {
                    std.log.info("出现未知错误：{any}", .{err});
                };
            },
        }
    }

    // You must defined a public clientMessage method
    pub fn clientMessage(self: *Handler, data: []const u8) !void {
        // std.log.debug("{s}", .{data});

        var arena = try rc.arc(self.app.allocator, std.heap.ArenaAllocator.init(self.app.allocator));
        const allocator = arena.value.allocator();
        defer if (arena.releaseUnwrap()) |v| v.deinit();

        const j = try std.json.parseFromSliceLeaky(std.json.Value, allocator, data, .{});
        switch (j) {
            .object => {
                if (onebot.action.DynamicApiReturn.fromJson(j)) |ret| {
                    try self.app.channel.send(.{ .ret = ret, .arena = arena.retain() });
                    std.log.debug("{s}", .{data});
                } else if (onebot.Event.fromJson(allocator, j)) |e| {
                    switch (e.post_data) {
                        .message => |me| {
                            try self.app.thread_pool.spawn(processMessage, .{ self, me, arena.retain() });
                        },
                        .meta => |ma| {
                            switch (ma) {
                                .lifecycle => {
                                    std.log.info("{any}", .{ma});
                                },
                                else => {},
                            }
                        },
                    }
                    // try self.conn.writeText(s); // echo the message back
                }
            },
            else => {},
        }
    }
};

// This is application-specific you want passed into your Handler's
// init function.
const App = struct {
    allocator: std.mem.Allocator,
    thread_pool: std.Thread.Pool,
    channel: chanz.Chan(RetWrapper),

    city_info: *mongodb.MongoConnection,
    group_info: *mongodb.MongoConnection,
    arcade_info: *mongodb.MongoConnection,
    // maybe a db pool
    // maybe a list of rooms
};
