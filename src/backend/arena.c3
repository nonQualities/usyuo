
module backend::arena;
import std::io;

<*
 * Contiguous memory arena.
 * Ingested file contents and dynamically added task strings are stored here.
 * Slices (String) directly point into this buffer without independent heap allocations.
 *>
struct MemoryArena
{
    char* buffer;
    usz capacity;
    usz used;
}

<*
 * Initializes an arena with a pre-allocated capacity.
 *>
fn void MemoryArena.init(&self, usz initial_capacity = 1048576)
{
    self.capacity = initial_capacity > 65536 ? initial_capacity : 65536;
    self.buffer = (char*)mem::alloc_array(char, (sz)self.capacity);
    self.used = 0;
}

<*
 * Frees the entire arena buffer in a single operation.
 *>
fn void MemoryArena.free(&self)
{
    if (self.buffer != null)
    {
        mem::free(self.buffer);
        self.buffer = null;
        self.capacity = 0;
        self.used = 0;
    }
}

<*
 * Bump-allocates raw aligned memory from the arena.
 *>
fn void* MemoryArena.alloc_bytes(&self, usz bytes)
{
    // Align to 8-byte boundary
    usz aligned_bytes = (bytes + 7) & ~7;
    usz required = self.used + aligned_bytes;
    if (required > self.capacity)
    {
        usz new_cap = self.capacity * 2;
        if (new_cap < required) new_cap = required + 65536;
        self.buffer = (char*)mem::realloc(self.buffer, (sz)new_cap);
        self.capacity = new_cap;
    }
    void* ptr = self.buffer + self.used;
    self.used += aligned_bytes;
    return ptr;
}

<*
 * Appends raw bytes (e.g. from an `add` command) into the arena and returns
 * a zero-copy String slice. Reallocates buffer if required.
 *>
fn String MemoryArena.append_string(&self, String text)
{
    usz required = self.used + text.len + 1;
    if (required > self.capacity)
    {
        usz new_cap = self.capacity * 2;
        if (new_cap < required) new_cap = required + 65536;
        self.buffer = (char*)mem::realloc(self.buffer, (sz)new_cap);
        self.capacity = new_cap;
    }
    char* dest = self.buffer + self.used;
    mem::copy(dest, text.ptr, text.len);
    dest[text.len] = 0;
    self.used += text.len + 1;
    return (String)dest[0 : text.len];
}
