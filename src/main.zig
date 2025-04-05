const std = @import("std");

const net = std.net;

pub fn main() !void {

    const stdout = std.io.getStdOut().writer();

    try stdout.print("Logs from your program will appear here!\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);

    var listener = try address.listen(.{

        .reuse_address = true,

    });

    defer listener.deinit();

    const conn = try listener.accept();

    defer conn.stream.close();

    const alloc = std.heap.page_allocator;

    const input = try alloc.alloc(u8, 1024);

    defer alloc.free(input);

    _ = try conn.stream.read(input);

    var iter = std.mem.splitAny(u8, input, " ");

    _ = iter.next();

    if (std.mem.eql(u8, iter.next().?, "/")) {

        try success(conn);

    } else {

        try not_found(conn);

    }

}

pub fn success(conn: net.Server.Connection) !void {

    _ = try conn.stream.write("HTTP/1.1 200 OK\r\n\r\n");

}

pub fn not_found(conn: net.Server.Connection) !void {

    _ = try conn.stream.write("HTTP/1.1 404 Not Found\r\n\r\n");

}
