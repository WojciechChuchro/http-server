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

    var iter = std.mem.split(u8, input, " ");

    _ = iter.next();

    // const method = iter.next();

    const path = iter.next();

    var pathIter = std.mem.split(u8, path.?, "/");

    _ = pathIter.next();

    const root = pathIter.next();

    if (std.mem.eql(u8, path.?, "/")) {
        _ = try conn.stream.writeAll("HTTP/1.1 200 OK\r\n\r\n");
    } else if (std.mem.eql(u8, root.?, "echo")) {
        const first = pathIter.next();

        const res = try std.fmt.allocPrint(alloc, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {0d}\r\n\r\n{1s}", .{ first.?.len, first.? });

        _ = try conn.stream.writeAll(res);
    } else {
        _ = try conn.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
    }
}
