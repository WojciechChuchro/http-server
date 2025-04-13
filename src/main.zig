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

fn file_response(file: []const u8, writer: net.Stream.Writer) !void {
    try std.fmt.format(writer, "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {}\r\n\r\n{s}", .{ file.len, file });
}

var directory_path: ?[]const u8 = null;
pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const page_alloc = std.heap.page_allocator;
    var args_iter = std.process.args();

    while (args_iter.next()) |val| {
        if (std.mem.eql(u8, val, "--directory")) {
            if (args_iter.next()) |value| {
                directory_path = value;
            } else {
                try stderr.print("Błąd: Flaga --directory wymaga podania wartości (ścieżki).\n", .{});

                return error.MissingArgumentValue;
            }
        }
    }

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
            _ = route_iter.next();

            ok_response(route_iter.next().?, conn.stream.writer()) catch return handleError(conn);
        } else if (std.mem.eql(u8, route_iter.peek().?, "user-agent")) {
            _ = route_iter.next();

            ok_response(req.get_user_agent().?, conn.stream.writer()) catch return handleError(conn);
        } else if (std.mem.eql(u8, route_iter.peek().?, "files")) {
            _ = route_iter.next();
            file_return(conn, route_iter.next().?, alloc, directory_path.?) catch return handleError(conn);
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
fn file_return(connection: net.Server.Connection, input: []const u8, allocator: std.mem.Allocator, dirname: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    const fileName = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dirname, input });

    const file = std.fs.cwd().openFile(fileName, .{});

    if (file) |value| {
        const file_size = try value.getEndPos();

        const buffer = try allocator.alloc(u8, file_size);

        defer allocator.free(buffer);

        const bytes = try value.read(buffer);

        if (bytes != file_size) @panic("Wrong file size");

        const response = try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {d}\r\n\r\n{s}", .{ file_size, buffer });

        try connection.stream.writeAll(response);
    } else |err| {
        try stdout.print("{any}\n", .{err});

        try connection.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
    }
}
