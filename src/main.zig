const std = @import("std");
const net = std.net;

fn sendNotFound(conn: net.Server.Connection) !void {
    try conn.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n", .{});
}

pub fn main() !void {
    const port = 4221;
    const stdout = std.io.getStdOut().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const response = try allocator.alloc(u8, 1024);
    defer allocator.free(response);

    //std.mem.copyBackwards(u8, response[0..str.len], str);

    try stdout.print("Server started at port {}\n", .{port});

    const address = try net.Address.resolveIp("127.0.0.1", port);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    const conn = try listener.accept();
    defer conn.stream.close();

    const input = try allocator.alloc(u8, 1024);
    defer allocator.free(input);

    const bytes_read = try conn.stream.read(input);
    try stdout.print("-----REQUEST-----: \n{s}\n", .{input[0..bytes_read]});

    var lines = std.mem.splitSequence(u8, input, "\n");

    const start_line = lines.next().?;
    var s = std.mem.splitSequence(u8, start_line, " ");

    const method = s.next().?;
    const request_target = s.next().?;
    const protocol = s.next().?;
    _ = method;
    _ = protocol;

    try stdout.print("Path: \n{s}\n", .{request_target});
    var url_parts = std.mem.splitAny(u8, request_target, "/");
    const part1 = url_parts.next();
    const part2 = url_parts.next();
    const part3 = url_parts.next();
    // First, let's determine which route we're handling
    const Route = enum {
        Root, // "/"
        Echo, // "/echo"
        EchoParam, // "/echo/parameter"
        NotFound, // Any other path
    };

    // Determine which route we're handling
    const route = if (part1) |p1| {
        if (std.mem.eql(u8, p1, "")) {
            if (part2) |p2| {
                if (std.mem.eql(u8, p2, "echo")) {
                    if (part3 != null) {
                        Route.EchoParam;
                    } else {
                        Route.Echo;
                    }
                } else {
                    Route.NotFound;
                }
            } else {
                Route.Root;
            }
        } else {
            Route.NotFound;
        }
    } else {
        Route.NotFound;
    };

    // Now handle each route with a switch statement
    switch (route) {
        .Root => try success(conn),
        .Echo => try not_found(conn), // You might want to handle this differently
        .EchoParam => {
            const p3 = part3.?; // We already checked that part3 is not null
            try stdout.print("part3: {s}\n", .{p3});
            const message = try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}", .{ p3.len, p3 });
            defer allocator.free(message);
            _ = try conn.stream.write(message);
        },
        .NotFound => try not_found(conn),
    }
}

pub fn responseWithBody(conn: net.Server.Connection, body: []const u8) !void {
    var header_buf: [128]u8 = undefined;
    const header = try std.fmt.bufPrint(
        &header_buf,
        .{body.len},
    );

    try conn.stream.writeAll(header);
    try conn.stream.writeAll(body);
}
pub fn success(conn: net.Server.Connection) !void {
    _ = try conn.stream.write("HTTP/1.1 200 OK\r\n\r\n");
}

pub fn not_found(conn: net.Server.Connection) !void {
    _ = try conn.stream.write("HTTP/1.1 404 Not Found\r\n\r\n");
}
