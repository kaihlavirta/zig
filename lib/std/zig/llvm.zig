pub const BitcodeReader = @import("llvm/BitcodeReader.zig");
pub const bitcode_writer = @import("llvm/bitcode_writer.zig");
pub const Builder = @import("llvm/Builder.zig");

test {
    _ = BitcodeReader;
    _ = bitcode_writer;
    _ = Builder;
}
