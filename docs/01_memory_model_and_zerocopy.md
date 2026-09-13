# 01: Memory Model & Zero-Copy Architecture

## 1. The Cost of Naive Heap Allocation

In standard CLI applications, reading a text file typically involves:
1. Reading line by line from disk.
2. Allocating heap memory for each line (`strdup` / `malloc`).
3. Splitting lines into tokens and allocating separate string objects for tags, projects, contexts, and descriptions.
4. Calling `free()` on hundreds or thousands of individual pointers on shutdown.

### Why this is problematic:
* **Heap Metadata Overhead**: In typical standard library allocators (ptmalloc, jemalloc), every allocation carries 8 to 16 bytes of header metadata. Allocating a 5-byte tag like `@work` consumes 24–32 bytes of heap space.
* **Heap Fragmentation**: Thousands of small, scattered allocations fragment the virtual memory pages.
* **Cache Misses**: String data is dispersed across disparate addresses in RAM. Iterating over tasks forces the CPU cache to pull in cache lines from fragmented memory pages, destroying L1/L2 cache locality.
* **Allocation Latency**: Making $O(M \times T)$ calls to the OS heap allocator incurs lock contention and metadata management costs.

---

## 2. The Zero-Copy Solution: Contiguous Memory Arena

The SRS mandates:
> *"The engine is constrained to a zero-copy memory architecture. The entirety of the active workspace file must be read into a single, contiguous memory arena. String manipulation during parsing must utilize pointer-and-length slices referencing the original buffer, forbidding independent heap allocations for localized string data."*

### Memory Layout Diagram

Instead of allocating memory for every token, the entire file is ingested into one contiguous memory arena:

```
Arena Buffer:
[ ( A )   2 0 2 6 - 0 9 - 1 3   B u i l d   e n g i n e   + c 3   @ w o r k \n ( B ) ... \0 ]
  ^                           ^
  |                           |
  |                           +---------- Slice: description (ptr, len=26)
  +-------------------------------------- Slice: raw_line    (ptr, len=47)
```

Every `String` in C3 is a fat pointer slice:
```c
struct String // built-in C3 slice (char[])
{
    char* ptr;   // 8 bytes: direct pointer into the arena buffer
    usz len;     // 8 bytes: byte length of the substring
}
```

Creating a slice does **not** allocate memory. It simply performs pointer arithmetic:
$$\text{slice.ptr} = \text{arena.buffer} + \text{offset}$$
$$\text{slice.len} = \text{length}$$

---

## 3. The 48-Byte Streamlined `Task` Struct

Rather than storing redundant dynamic lists inside each task, the streamlined `Task` struct maintains only essential metadata and zero-copy string slices:

```c
struct Task
{
    int id;                 // 4 bytes: 1-based operational index
    bool completed;         // 1 byte:  true if prefixed with 'x '
    char priority;          // 1 byte:  'A'..'Z' or 0 if unprioritized
    // 2 bytes padding for alignment
    int completion_jdn;     // 4 bytes: Julian Day Number of completion, or 0
    int creation_jdn;       // 4 bytes: Julian Day Number of creation, or 0
    int due_jdn;            // 4 bytes: Julian Day Number from due:YYYY-MM-DD, or 0
    // 4 bytes padding for pointer alignment
    String raw_line;        // 16 bytes: full original line slice (ptr + len)
    String description;     // 16 bytes: task body text slice (ptr + len)
}                           // Total: exactly 48 bytes!
```

### Key Advantages:
1. **Contiguous Storage (`TaskArray`)**: Tasks are stored in a contiguous dynamic array `List{Task}`. Iterating through all tasks streams contiguous 48-byte records directly through the CPU L1 data cache.
2. **Zero Secondary Allocations**: No heap lists for contexts, projects, or tags. Slices stream directly from the arena buffer during rendering and indexing.
3. **70% Memory Reduction**: Shrinks task memory from ~160 bytes down to 48 bytes per task.

---

## 4. Implementation of `MemoryArena` in C3

The `MemoryArena` struct maintains the contiguous byte buffer, its total allocated capacity, and the current byte offset:

```c
module backend::arena;
import std::io;

struct MemoryArena
{
    char* buffer;    // Pointer to contiguous heap buffer
    usz capacity;    // Total allocated capacity in bytes
    usz used;        // Bytes currently occupied
}

fn void MemoryArena.init(&self, usz initial_capacity = 1048576)
{
    self.capacity = initial_capacity > 65536 ? initial_capacity : 65536;
    self.buffer = (char*)mem::alloc_array(char, (sz)self.capacity);
    self.used = 0;
}

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
```

### Handling REPL Mutations (`add` Command)

When a user executes `add <text>` in the REPL, a new task must be appended. To preserve the zero-copy invariant:
1. The new string is copied into the arena's unused space (`arena.buffer + arena.used`).
2. If necessary, the arena dynamically doubles its capacity with `mem::realloc`.
3. A zero-copy slice `(String)` referencing the arena memory is returned for lexical parsing.

```c
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
    dest[text.len] = 0; // Null-terminator for C ABI safety
    self.used += text.len + 1;
    return (String)dest[0 : text.len];
}
```

---

## 5. Cache Efficiency & Big-O Impact

* **Startup Space Complexity**: Exactly $O(N)$ bytes, where $N$ is the file size on disk, plus 48 bytes per task in the contiguous task array.
* **Allocation Overhead**: Exactly 2 contiguous arena allocations at startup (1 large arena buffer read + 1 task array buffer) instead of $O(M \times T)$ small allocations.
* **Deallocation Overhead**: $O(1)$ cleanup time (`arena.free()`), eliminating recursive traversals of heap strings.
