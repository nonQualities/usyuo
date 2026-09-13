# usyuo

High-performance, zero-copy `todo.txt` task engine implemented in C3.

---

## Overview

`usyuo` is a command-line interface (CLI) task management engine adhering to the `todo.txt` standard. The system executes query and mutation operations on structured text datasets without runtime heap fragmentation. It operates via a contiguous memory arena, integer-space calendar arithmetic, and arena-backed inverted indices, enforcing a strict bipartite boundary between its backend memory model and presentation layer.

---

## 1. Etymology and Design Principles

The name **usyuo** is derived from classical Japanese philology and classical Latin terminology.

### Historical Context: *Usuyō* (薄様 / うすよう)
In classical Japan, beginning in the Heian period, *usuyō* designated an ultra-thin, high-density parchment produced from wild mountain gampi fibers (*gampishi*). Due to extensive beating of the bast fibers, the resulting paper possessed minimal physical thickness and weight while exhibiting high tensile strength, resistance to tearing, and sharp ink absorption without feathering. It was utilized by administrators, scholars, and officials for pocket memoranda, sequential ledgers, and official dispatches.

*(A brief reflection: a millennium of technological development, and humanity went from carrying pocket-sized gampi leaves to requiring two gigabytes of browser engine to display a checkbox. Progress is rarely linear.)*

### Linguistic Resonance: *Ūsus*
The designation simultaneously aligns with classical Latin *ūsus* (practice, application, utility), emphasizing functional execution over structural abstraction.

### Architectural Mapping
The physical and linguistic attributes correspond directly to the technical architecture of `usyuo`:

* **Minimal Memory Overhead**: Eliminates dynamic heap allocation wrappers, individual string objects, and fragmented pointer graphs. The entire dataset resides in a single contiguous memory arena; tasks and metadata are represented as direct slices.
* **Plain-Text Persistence**: Employs the `todo.txt` format as an unadorned, durable storage standard, independent of proprietary database formats or volatile schemas.
* **Deterministic Execution**: Bounded $O(1)$ and $O(K)$ query operations executed over integer calendar values, maintaining bounded steady-state memory overhead throughout execution.

---

## 2. Memory Model and Data Representation

The engine eliminates localized heap allocations by ingesting datasets into a contiguous memory block and slicing tokens using pointer-and-length references.

### Contiguous Virtual Memory Arena
1. The active workspace file is loaded into a single contiguous byte buffer managed by `MemoryArena`.
2. Memory allocations within the arena occur via an 8-byte aligned bump allocator. The allocation offset moves strictly forward; like software deadlines, the arena does not look back.
3. Strings are represented using C3's native `String` type (`{ char* ptr, usz len }`), referencing sub-slices of the arena buffer directly. In the most literal technical sense, there are no strings attached—merely an 8-byte pointer with commitment issues and an 8-byte length.

```
Contiguous Virtual Memory Arena
+-------------------------------------------------------------------------------+
| Line 0: (A) 2026-09-14 Review architecture docs +Core @Meeting due:2026-09-15\n|
| Line 1: (B) Implement parser regression test +Engine due:2026-09-16\n          |
| Line 2: x 2026-09-13 Fix terminal escape sequence +UI\n                       |
| [ Unallocated Capacity / Dynamic Mutation Appends ...........................]|
+-------------------------------------------------------------------------------+
  ^                      ^
  |-- raw_line slice ----| (char* ptr, usz len)
```

### Task Struct Layout
The core abstract syntax tree (AST) node is defined as a fixed 48-byte record in `backend::ast`:

```c3
struct Task
{
    int id;                 // 1-based operational index
    bool completed;         // true if prefixed with 'x '
    char priority;          // 'A'..'Z' or 0 if unprioritized
    int completion_jdn;     // Julian Day Number of completion, or 0
    int creation_jdn;       // Julian Day Number of creation, or 0
    int due_jdn;            // Julian Day Number from due:YYYY-MM-DD, or 0
    String raw_line;        // Full original line slice in arena
    String description;     // Task body text slice (excluding tags/dates)
}
```

#### Memory Alignment Specification (64-bit Architecture):
| Offset (Bytes) | Field | Type | Size (Bytes) | Description |
| :--- | :--- | :--- | :--- | :--- |
| `0x00` | `id` | `int` | 4 | 1-based operational index |
| `0x04` | `completed` | `bool` | 1 | Completion status marker |
| `0x05` | `priority` | `char` | 1 | Priority ASCII character |
| `0x06` | *(padding)* | — | 2 | Alignment padding |
| `0x08` | `completion_jdn`| `int` | 4 | Integer completion date |
| `0x0C` | `creation_jdn`  | `int` | 4 | Integer creation date |
| `0x10` | `due_jdn`       | `int` | 4 | Integer due date |
| `0x14` | *(padding)* | — | 4 | Alignment padding |
| `0x18` | `raw_line`      | `String` | 16 | Slice referencing arena line (`ptr` + `len`) |
| `0x28` | `description`   | `String` | 16 | Slice referencing task text (`ptr` + `len`) |
| **Total** | | | **48** | |

---

## 3. Temporal Engine and Calendar Arithmetic

To guarantee constant-time temporal query evaluation, ISO 8601 calendar strings (`YYYY-MM-DD`) are mapped to integer Julian Day Numbers (JDN) during initial lexical analysis. String processing at query time is strictly prohibited.

*(Dating is notoriously difficult, but string-based calendar comparisons inside an interactive query loop are pure self-inflicted heartbreak. Integers don't lie, and they don't allocate.)*

### Gregorian Calendar to Julian Day Number (Fliegel-van Flandern)
For a given Gregorian calendar date with Year $Y$, Month $M \in [1, 12]$, and Day $D \in [1, 31]$:

$$a = \left\lfloor \frac{14 - M}{12} \right\rfloor$$

$$y = Y + 4800 - a$$

$$m = M + 12a - 3$$

$$\text{JDN} = D + \left\lfloor \frac{153m + 2}{5} \right\rfloor + 365y + \left\lfloor \frac{y}{4} \right\rfloor - \left\lfloor \frac{y}{100} \right\rfloor + \left\lfloor \frac{y}{400} \right\rfloor - 32045$$

This mapping is strictly monotonic: $\text{JDN}(d + 1) - \text{JDN}(d) = 1$ across all calendar dates.

### Julian Day Number to Gregorian Calendar (Richards-Hatcher)
The inverse transformation converts an integer JDN back to $(Y, M, D)$ coordinates in $O(1)$ without table lookups:

$$l = \text{JDN} + 68569$$

$$n = \left\lfloor \frac{4l}{146097} \right\rfloor$$

$$l = l - \left\lfloor \frac{146097n + 3}{4} \right\rfloor$$

$$i = \left\lfloor \frac{4000(l + 1)}{1461001} \right\rfloor$$

$$l = l - \left\lfloor \frac{1461i}{4} \right\rfloor + 31$$

$$j = \left\lfloor \frac{80l}{2447} \right\rfloor$$

$$D = l - \left\lfloor \frac{2447j}{80} \right\rfloor$$

$$l = \left\lfloor \frac{j}{11} \right\rfloor$$

$$M = j + 2 - 12l$$

$$Y = 100(n - 49) + i + l$$

### Temporal Query Semantics
* **Effective Date Resolution**: Evaluates `due_jdn` if present; falls back to `creation_jdn`.
* **Date Equality**: Evaluated as `effective_jdn == query_jdn` in $O(1)$ integer operations.
* **Interval Bounds**: Evaluated as `start_jdn <= effective_jdn && effective_jdn <= end_jdn` in $O(1)$ integer operations.

---

## 4. Indexing Engine and Query Complexity

The engine populates two in-memory indices during file ingestion to bypass linear scanning on query operations.

For twenty tasks, a linear scan ($O(N)$) is unnoticeable. For twenty thousand uncompleted tasks, the user does not need a faster scanner—they need to reconsider their commitments. Regardless, the inverted index ensures the CPU does not suffer alongside them.

```
Inverted Index (Tag -> Posting List)
Key: String (Arena Slice)  -> Head Pointer: PostingNode*
  "@Meeting"               -> [Task 1] -> [Task 4] -> null
  "+Core"                  -> [Task 1] -> [Task 2] -> null

Temporal Index (JDN -> Posting List)
Key: int (JDN)             -> Head Pointer: PostingNode*
  2461298                  -> [Task 1] -> [Task 3] -> null
```

### Data Structures
Index nodes are allocated directly within the contiguous `MemoryArena`:

```c3
struct PostingNode
{
    int task_id;
    PostingNode* next;
}
```

* `InvertedIndex`: Hash map mapping tag slices (`String`) to `PostingNode*`.
* `TemporalIndex`: Hash map mapping integer `int` (JDN) to `PostingNode*`.

### Algorithmic Complexities
| Operation | Target | Algorithm | Time Complexity | Auxiliary Space |
| :--- | :--- | :--- | :--- | :--- |
| File Ingestion | Workspace | Single-pass lexical scan | $O(N)$ | $O(N)$ contiguous arena |
| Index Construction | Tag / JDN | Prepend to linked list | $O(1)$ per token | $O(1)$ per posting node |
| Tag Query | `@ctx` / `+proj` | Hash lookup + list traversal | $O(1 + K)$ | $O(1)$ |
| Temporal Query | `today` / Date | Hash lookup + list traversal | $O(1 + K)$ | $O(1)$ |
| Task Completion | `done <id>` | In-place record mutation | $O(1)$ | $O(1)$ |
| Workspace Persistence| Disk | Single-pass serialization | $O(N)$ | $O(1)$ |

*(Where $N$ is the total number of tasks, and $K$ is the number of matching tasks returned).*

---

## 5. Storage Architecture and Persistence Protocol

### XDG Base Directory Compliance
`usyuo` complies with the XDG Base Directory Specification:
* **Canonical Storage Path**: `$XDG_DATA_HOME/usyuo/todo.txt` (defaulting to `$HOME/.local/share/usyuo/todo.txt`).
* **Environment Fallback**: If the user home directory or XDG path is mounted read-only, the engine transparently falls back to `./usyuo_data/todo.txt`.

### External Workspace Isolation (FR-1)
When invoked with an external file argument outside the canonical directory:
```bash
usyuo /path/to/external_tasks.txt
```
The file is copied into `$XDG_DATA_HOME/usyuo/external_tasks.txt` prior to loading. The engine mounts the local copy, preventing uncoordinated in-place modifications to external storage.

### Deferred Persistence Protocol
1. Ingestion loads and indexes the file in memory. Disk handles are closed immediately after reading.
2. Mutation commands (`add`, `done`) modify the in-memory AST and set a workspace `dirty` flag.
3. Disk writes occur only upon:
   * Explicit execution of the `save` command.
   * Orderly termination via `exit` or `quit`.
   * Interception of POSIX `SIGINT` (`Ctrl+C`), handled by `handle_sigint` to flush pending changes via `O_TRUNC` before process termination.

The persistence layer operates on a principle of disciplined laziness: we refuse to thrash the disk on every keystroke, but we guard against abrupt termination. When the user hits `Ctrl+C` in an existential panic, `handle_sigint` catches the signal and commits the state before the kernel pulls the plug.

---

## 6. Terminal Presentation and Execution Loop

### Terminal Capability Detection
The engine queries file descriptor 1 via POSIX `libc::isatty(1)`:
* **TTY Mode**: Formats task components with ANSI escape codes.
* **Non-TTY Mode (Piped/Redirected)**: Emits raw ASCII text without escape characters.

### Streaming Token Colorization
The presentation layer implements a single-pass streaming colorizer (`presentation::tty`). The raw line slice is scanned and emitted directly to the standard output stream without intermediate string formatting allocations:
* **Priority `(A)`**: Bold Red (`\e[1;31m`)
* **Priority `(B)`**: Bold Yellow (`\e[1;33m`)
* **Priority `(C)`**: Bold Cyan (`\e[1;36m`)
* **Projects (`+Project`)**: Magenta (`\e[35m`)
* **Contexts (`@Context`)**: Cyan (`\e[36m`)
* **Due Dates (`due:YYYY-MM-DD`)**: Bold Yellow (`\e[1;33m`)
* **Completed Tasks**: Dim Strikethrough (`\e[2;9m`)

### REPL Memory Boundary
The interactive loop in `src/main.c3` executes inside a C3 `@pool()` block. Transient memory allocated for user command input parsing is reclaimed after each iteration, maintaining bounded memory consumption across long-running sessions.

---

## 7. Modular System Architecture

The codebase enforces a bipartite boundary between the backend memory model and the presentation layer:

```
src/
├── backend/
│   ├── ast.c3            # Task struct (48 bytes) and JDN arithmetic
│   ├── arena.c3          # MemoryArena bump allocator and slice management
│   ├── parser.c3         # Single-pass lexical scanner and ISO 8601 parser
│   ├── index.c3          # InvertedIndex and TemporalIndex (PostingNode)
│   └── storage.c3        # XDG directory resolution and serialization
├── presentation/
│   ├── tty.c3            # Terminal detection (isatty) and streaming ANSI colorizer
│   └── repl.c3           # REPL state, command tokenizer, and dispatcher
└── main.c3               # Application entry point, CLI args, and SIGINT handler
```

### Module Responsibilities:

| Module | Source File | Description |
| :--- | :--- | :--- |
| `backend::ast` | `src/backend/ast.c3` | Abstract syntax definitions and calendar arithmetic algorithms. |
| `backend::arena` | `src/backend/arena.c3` | Memory arena management, bump allocation, and string buffer growth. |
| `backend::parser` | `src/backend/parser.c3` | Lexical analysis of `todo.txt` syntax into zero-copy slices. |
| `backend::index` | `src/backend/index.c3` | Inverted tag and temporal posting list construction and query. |
| `backend::storage` | `src/backend/storage.c3` | File ingestion, XDG path resolution, and atomic serialization. |
| `presentation::tty` | `src/presentation/tty.c3` | Terminal capability detection and streaming ANSI formatting. |
| `presentation::repl` | `src/presentation/repl.c3` | Interactive command dispatching and output coordination. |
| `usyuo` | `src/main.c3` | Top-level initialization, signal setup, and main execution loop. |

---

## 8. Compilation and Installation

### Requirements
* C3 Compiler (`c3c`) version 0.8.x
* GNU Make or compatible build utility
* POSIX-compliant C standard library (`libc`)

### Build Targets

```bash
# Compile optimized binary
make build

# Execute automated tests
make test

# Launch REPL with default XDG workspace
make run

# Clean build artifacts
make clean
```

---

## 9. REPL Command Reference

| Command | Syntax | Operational Description | Complexity |
| :--- | :--- | :--- | :--- |
| `list` | `list [all\|done\|pending]` | Traverses and displays tasks. Defaults to `pending`. | $O(N)$ |
| `today` | `today` | Queries index for tasks due on or assigned to current system JDN. | $O(1 + K)$ |
| `tag` | `tag <@context\|+project\|tag>` | Queries inverted index for exact tag match. | $O(1 + K)$ |
| `add` | `add <task_description>` | Appends raw task to arena, parses record, updates indices. | $O(L)$ |
| `done` | `done <task_id>` | Mutates task to completed status and prepends completion date. The closest a terminal user gets to closure. | $O(1)$ |
| `save` | `save` | Serializes dirty in-memory state to disk via `O_TRUNC`. | $O(N)$ |
| `help` | `help` | Outputs REPL command reference. | $O(1)$ |
| `exit` / `quit` | `exit` | Serializes changes if dirty and terminates execution. | $O(N)$ or $O(1)$ |
