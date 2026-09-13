# 07: Step-by-Step Implementation & Build Guide

This hands-on guide walks you through building the multi-file, zero-copy `usyuo` engine step-by-step from scratch. Follow each phase to implement, test, and verify every component of the system.

---

## Phase 1: Project Setup & Baseline Verification

### Objective:
Verify compiler installation, multi-file directory layout, and initial build target.

### Step 1.1: Verify C3 Compiler & Standard Library
Run the compiler check:
```bash
c3c --version
```
Expected output: C3 compiler version 0.8.x.

### Step 1.2: Multi-File Directory Layout
```
src/
├── backend/
│   ├── ast.c3            # struct Task, JDN arithmetic
│   ├── arena.c3          # MemoryArena, bump allocation, zero-copy append
│   ├── parser.c3         # Strict todo.txt grammar scanner, ISO date parser
│   ├── index.c3          # InvertedIndex & TemporalIndex with PostingNode
│   └── storage.c3        # Workspace, XDG paths, ingestion, deferred write
├── presentation/
│   ├── tty.c3            # is_stdout_tty, streaming ANSI token colorizer
│   └── repl.c3           # ReplState, command dispatcher, @pool() memory loop
└── main.c3               # CLI entry point, argument parsing, SIGINT handler
```

### Step 1.3: Build the Project
Run `make build` from the project root:
```bash
make build
```
Verify that the binary `./usyuo` is produced without errors or warnings.

### Step 1.4: Run the Help Command
```bash
./usyuo --help
```
You should see the usage banner.

---

## Phase 2: Memory Arena & Zero-Copy Slicing

### Objective:
Implement `src/backend/arena.c3` to allocate a single contiguous memory block for workspace data, completely bypassing per-token heap allocations.

### Key Concepts:
* Slices in C3 (`String` / `char[]`) are fat pointers: `{ ptr: char*, len: usz }`.
* Substring slicing in C3 uses `buffer[start : length]`.
* Slicing creates a pointer reference without invoking `malloc`.

### Implementation Checklist:
1. Define `struct MemoryArena { char* buffer; usz capacity; usz used; }`.
2. In `MemoryArena.init`, allocate `buffer` with `mem::alloc_array(char, (sz)capacity)`.
3. In `MemoryArena.alloc_bytes(usz bytes)`, bump-allocate aligned memory for posting nodes.
4. In `MemoryArena.append_string`, check if `used + len + 1 > capacity`. If so, double the capacity using `mem::realloc`.
5. Copy bytes with `mem::copy`, append `\0`, and return `(String)dest[0 : text.len]`.
6. Implement `MemoryArena.free` to release the entire buffer at shutdown with a single `mem::free(self.buffer)`.

---

## Phase 3: Julian Day Number (JDN) Temporal Engine

### Objective:
Implement arithmetic mapping of `YYYY-MM-DD` strings to 32-bit integer JDNs in `src/backend/ast.c3`, strictly forbidding string-based date comparisons.

### Implementation Checklist:
1. Implement `date_to_jdn(int year, int month, int day) -> int`:
   ```c
   fn int date_to_jdn(int year, int month, int day)
   {
       int a = (14 - month) / 12;
       int y = year + 4800 - a;
       int m = month + 12 * a - 3;
       return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045;
   }
   ```
2. Implement `jdn_to_date(int jdn, int* year, int* month, int* day)` using the Richards-Hatcher inversion.
3. Implement `Task.get_effective_jdn()` to prioritize `due_jdn` with fallback to `creation_jdn`.

---

## Phase 4: Strict `todo.txt` Lexical Scanner

### Objective:
Implement `src/backend/parser.c3` to scan each line in $O(N)$ time into the 48-byte `Task` struct.

### Implementation Checklist:
1. Check leading `x ` for completion status (`task.completed = true`).
2. Check `(A) ` .. `(Z) ` for priority (`task.priority = rem[1]`).
3. Parse leading ISO 8601 dates:
   * If completed: first date is `completion_jdn`, optional second date is `creation_jdn`.
   * If incomplete: first date is `creation_jdn`.
4. Scan description for `due:YYYY-MM-DD` to populate `task.due_jdn`.

---

## Phase 5: Inverted Index & Temporal Index with `PostingNode`

### Objective:
Implement `src/backend/index.c3` to provide $O(K)$ query operations using arena-backed posting nodes.

### Implementation Checklist:
1. Define `struct PostingNode { int task_id; PostingNode* next; }`.
2. In `InvertedIndex.insert`:
   * Bump-allocate `PostingNode` in the arena.
   * Prepend node to the tag's linked list in $O(1)$ time.
3. In `TemporalIndex.insert`:
   * Prepend node to the JDN's linked list in $O(1)$ time.
4. Traversal: Walk `node = node.next` to visit all $K$ matching tasks without linear scanning.

---

## Phase 6: Storage, XDG Compliance & Deferred Persistence

### Objective:
Implement `src/backend/storage.c3` to manage workspace discovery, file isolation, and deferred file flushing.

### Implementation Checklist:
1. `resolve_xdg_directory`: probe `$XDG_DATA_HOME/usyuo`, fallback to `~/.local/share/usyuo`, with local `./usyuo_data` fallback for sandboxed/read-only environments.
2. `isolate_external_workspace`: copy external `.txt` files into XDG storage before mounting (FR-1).
3. `Workspace.load_from_file`:
   * Read raw file into `arena.buffer`.
   * Line-split and parse tasks into contiguous `tasks` array (`List{Task}`).
   * Populate inverted and temporal indices.
   * Set `dirty = false`.
4. `Workspace.save_if_dirty`:
   * If `!dirty`, return immediately (zero disk I/O).
   * Open with `"wb"` (`O_TRUNC`) and stream all `task.raw_line` items sequentially.
   * Set `dirty = false`.

---

## Phase 7: Interactive REPL & Single-Pass Streaming ANSI Formatting

### Objective:
Implement `src/presentation/tty.c3`, `src/presentation/repl.c3`, and `src/main.c3`.

### Implementation Checklist:
1. Terminal check: `libc::isatty(1) == 1`.
2. Streaming ANSI renderer:
   * Scan tokens on the fly from `task.description`.
   * Colorize `@contexts` (cyan), `+projects` (magenta), `due:` (bold yellow), tags (yellow), priorities (red/yellow/cyan).
   * Completed tasks rendered in dim strikethrough.
3. REPL loop:
   * Wrap each command in `@pool()` to guarantee $O(1)$ steady-state memory.
   * Read lines using `io::treadline(io::stdin())`.
4. Command dispatch:
   * `list`: iterate active tasks and format.
   * `today`: query temporal index for current system JDN in $O(K)$ time.
   * `tag <name>`: query inverted index for matching tasks in $O(K)$ time.
   * `add <text>`: append to arena, parse, index, set `dirty = true`.
   * `done <id>`: mark completed, inject date, set `dirty = true`.
   * `save`: flush dirty workspace.
   * `exit` / `quit`: flush dirty workspace and terminate.
5. Signal Handler:
   * Register `libc::signal(libc::SIGINT, &handle_sigint)`.
   * Trigger `save_if_dirty()` upon receiving `SIGINT`.

---

## Phase 8: End-to-End Verification Suite

Run the full interactive lifecycle test using piped stdin:

```bash
# 1. Compile the multi-file modular project
make build

# 2. Test piped execution with queries and mutations
printf "list\ntoday\ntag @backend\nadd (A) Test task +demo @test due:2026-09-13\ndone 1\ntoday\nexit\n" | ./usyuo resources/sample_todo.txt
```

### Verification Criteria:
1. All 10 tasks render cleanly with preserved word order and no duplicate tags.
2. `today` displays tasks with today's due date.
3. `tag @backend` displays exactly the tasks containing `@backend`.
4. `add` appends task #11 to the arena and updates indices.
5. `done 1` injects the completion timestamp `x YYYY-MM-DD`.
6. `exit` writes the updated workspace back to disk with `O_TRUNC`.
