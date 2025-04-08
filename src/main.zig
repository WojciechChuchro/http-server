const std = @import("std");

// Uncomment this block to pass the first stage

const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const alloc = std.heap.page_allocator;

    // You can use print statements as follows for debugging, they'll be visible when running tests.

    try stdout.print("Logs from your program will appear here!\n", .{});

    // Uncomment this block to pass the first stage

    const address = try net.Address.resolveIp("127.0.0.1", 4221);

    var listener = try address.listen(.{
        .reuse_address = true,
    });

    defer listener.deinit();

    const conn = try listener.accept();

    defer conn.stream.close();

    try stdout.print("client connected!", .{});

    const input = try alloc.alloc(u8, 1024);

    defer alloc.free(input);

    _ = try conn.stream.read(input);

    var iter = std.mem.splitAny(u8, input, " ");
    var iter2 = std.mem.splitAny(u8, input, "\r\n");
    var user_agent: ?[]const u8 = undefined;

    try stdout.print("------------", .{});
    const ua_placeholder = "User-Agent: ";

    while (iter2.next()) |line| {
        try stdout.print("val: {s} len {}\n", .{ line, line.len });
        if (line.len == 0) continue;
        const index = std.mem.indexOf(u8, line, ua_placeholder) != null;
        if (index) {
            // Found the User-Agent header
            try stdout.print("Found User-Agent header\n", .{});

            // Extract the value part (after "User-Agent:")
            const value_start = ua_placeholder.len;
            user_agent = std.mem.trim(u8, line[value_start..], " ");
        }
    }
    try stdout.print("------------", .{});

    _ = iter.next();

    // const method = iter.next();

    const path = iter.next();

    var pathIter = std.mem.splitAny(u8, path.?, "/");

    _ = pathIter.next();

    const root = pathIter.next();

    if (std.mem.eql(u8, path.?, "/")) {
        _ = try conn.stream.writeAll("HTTP/1.1 200 OK\r\n\r\n");
    } else if (std.mem.eql(u8, root.?, "echo")) {
        const first = pathIter.next();

        const res = try std.fmt.allocPrint(alloc, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {0d}\r\n\r\n{1s}", .{ first.?.len, first.? });

        _ = try conn.stream.writeAll(res);
    } else if (std.mem.eql(u8, root.?, "user-agent")) {
        const res = try std.fmt.allocPrint(alloc, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {0d}\r\n\r\n{1s}", .{ user_agent.?.len, user_agent.? });
        _ = try conn.stream.writeAll(res);
    } else {
        _ = try conn.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
    }
}
