const std = @import("std");

const onebot = @import("onebot");
const ts = @import("timestamp");
const ws = @import("websocket");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();

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

    // Arbitrary (application-specific) data to pass into each handler
    // Pass void ({}) into listen if you have none
    var app = App{ .allocator = allocator };

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

    fn writeMessage(self: *Handler, comptime H: type, h: H) !void {
        var arena = std.heap.ArenaAllocator.init(self.app.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const req = try onebot.action.new(H, h, allocator);
        const jreq = try req.toJson(allocator);
        var string = std.ArrayList(u8).init(allocator);
        try std.json.stringify(jreq, .{}, string.writer());
        try self.conn.writeText(string.items);
    }

    fn privateMessage(self: *Handler, e: onebot.MessageEvent) !void {
        try self.writeMessage(onebot.action.PrivateMessageReq, .{
            .user_id = e.user_id,
            .message = &e.message,
        });
    }

    fn groupMessage(self: *Handler, e: onebot.MessageEvent) !void {
        if (e.user_id == 1071814607) {
            var chain = onebot.MessageChain.init(self.app.allocator);
            defer chain.deinit();
            try chain.text("我在复读：").chain(&e.message);
            try self.writeMessage(onebot.action.GroupMessageReq, .{
                .group_id = e.group_id.?,
                .message = &chain,
            });
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
    // maybe a db pool
    // maybe a list of rooms
};
