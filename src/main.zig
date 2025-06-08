const std = @import("std");

const onebot = @import("onebot/onebot.zig");
const ts = @import("timestamp");
const ws = @import("websocket");
const mongodb = @import("mongodb.zig");
const maimai = @import("maimai.zig");
const String = @import("string").String;

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

    // Arbitrary (application-specific) data to pass into each handler
    // Pass void ({}) into listen if you have none
    var app = App{ .allocator = allocator, .city_info = &cityinfo, .group_info = &groupinfo, .arcade_info = &arcadeinfo };

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

    fn writeMessage(self: *Handler, h: anytype) !void {
        const H = @TypeOf(h);
        var arena = std.heap.ArenaAllocator.init(self.app.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const req = try onebot.action.new(H, h, allocator);
        const jreq = try req.toJson(allocator);
        var string = String.init(allocator);
        try std.json.stringify(jreq, .{}, string.writer());
        try self.conn.writeText(string.str());
    }

    fn splitCommandStart(str: []const u8, command: []const u8) ?[]const u8 {
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

    fn privateMessage(self: *Handler, e: onebot.MessageEvent) !void {
        var arena = std.heap.ArenaAllocator.init(self.app.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        if (e.user_id == 1071814607) {
            if (splitCommandStart(e.raw_message, "jt")) |value| {
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
                try self.writeMessage(onebot.action.PrivateMessageReq{
                    .user_id = e.user_id,
                    .message = chain.text(result.str()),
                });
            }
        }
    }

    fn groupMessage(self: *Handler, e: onebot.MessageEvent) !void {
        _ = self;
        if (e.user_id == 1071814607) {
            // var chain = onebot.MessageChain.init(self.app.allocator);
            // defer chain.deinit();
            // try chain.text("我在复读：").chain(&e.message);
            // try self.writeMessage(onebot.action.GroupMessageReq{
            //     .group_id = e.group_id.?,
            //     .message = &chain,
            // });
        }
    }

    // You must defined a public clientMessage method
    pub fn clientMessage(self: *Handler, data: []const u8) !void {
        // std.log.debug("{s}", .{data});
        var j = try std.json.parseFromSlice(std.json.Value, self.app.allocator, data, .{});
        defer j.deinit();

        switch (j.value) {
            .object => |root| {
                if (root.contains("retcode")) {} else if (onebot.Event.fromJson(self.app.allocator, j.value)) |e| {
                    defer e.deinit(self.app.allocator);

                    switch (e.post_data) {
                        .message => |me| {
                            switch (me.message_type) {
                                .private => {
                                    std.log.info("收到来自 {} 的私聊消息：{s}", .{ me.user_id, me.raw_message });
                                    try self.privateMessage(me);
                                },
                                .group => {
                                    std.log.info("收到来自 {} 里 {} 的群聊消息：{s}", .{ me.group_id.?, me.user_id, me.raw_message });
                                    try self.groupMessage(me);
                                },
                            }
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
    city_info: *mongodb.MongoConnection,
    group_info: *mongodb.MongoConnection,
    arcade_info: *mongodb.MongoConnection,
    // maybe a db pool
    // maybe a list of rooms
};
