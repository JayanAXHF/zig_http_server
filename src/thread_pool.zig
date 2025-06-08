const std = @import("std");
const builtin = @import("builtin");
const Pool = @This();
const Thread = std.Thread;
const ArrayList = std.ArrayList;
pub const Mutex = std.Thread.Mutex;
const JobFn = fn (*anyopaque) anyerror!void;

pub const Job = struct {
    job: *const JobFn,
    args: *anyopaque,
};

pub const ThreadPool = struct {
    threads: []*Worker,
    allocator: std.mem.Allocator,
    jobs: ArrayList(Job),
    mutex: Mutex,
    running: bool = false,
    condition: std.Thread.Condition,

    pub fn init(allocator: std.mem.Allocator, threads: usize) !*ThreadPool {
        const pool = try allocator.create(ThreadPool);
        const threads_buf = try allocator.alloc(*Worker, threads);

        pool.* = ThreadPool{
            .threads = threads_buf,
            .jobs = ArrayList(Job).init(allocator),
            .allocator = allocator,
            .mutex = Mutex{},
            .running = true,
            .condition = std.Thread.Condition{},
        };

        for (pool.threads, 0..) |*thread, i| {
            var worker = try Worker.init(i, pool);
            thread.* = &worker;
        }

        return pool; // Re
    }
    pub fn deinit(self: *ThreadPool) void {
        self.running = false;
        std.time.sleep(100 * std.time.ns_per_ms);
        self.condition.broadcast();
        for (self.threads) |worker| {
            worker.deinit();
        }
        self.allocator.free(self.threads);
        self.jobs.deinit();
    }
    pub fn queue_job(self: *ThreadPool, job: *const JobFn, args: *anyopaque) !void {
        const new_job = Job{ .job = job, .args = args };

        self.mutex.lock();
        defer self.mutex.unlock();
        std.log.info("Appending Job", .{});
        try self.jobs.append(new_job);
        self.condition.signal();

        std.log.info("Job queue now contains {} jobs", .{self.jobs.items.len});
    }
};

pub const Worker = struct {
    thread: ?Thread,
    id: usize,
    mutex: Mutex,
    pub fn init(id: usize, pool: *ThreadPool) !Worker {
        return Worker{ .thread = try Thread.spawn(.{}, run_worker, .{pool}), .id = id, .mutex = pool.mutex };
    }
    pub fn deinit(self: *Worker) void {
        if (self.thread) |thread| {
            thread.detach();
        }
    }
};

fn run_worker(pool: *ThreadPool) void {
    const thread_id = std.Thread.getCurrentId();
    std.log.info("Worker thread {d} starting", .{thread_id});

    while (pool.running) {
        var maybe_job: ?Job = null;
        {
            pool.mutex.lock();

            defer {
                pool.mutex.unlock();
            }

            const job_count = pool.jobs.items.len;
            while (pool.jobs.items.len == 0 and pool.running) {
                pool.condition.wait(&pool.mutex);
            }

            std.log.info("Thread {d} found {d} jobs in queue", .{ thread_id, job_count });

            if (job_count > 0) {
                maybe_job = pool.jobs.pop();
                std.log.info("Thread {d} popped job, queue now has {d} jobs", .{ thread_id, pool.jobs.items.len });
            }
        }

        if (maybe_job) |job| {
            std.log.info("Thread {d} executing job...", .{thread_id});
            _ = job.job(job.args) catch |err| {
                std.log.err("Job failed: {s}", .{@errorName(err)});
            };
            std.log.info("Thread {d} finished executing job", .{thread_id});
        } else {
            std.log.info("Thread {d} found no jobs, sleeping...", .{thread_id});
            std.time.sleep(10 * std.time.ns_per_ms);
        }
    }
}
