const std = @import("../../std.zig");
const builtin = @import("builtin");
const mem = std.mem;
const debug = std.debug;

const has_vaes = builtin.cpu.arch == .x86_64 and builtin.cpu.has(.x86, .vaes);
const has_avx512f = builtin.cpu.arch == .x86_64 and builtin.zig_backend != .stage2_x86_64 and builtin.cpu.has(.x86, .avx512f);

/// A single AES block.
pub const Block = struct {
    const Repr = @Vector(2, u64);

    /// The length of an AES block in bytes.
    pub const block_length: usize = 16;

    /// Internal representation of a block.
    repr: Repr,

    /// Convert a byte sequence into an internal representation.
    pub fn fromBytes(bytes: *const [16]u8) Block {
        const repr = mem.bytesToValue(Repr, bytes);
        return Block{ .repr = repr };
    }

    /// Convert the internal representation of a block into a byte sequence.
    pub fn toBytes(block: Block) [16]u8 {
        return mem.toBytes(block.repr);
    }

    /// XOR the block with a byte sequence.
    pub fn xorBytes(block: Block, bytes: *const [16]u8) [16]u8 {
        const x = block.repr ^ fromBytes(bytes).repr;
        return mem.toBytes(x);
    }

    /// Encrypt a block with a round key.
    pub fn encrypt(block: Block, round_key: Block) Block {
        return Block{
            .repr = asm (
                \\ vaesenc %[rk], %[in], %[out]
                : [out] "=x" (-> Repr),
                : [in] "x" (block.repr),
                  [rk] "x" (round_key.repr),
            ),
        };
    }

    /// Encrypt a block with the last round key.
    pub fn encryptLast(block: Block, round_key: Block) Block {
        return Block{
            .repr = asm (
                \\ vaesenclast %[rk], %[in], %[out]
                : [out] "=x" (-> Repr),
                : [in] "x" (block.repr),
                  [rk] "x" (round_key.repr),
            ),
        };
    }

    /// Decrypt a block with a round key.
    pub fn decrypt(block: Block, inv_round_key: Block) Block {
        return Block{
            .repr = asm (
                \\ vaesdec %[rk], %[in], %[out]
                : [out] "=x" (-> Repr),
                : [in] "x" (block.repr),
                  [rk] "x" (inv_round_key.repr),
            ),
        };
    }

    /// Decrypt a block with the last round key.
    pub fn decryptLast(block: Block, inv_round_key: Block) Block {
        return Block{
            .repr = asm (
                \\ vaesdeclast %[rk], %[in], %[out]
                : [out] "=x" (-> Repr),
                : [in] "x" (block.repr),
                  [rk] "x" (inv_round_key.repr),
            ),
        };
    }

    /// Apply the bitwise XOR operation to the content of two blocks.
    pub fn xorBlocks(block1: Block, block2: Block) Block {
        return Block{ .repr = block1.repr ^ block2.repr };
    }

    /// Apply the bitwise AND operation to the content of two blocks.
    pub fn andBlocks(block1: Block, block2: Block) Block {
        return Block{ .repr = block1.repr & block2.repr };
    }

    /// Apply the bitwise OR operation to the content of two blocks.
    pub fn orBlocks(block1: Block, block2: Block) Block {
        return Block{ .repr = block1.repr | block2.repr };
    }

    /// Perform operations on multiple blocks in parallel.
    pub const parallel = struct {
        const cpu = std.Target.x86.cpu;

        /// The recommended number of AES encryption/decryption to perform in parallel for the chosen implementation.
        pub const optimal_parallel_blocks = switch (builtin.cpu.model) {
            &cpu.westmere, &cpu.goldmont => 3,
            &cpu.cannonlake, &cpu.skylake, &cpu.skylake_avx512, &cpu.tremont, &cpu.goldmont_plus, &cpu.cascadelake => 4,
            &cpu.icelake_client, &cpu.icelake_server, &cpu.tigerlake, &cpu.rocketlake, &cpu.alderlake => 6,
            &cpu.haswell, &cpu.broadwell => 7,
            &cpu.sandybridge, &cpu.ivybridge => 8,
            &cpu.znver1, &cpu.znver2, &cpu.znver3, &cpu.znver4 => 8,
            else => 8,
        };

        /// Encrypt multiple blocks in parallel, each their own round key.
        pub fn encryptParallel(comptime count: usize, blocks: [count]Block, round_keys: [count]Block) [count]Block {
            comptime var i = 0;
            var out: [count]Block = undefined;
            inline while (i < count) : (i += 1) {
                out[i] = blocks[i].encrypt(round_keys[i]);
            }
            return out;
        }

        /// Decrypt multiple blocks in parallel, each their own round key.
        pub fn decryptParallel(comptime count: usize, blocks: [count]Block, round_keys: [count]Block) [count]Block {
            comptime var i = 0;
            var out: [count]Block = undefined;
            inline while (i < count) : (i += 1) {
                out[i] = blocks[i].decrypt(round_keys[i]);
            }
            return out;
        }

        /// Encrypt multiple blocks in parallel with the same round key.
        pub fn encryptWide(comptime count: usize, blocks: [count]Block, round_key: Block) [count]Block {
            comptime var i = 0;
            var out: [count]Block = undefined;
            inline while (i < count) : (i += 1) {
                out[i] = blocks[i].encrypt(round_key);
            }
            return out;
        }

        /// Decrypt multiple blocks in parallel with the same round key.
        pub fn decryptWide(comptime count: usize, blocks: [count]Block, round_key: Block) [count]Block {
            comptime var i = 0;
            var out: [count]Block = undefined;
            inline while (i < count) : (i += 1) {
                out[i] = blocks[i].decrypt(round_key);
            }
            return out;
        }

        /// Encrypt multiple blocks in parallel with the same last round key.
        pub fn encryptLastWide(comptime count: usize, blocks: [count]Block, round_key: Block) [count]Block {
            comptime var i = 0;
            var out: [count]Block = undefined;
            inline while (i < count) : (i += 1) {
                out[i] = blocks[i].encryptLast(round_key);
            }
            return out;
        }

        /// Decrypt multiple blocks in parallel with the same last round key.
        pub fn decryptLastWide(comptime count: usize, blocks: [count]Block, round_key: Block) [count]Block {
            comptime var i = 0;
            var out: [count]Block = undefined;
            inline while (i < count) : (i += 1) {
                out[i] = blocks[i].decryptLast(round_key);
            }
            return out;
        }
    };
};

/// A fixed-size vector of AES blocks.
/// All operations are performed in parallel, using SIMD instructions when available.
pub fn BlockVec(comptime blocks_count: comptime_int) type {
    return struct {
        const Self = @This();

        /// The number of AES blocks the target architecture can process with a single instruction.
        pub const native_vector_size = w: {
            if (has_avx512f and blocks_count % 4 == 0) break :w 4;
            if (has_vaes and blocks_count % 2 == 0) break :w 2;
            break :w 1;
        };

        /// The size of the AES block vector that the target architecture can process with a single instruction, in bytes.
        pub const native_word_size = native_vector_size * 16;

        const native_words = blocks_count / native_vector_size;

        const Repr = @Vector(native_vector_size * 2, u64);

        /// Internal representation of a block vector.
        repr: [native_words]Repr,

        /// Length of the block vector in bytes.
        pub const block_length: usize = blocks_count * 16;

        /// Convert a byte sequence into an internal representation.
        pub fn fromBytes(bytes: *const [blocks_count * 16]u8) Self {
            var out: Self = undefined;
            inline for (0..native_words) |i| {
                out.repr[i] = mem.bytesToValue(Repr, bytes[i * native_word_size ..][0..native_word_size]);
            }
            return out;
        }

        /// Convert the internal representation of a block vector into a byte sequence.
        pub fn toBytes(block_vec: Self) [blocks_count * 16]u8 {
            var out: [blocks_count * 16]u8 = undefined;
            inline for (0..native_words) |i| {
                out[i * native_word_size ..][0..native_word_size].* = mem.toBytes(block_vec.repr[i]);
            }
            return out;
        }

        /// XOR the block vector with a byte sequence.
        pub fn xorBytes(block_vec: Self, bytes: *const [blocks_count * 16]u8) [blocks_count * 16]u8 {
            var x: Self = undefined;
            inline for (0..native_words) |i| {
                x.repr[i] = block_vec.repr[i] ^ mem.bytesToValue(Repr, bytes[i * native_word_size ..][0..native_word_size]);
            }
            return x.toBytes();
        }

        /// Apply the forward AES operation to the block vector with a vector of round keys.
        pub fn encrypt(block_vec: Self, round_key_vec: Self) Self {
            var out: Self = undefined;
            inline for (0..native_words) |i| {
                out.repr[i] = asm (
                    \\ vaesenc %[rk], %[in], %[out]
                    : [out] "=x" (-> Repr),
                    : [in] "x" (block_vec.repr[i]),
                      [rk] "x" (round_key_vec.repr[i]),
                );
            }
            return out;
        }

        /// Apply the forward AES operation to the block vector with a vector of last round keys.
        pub fn encryptLast(block_vec: Self, round_key_vec: Self) Self {
            var out: Self = undefined;
            inline for (0..native_words) |i| {
                out.repr[i] = asm (
                    \\ vaesenclast %[rk], %[in], %[out]
                    : [out] "=x" (-> Repr),
                    : [in] "x" (block_vec.repr[i]),
                      [rk] "x" (round_key_vec.repr[i]),
                );
            }
            return out;
        }

        /// Apply the inverse AES operation to the block vector with a vector of round keys.
        pub fn decrypt(block_vec: Self, inv_round_key_vec: Self) Self {
            var out: Self = undefined;
            inline for (0..native_words) |i| {
                out.repr[i] = asm (
                    \\ vaesdec %[rk], %[in], %[out]
                    : [out] "=x" (-> Repr),
                    : [in] "x" (block_vec.repr[i]),
                      [rk] "x" (inv_round_key_vec.repr[i]),
                );
            }
            return out;
        }

        /// Apply the inverse AES operation to the block vector with a vector of last round keys.
        pub fn decryptLast(block_vec: Self, inv_round_key_vec: Self) Self {
            var out: Self = undefined;
            inline for (0..native_words) |i| {
                out.repr[i] = asm (
                    \\ vaesdeclast %[rk], %[in], %[out]
                    : [out] "=x" (-> Repr),
                    : [in] "x" (block_vec.repr[i]),
                      [rk] "x" (inv_round_key_vec.repr[i]),
                );
            }
            return out;
        }

        /// Apply the bitwise XOR operation to the content of two block vectors.
        pub fn xorBlocks(block_vec1: Self, block_vec2: Self) Self {
            var out: Self = undefined;
            inline for (0..native_words) |i| {
                out.repr[i] = block_vec1.repr[i] ^ block_vec2.repr[i];
            }
            return out;
        }

        /// Apply the bitwise AND operation to the content of two block vectors.
        pub fn andBlocks(block_vec1: Self, block_vec2: Self) Self {
            var out: Self = undefined;
            inline for (0..native_words) |i| {
                out.repr[i] = block_vec1.repr[i] & block_vec2.repr[i];
            }
            return out;
        }

        /// Apply the bitwise OR operation to the content of two block vectors.
        pub fn orBlocks(block_vec1: Self, block_vec2: Block) Self {
            var out: Self = undefined;
            inline for (0..native_words) |i| {
                out.repr[i] = block_vec1.repr[i] | block_vec2.repr[i];
            }
            return out;
        }
    };
}

fn KeySchedule(comptime Aes: type) type {
    std.debug.assert(Aes.rounds == 10 or Aes.rounds == 14);
    const rounds = Aes.rounds;

    return struct {
        const Self = @This();

        const Repr = Aes.block.Repr;

        round_keys: [rounds + 1]Block,

        fn drc(comptime second: bool, comptime rc: u8, t: Repr, tx: Repr) Repr {
            var s: Repr = undefined;
            var ts: Repr = undefined;
            return asm (
                \\ vaeskeygenassist %[rc], %[t], %[s]
                \\ vpslldq $4, %[tx], %[ts]
                \\ vpxor   %[ts], %[tx], %[r]
                \\ vpslldq $8, %[r], %[ts]
                \\ vpxor   %[ts], %[r], %[r]
                \\ vpshufd %[mask], %[s], %[ts]
                \\ vpxor   %[ts], %[r], %[r]
                : [r] "=&x" (-> Repr),
                  [s] "=&x" (s),
                  [ts] "=&x" (ts),
                : [rc] "n" (rc),
                  [t] "x" (t),
                  [tx] "x" (tx),
                  [mask] "n" (@as(u8, if (second) 0xaa else 0xff)),
            );
        }

        fn expand128(t1: *Block) Self {
            var round_keys: [11]Block = undefined;
            const rcs = [_]u8{ 1, 2, 4, 8, 16, 32, 64, 128, 27, 54 };
            inline for (rcs, 0..) |rc, round| {
                round_keys[round] = t1.*;
                t1.repr = drc(false, rc, t1.repr, t1.repr);
            }
            round_keys[rcs.len] = t1.*;
            return Self{ .round_keys = round_keys };
        }

        fn expand256(t1: *Block, t2: *Block) Self {
            var round_keys: [15]Block = undefined;
            const rcs = [_]u8{ 1, 2, 4, 8, 16, 32 };
            round_keys[0] = t1.*;
            inline for (rcs, 0..) |rc, round| {
                round_keys[round * 2 + 1] = t2.*;
                t1.repr = drc(false, rc, t2.repr, t1.repr);
                round_keys[round * 2 + 2] = t1.*;
                t2.repr = drc(true, rc, t1.repr, t2.repr);
            }
            round_keys[rcs.len * 2 + 1] = t2.*;
            t1.repr = drc(false, 64, t2.repr, t1.repr);
            round_keys[rcs.len * 2 + 2] = t1.*;
            return Self{ .round_keys = round_keys };
        }

        /// Invert the key schedule.
        pub fn invert(key_schedule: Self) Self {
            const round_keys = &key_schedule.round_keys;
            var inv_round_keys: [rounds + 1]Block = undefined;
            inv_round_keys[0] = round_keys[rounds];
            comptime var i = 1;
            inline while (i < rounds) : (i += 1) {
                inv_round_keys[i] = Block{
                    .repr = asm (
                        \\ vaesimc %[rk], %[inv_rk]
                        : [inv_rk] "=x" (-> Repr),
                        : [rk] "x" (round_keys[rounds - i].repr),
                    ),
                };
            }
            inv_round_keys[rounds] = round_keys[0];
            return Self{ .round_keys = inv_round_keys };
        }
    };
}

/// A context to perform encryption using the standard AES key schedule.
pub fn AesEncryptCtx(comptime Aes: type) type {
    std.debug.assert(Aes.key_bits == 128 or Aes.key_bits == 256);
    const rounds = Aes.rounds;

    return struct {
        const Self = @This();
        pub const block = Aes.block;
        pub const block_length = block.block_length;
        key_schedule: KeySchedule(Aes),

        /// Create a new encryption context with the given key.
        pub fn init(key: [Aes.key_bits / 8]u8) Self {
            var t1 = Block.fromBytes(key[0..16]);
            const key_schedule = if (Aes.key_bits == 128) ks: {
                break :ks KeySchedule(Aes).expand128(&t1);
            } else ks: {
                var t2 = Block.fromBytes(key[16..32]);
                break :ks KeySchedule(Aes).expand256(&t1, &t2);
            };
            return Self{
                .key_schedule = key_schedule,
            };
        }

        /// Encrypt a single block.
        pub fn encrypt(ctx: Self, dst: *[16]u8, src: *const [16]u8) void {
            const round_keys = ctx.key_schedule.round_keys;
            var t = Block.fromBytes(src).xorBlocks(round_keys[0]);
            comptime var i = 1;
            inline while (i < rounds) : (i += 1) {
                t = t.encrypt(round_keys[i]);
            }
            t = t.encryptLast(round_keys[rounds]);
            dst.* = t.toBytes();
        }

        /// Encrypt+XOR a single block.
        pub fn xor(ctx: Self, dst: *[16]u8, src: *const [16]u8, counter: [16]u8) void {
            const round_keys = ctx.key_schedule.round_keys;
            var t = Block.fromBytes(&counter).xorBlocks(round_keys[0]);
            comptime var i = 1;
            inline while (i < rounds) : (i += 1) {
                t = t.encrypt(round_keys[i]);
            }
            t = t.encryptLast(round_keys[rounds]);
            dst.* = t.xorBytes(src);
        }

        /// Encrypt multiple blocks, possibly leveraging parallelization.
        pub fn encryptWide(ctx: Self, comptime count: usize, dst: *[16 * count]u8, src: *const [16 * count]u8) void {
            const round_keys = ctx.key_schedule.round_keys;
            var ts: [count]Block = undefined;
            comptime var j = 0;
            inline while (j < count) : (j += 1) {
                ts[j] = Block.fromBytes(src[j * 16 .. j * 16 + 16][0..16]).xorBlocks(round_keys[0]);
            }
            comptime var i = 1;
            inline while (i < rounds) : (i += 1) {
                ts = Block.parallel.encryptWide(count, ts, round_keys[i]);
            }
            ts = Block.parallel.encryptLastWide(count, ts, round_keys[i]);
            j = 0;
            inline while (j < count) : (j += 1) {
                dst[16 * j .. 16 * j + 16].* = ts[j].toBytes();
            }
        }

        /// Encrypt+XOR multiple blocks, possibly leveraging parallelization.
        pub fn xorWide(ctx: Self, comptime count: usize, dst: *[16 * count]u8, src: *const [16 * count]u8, counters: [16 * count]u8) void {
            const round_keys = ctx.key_schedule.round_keys;
            var ts: [count]Block = undefined;
            comptime var j = 0;
            inline while (j < count) : (j += 1) {
                ts[j] = Block.fromBytes(counters[j * 16 .. j * 16 + 16][0..16]).xorBlocks(round_keys[0]);
            }
            comptime var i = 1;
            inline while (i < rounds) : (i += 1) {
                ts = Block.parallel.encryptWide(count, ts, round_keys[i]);
            }
            ts = Block.parallel.encryptLastWide(count, ts, round_keys[i]);
            j = 0;
            inline while (j < count) : (j += 1) {
                dst[16 * j .. 16 * j + 16].* = ts[j].xorBytes(src[16 * j .. 16 * j + 16]);
            }
        }
    };
}

/// A context to perform decryption using the standard AES key schedule.
pub fn AesDecryptCtx(comptime Aes: type) type {
    std.debug.assert(Aes.key_bits == 128 or Aes.key_bits == 256);
    const rounds = Aes.rounds;

    return struct {
        const Self = @This();
        pub const block = Aes.block;
        pub const block_length = block.block_length;
        key_schedule: KeySchedule(Aes),

        /// Create a decryption context from an existing encryption context.
        pub fn initFromEnc(ctx: AesEncryptCtx(Aes)) Self {
            return Self{
                .key_schedule = ctx.key_schedule.invert(),
            };
        }

        /// Create a new decryption context with the given key.
        pub fn init(key: [Aes.key_bits / 8]u8) Self {
            const enc_ctx = AesEncryptCtx(Aes).init(key);
            return initFromEnc(enc_ctx);
        }

        /// Decrypt a single block.
        pub fn decrypt(ctx: Self, dst: *[16]u8, src: *const [16]u8) void {
            const inv_round_keys = ctx.key_schedule.round_keys;
            var t = Block.fromBytes(src).xorBlocks(inv_round_keys[0]);
            comptime var i = 1;
            inline while (i < rounds) : (i += 1) {
                t = t.decrypt(inv_round_keys[i]);
            }
            t = t.decryptLast(inv_round_keys[rounds]);
            dst.* = t.toBytes();
        }

        /// Decrypt multiple blocks, possibly leveraging parallelization.
        pub fn decryptWide(ctx: Self, comptime count: usize, dst: *[16 * count]u8, src: *const [16 * count]u8) void {
            const inv_round_keys = ctx.key_schedule.round_keys;
            var ts: [count]Block = undefined;
            comptime var j = 0;
            inline while (j < count) : (j += 1) {
                ts[j] = Block.fromBytes(src[j * 16 .. j * 16 + 16][0..16]).xorBlocks(inv_round_keys[0]);
            }
            comptime var i = 1;
            inline while (i < rounds) : (i += 1) {
                ts = Block.parallel.decryptWide(count, ts, inv_round_keys[i]);
            }
            ts = Block.parallel.decryptLastWide(count, ts, inv_round_keys[i]);
            j = 0;
            inline while (j < count) : (j += 1) {
                dst[16 * j .. 16 * j + 16].* = ts[j].toBytes();
            }
        }
    };
}

/// AES-128 with the standard key schedule.
pub const Aes128 = struct {
    pub const key_bits: usize = 128;
    pub const rounds = ((key_bits - 64) / 32 + 8);
    pub const block = Block;

    /// Create a new context for encryption.
    pub fn initEnc(key: [key_bits / 8]u8) AesEncryptCtx(Aes128) {
        return AesEncryptCtx(Aes128).init(key);
    }

    /// Create a new context for decryption.
    pub fn initDec(key: [key_bits / 8]u8) AesDecryptCtx(Aes128) {
        return AesDecryptCtx(Aes128).init(key);
    }
};

/// AES-256 with the standard key schedule.
pub const Aes256 = struct {
    pub const key_bits: usize = 256;
    pub const rounds = ((key_bits - 64) / 32 + 8);
    pub const block = Block;

    /// Create a new context for encryption.
    pub fn initEnc(key: [key_bits / 8]u8) AesEncryptCtx(Aes256) {
        return AesEncryptCtx(Aes256).init(key);
    }

    /// Create a new context for decryption.
    pub fn initDec(key: [key_bits / 8]u8) AesDecryptCtx(Aes256) {
        return AesDecryptCtx(Aes256).init(key);
    }
};
