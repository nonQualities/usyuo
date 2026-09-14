module test_arena;
import backend::arena;
import std::io;

fn int main()
{
    io::printn("=== Testing Your MemoryArena ===");

    backend::arena::MemoryArena arena;
    arena.init(1024);

    // Test 1: Initialization floor
    if (arena.bfr == null)
    {
        io::printn("FAIL: arena.bfr is null");
        return 1;
    }
    if (arena.capacity != 65536)
    {
        io::printfn("FAIL: expected minimum capacity 65536, got %d", arena.capacity);
        return 1;
    }
    if (arena.used != 0)
    {
        io::printfn("FAIL: expected used 0, got %d", arena.used);
        return 1;
    }
    io::printn("PASS: [1/4] init() respects 64KB minimum floor!");

    // Test 2: bump_alloc alignment test
    // Request 13 bytes -> should align to 16 bytes
    void* p1 = arena.bump_alloc(13);
    if (arena.used != 16)
    {
        io::printfn("FAIL: expected arena.used to be 16 after 13 bytes, got %d", arena.used);
        return 1;
    }

    // Request 1 byte -> should align to 8 bytes (used becomes 24)
    void* p2 = arena.bump_alloc(1);
    if (arena.used != 24)
    {
        io::printfn("FAIL: expected arena.used to be 24 after 1 byte, got %d", arena.used);
        return 1;
    }
    io::printn("PASS: [2/4] bump_alloc() enforces strict 8-byte alignment!");

    // Test 3: append_string test
    String s = arena.append_string("Hello Zero-Copy!");
    if (s != "Hello Zero-Copy!")
    {
        io::printfn("FAIL: string content mismatch: '%s'", s);
        return 1;
    }
    // Verify slice points directly inside the arena buffer
    if ((char*)s.ptr < arena.bfr || (char*)s.ptr >= arena.bfr + arena.used)
    {
        io::printn("FAIL: string slice does not reside inside arena buffer!");
        return 1;
    }
    io::printn("PASS: [3/4] append_string() stores zero-copy string inside arena!");

    // Test 4: free
    arena.free();
    if (arena.bfr != null || arena.capacity != 0 || arena.used != 0)
    {
        io::printn("FAIL: free did not reset arena state");
        return 1;
    }
    io::printn("PASS: [4/4] free() cleanly released resources!");

    io::printn("=================================");
    io::printn(" ALL TESTS PASSED! YOUR ARENA IS ROCK SOLID! ");
    io::printn("=================================");
    return 0;
}
