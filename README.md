# usyuo: Unified Sequential Year-mapped User Organizer

`usyuo` is a terminal-based, zero-copy `todo.txt` task engine implemented in C3. The system executes query and mutation operations on structured text datasets without heap fragmentation, utilizing a contiguous memory arena, an integer-space temporal mapping engine, and arena-backed inverted indices.

---

## 1. System Architecture & Memory Model

The architecture enforces a strict bipartite boundary between the backend memory model (`backend::*`) and the presentation layer (`presentation::*`).

```
+-------------------------------------------------------------------------+
|                                  usyuo                                  |
|                                                                         |
|  +---------------------------+       +-------------------------------+  |
|  |     Presentation Layer    |       |      Backend Memory Model     |  |
|  |                           |       |                               |  |
|  |   presentation::tty       |       |   backend::ast                |  |
|  |   presentation::repl      |       |   backend::arena              |  |
|  |                           |       |   backend::parser             |  |
|  |                           |       |   backend::index              |  |
|  |                           |       |   backend::storage            |  |
|  +-------------+-------------+       +---------------+---------------+  |
|                ^                                     ^                  |
|                |                                     |                  |
|                +------------------+------------------+                  |
|                                   |                                     |
|                       +-----------+-----------+                         |
|                       |      module usyuo     |                         |
|                       |   (CLI Entry Point)   |                         |
|                       +-----------------------+                         |
+-------------------------------------------------------------------------+
```

### Zero-Copy Memory Arena
* **Contiguous Virtual Memory**: The active workspace file is ingested in a single read into a contiguous byte buffer managed by `MemoryArena`.
* **Pointer-and-Length Slices**: Task descriptions, project identifiers (`+Project`), context identifiers (`@Context`), and key-value tags (`key:value`) are represented as C3 `String` slices (`char[]`), referencing the contiguous arena buffer directly without secondary heap string allocations.
* **Streamlined Task Representation**: The `Task` record is fixed at 48 bytes:
  ```c3
  struct Task
  {
      int id;                 // 1-based operational index
      bool completed;         // Boolean completion state ('x ')
      char priority;          // Uppercase priority ASCII ('A'..'Z' or 0)
      int completion_jdn;     // Julian Day Number of completion, or 0
      int creation_jdn;       // Julian Day Number of creation, or 0
      int due_jdn;            // Julian Day Number from due:YYYY-MM-DD, or 0
      String raw_line;        // Full line slice in the arena buffer
      String description;     // Body text slice in the arena buffer
  }
  ```
* **Contiguous Array Storage**: Tasks are stored sequentially in a dynamic array (`List{Task}`). Lookups by task ID evaluate via direct array indexing `tasks[(sz)(id - 1)]` in $O(1)$ time.

---

## 2. Temporal Mapping Engine (Julian Day Number)

To satisfy constant-time temporal query bounds, all ISO 8601 calendar dates (`YYYY-MM-DD`) are mapped to integer Julian Day Numbers (JDN) during the lexical scan. String-based date processing is forbidden at query time.

### Gregorian to JDN Conversion (Fliegel-Van Flandern Algorithm)
Given astronomical integer year $Y$, month $M \in [1, 12]$, and day $D \in [1, 31]$:

$$a = \left\lfloor \frac{14 - M}{12} \right\rfloor$$
$$y = Y + 4800 - a$$
$$m = M + 12a - 3$$
$$JDN = D + \left\lfloor \frac{153m + 2}{5} \right\rfloor + 365y + \left\lfloor \frac{y}{4} \right\rfloor - \left\lfloor \frac{y}{100} \right\rfloor + \left\lfloor \frac{y}{400} \right\rfloor - 32045$$

* The term $\lfloor(153m + 2)/5\rfloor$ accounts for the repeating five-month cycle of month lengths (31, 30, 31, 30, 31 days).
* Shifting January and February to months 10 and 11 of the preceding year places the leap day at the end of the calculation, ensuring strict mathematical monotonicity:
  $$JDN(date + 1) - JDN(date) \equiv 1$$

### JDN to Gregorian Inversion (Richards-Hatcher Algorithm)
For date serialization and timestamp generation:
$$l = JDN + 68569, \quad n = \left\lfloor \frac{4l}{146097} \right\rfloor, \quad l = l - \left\lfloor \frac{146097n + 3}{4} \right\rfloor$$
$$i = \left\lfloor \frac{4000(l + 1)}{1461001} \right\rfloor, \quad l = l - \left\lfloor \frac{1461i}{4} \right\rfloor + 31, \quad j = \left\lfloor \frac{80l}{2447} \right\rfloor$$
$$Day = l - \left\lfloor \frac{2447j}{80} \right\rfloor, \quad l = \left\lfloor \frac{j}{11} \right\rfloor, \quad Month = j + 2 - 12l, \quad Year = 100(n - 49) + i + l$$

### Query Bounds Complexity:
* **Today Query**: Evaluates as an integer equality check `task.effective_jdn == system_jdn`.
* **Range Query**: Evaluates as an arithmetic bounds check $JDN_{start} \le \text{task.effective\_jdn} \le JDN_{end}$.

---

## 3. Inverted & Temporal Indexing Engine

To prevent $O(M)$ linear scans over large datasets with $M$ tasks, the system builds two in-memory indices populated during parsing.

```
[Inverted Index: HashMap{String, PostingNode*}]
Key (String slice)   -> Head Pointer (PostingNode*)
------------------------------------------------------------------
"@backend"           -> [ Node: task_id=9 ] -> [ Node: task_id=3 ] -> [ Node: task_id=1 ] -> null
"+c3engine"          -> [ Node: task_id=1 ] -> null

[Temporal Index: HashMap{int, PostingNode*}]
Key (int JDN)        -> Head Pointer (PostingNode*)
------------------------------------------------------------------
2461298 (2026-09-14) -> [ Node: task_id=2 ] -> null
```

* **Arena-Backed Posting Lists**: Each posting record is a 16-byte node (`PostingNode { int task_id; PostingNode* next; }`) bump-allocated in the workspace memory arena.
* **Complexity Guarantees**:
  * Tag Insertion: Prepending to the posting list executes in $O(1)$ time with zero heap reallocations.
  * Tag Query: Hash table bucket resolution executes in $O(1)$ average time; traversing the posting list streams exactly the $K$ matching task records in $O(K)$ time ($K \ll M$).

---

## 4. Storage & Persistence Protocol

### XDG Base Directory Compliance
* Primary storage directory: `$XDG_DATA_HOME/usyuo/` (defaulting to `$HOME/.local/share/usyuo/`).
* Fallback: If parent directories are read-only (such as containerized sandbox environments), storage automatically falls back to `./usyuo_data`.

### Workspace Ingestion & Isolation (FR-1)
When initialized with an external file argument:
```bash
./usyuo /path/to/external_tasks.txt
```
The file is copied into `$XDG_DATA_HOME/usyuo/external_tasks.txt` prior to parsing, isolating the active workspace from foreign directory mutations.

### Deferred Serialization Protocol (FR-5)
* **Dirty Flag**: Any mutation (`add`, `done`) sets an in-memory boolean flag `workspace.dirty = true`.
* **Sequential Stream Flush**: Upon graceful termination (`exit`, `quit`) or receipt of `SIGINT` (Ctrl+C), if `dirty == true`, the active workspace file is opened with `O_TRUNC` and all task line records are written sequentially in a single continuous stream.

---

## 5. Terminal Presentation & Interactive REPL

* **Terminal Capability Detection**: Standard output is probed using POSIX `libc::isatty(1)`. When attached to a terminal, ANSI color sequences are enabled; when piped or redirected, plain text is emitted.
* **Single-Pass Streaming Colorizer**: The ANSI formatting engine scans the raw description slice in a single pass directly to the output stream, colorizing `@Context` in cyan, `+Project` in magenta, `due:YYYY-MM-DD` in bold yellow, priorities in bold red/yellow/cyan, and completed tasks in dim strikethrough.
* **Bounded REPL Memory**: Each iteration of the REPL loop is scoped with C3 `@pool()` blocks, ensuring transient memory from line tokenization is reclaimed each turn, maintaining $O(1)$ steady-state memory across indefinite uptime.

---

## 6. Directory Structure

```
todo_cli/
├── c3lib/                # Local C3 standard library modules
├── docs/                 # Detailed architectural specifications
│   ├── 00_architecture_overview.md
│   ├── 01_memory_model_and_zerocopy.md
│   ├── 02_todo_txt_grammar_and_parser.md
│   ├── 03_temporal_engine_and_jdn.md
│   ├── 04_indexing_and_query_complexity.md
│   ├── 05_storage_and_xdg_protocol.md
│   ├── 06_presentation_layer_and_repl.md
│   └── 07_step_by_step_build_guide.md
├── resources/            # Reference datasets
│   └── sample_todo.txt
├── src/                  # Multi-file source tree
│   ├── backend/
│   │   ├── arena.c3      # Contiguous memory arena & slice allocation
│   │   ├── ast.c3        # Task struct & Julian Day Number conversion
│   │   ├── index.c3      # Inverted & temporal indices with posting nodes
│   │   ├── parser.c3     # Linear single-pass todo.txt parser
│   │   └── storage.c3    # XDG directory management & deferred persistence
│   ├── presentation/
│   │   ├── repl.c3       # Interactive command tokenizer & dispatch loop
│   │   └── tty.c3        # Terminal detection & streaming ANSI formatter
│   └── main.c3           # Application entry point & SIGINT registration
├── Makefile              # Build automation targets
├── project.json          # C3 project configuration
└── README.md             # Technical documentation
```

---

## 7. Compilation & Build

### Prerequisites
* C3 Compiler (`c3c`) version 0.8.x
* POSIX-compliant host operating system (Linux / Unix)

### Build Targets
```bash
# Compile the usyuo binary
make build

# Execute interactive REPL with default XDG workspace
make run

# Execute interactive REPL with a specific workspace file
./usyuo resources/sample_todo.txt

# Run automated help/compilation test
make test

# Remove build artifacts and binaries
make clean
```

---

## 8. REPL Command Reference

| Command | Arguments | Description | Time Complexity |
| :--- | :--- | :--- | :--- |
| `list` / `ls` | None | Iterate and render all active tasks | $O(M)$ |
| `today` | None | Retrieve tasks matching current system JDN | $O(K)$ |
| `tag` | `<@context \| +project \| key:val>` | Query inverted index for matching tasks | $O(K)$ |
| `add` | `<raw todo.txt string>` | Append task to arena, parse, and update indices | $O(1)$ |
| `done` | `<task-id>` | Mark task completed and prepend completion date | $O(1)$ |
| `save` | None | Flush active workspace to disk immediately | $O(M)$ |
| `help` | None | Print command reference | $O(1)$ |
| `exit` / `quit` | None | Flush modifications if dirty and terminate | $O(M)$ or $O(1)$ |
