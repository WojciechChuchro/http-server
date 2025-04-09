const std = @import("std");

const net = std.net;

const Request = struct {
    request_line: []const u8,
    headers: []const u8,
    body: []const u8,
    const Self = @This();

    fn parse(input: []const u8) Request {
        var iter = std.mem.splitSequence(u8, input, "\r\n\r\n");

        const request_line_and_headers = iter.next().?;
        const body = iter.rest();
        var headers_iter = std.mem.splitSequence(u8, request_line_and_headers, "\r\n");

        return Request{
            .request_line = headers_iter.first(),
            .headers = headers_iter.rest(),
            .body = body,
        };
    }

    fn get_method(self: *Self) []const u8 {
        var request_line_iter = std.mem.splitSequence(u8, self.request_line, " ");

        return request_line_iter.first();
    }

    fn get_target(self: *Self) ?[]const u8 {
        var request_line_iter = std.mem.splitSequence(u8, self.request_line, " ");
        _ = request_line_iter.first();

        return request_line_iter.next();
    }

    fn is_echo(self: *Self) ?bool {
        if (self.get_target()) |target| {
            return std.mem.startsWith(u8, target, "/echo");
        }

        return null;
    }

    fn get_header(self: *Self, header_name: []const u8) ?[]const u8 {
        var header_iter = std.mem.splitSequence(u8, self.headers, "\r\n");

        while (header_iter.next()) |header| {
            var header_split = std.mem.splitSequence(u8, header, ": ");

            if (std.mem.eql(u8, header_split.next().?, header_name)) {
                return header_split.next();
            }
        }

        return null;
    }

    fn get_user_agent(self: *Self) ?[]const u8 {
        return self.get_header("User-Agent");
    }
};

fn ok_response(body: []const u8, writer: net.Stream.Writer) !void {
    try std.fmt.format(writer, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {}\r\n\r\n{s}", .{ body.len, body });
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const page_alloc = std.heap.page_allocator;
    var alloc: std.heap.ThreadSafeAllocator = .{ .child_allocator = page_alloc };

    try stdout.print("Logs from your program will appear here!\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);

    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    var pool: std.Thread.Pool = undefined;
    try pool.init(std.Thread.Pool.Options{
        .allocator = alloc.child_allocator,
        .n_jobs = 4,
    });
    defer pool.deinit();

    //var wait_group: std.Thread.WaitGroup = undefined;

    //wait_group.reset();

    while (true) {
        const connection = try listener.accept();

        try pool.spawn(handleConnection, .{ connection, stdout, alloc.allocator() });
    }
}

fn handleConnection(conn: net.Server.Connection, log: ?std.fs.File.Writer, alloc: std.mem.Allocator) void {
    defer conn.stream.close();

    if (log) |logger| {
        logger.print("client connected!\n", .{}) catch return handleError(conn);
    }

    const buffer = alloc.alloc(u8, 1024) catch return handleError(conn);
    defer alloc.free(buffer);

    const data_len = conn.stream.read(buffer) catch return handleError(conn);

    if (log) |logger| {
        logger.print("{s}\n", .{buffer[0..data_len]}) catch return handleError(conn);
    }

    var req = Request.parse(buffer[0..data_len]);

    if (std.mem.eql(u8, req.get_target().?, "/")) {
        conn.stream.writeAll("HTTP/1.1 200 OK\r\n\r\n") catch return handleError(conn);
    } else {
        var route_iter = std.mem.splitSequence(u8, req.get_target().?, "/");

        // skip the first '/' as there is nothing in front of it
        _ = route_iter.next();

        if (std.mem.eql(u8, route_iter.peek().?, "echo")) {
            _ = route_iter.next(); // skip what we peeked

            ok_response(route_iter.next().?, conn.stream.writer()) catch return handleError(conn);
        } else if (std.mem.eql(u8, route_iter.peek().?, "user-agent")) {
            _ = route_iter.next(); // skip what we peeked

            ok_response(req.get_user_agent().?, conn.stream.writer()) catch return handleError(conn);
        } else {
            conn.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n") catch return handleError(conn);
        }
    }

    if (log) |logger| {
        logger.print("HTTP response sent\n", .{}) catch return;
    }
}

fn handleError(connection: net.Server.Connection) void {
    connection.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\n\r\n") catch return;
}
