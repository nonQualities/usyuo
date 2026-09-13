# 00: Architectural Overview & System Design

## 1. Introduction & Core Philosophy

The `usyuo` engine is designed to be a high-performance, terminal-based, zero-copy task management system adhering strictly to the `todo.txt` format. Rather than treating task management as a trivial script, the engine treats `todo.txt` as a high-throughput, structured in-memory database with deferred disk persistence.

### Key Architectural Tenets:
1. **Zero-Copy Memory Model**: File ingestion loads the workspace file into a single contiguous memory arena. Parsing slices the buffer using pointer-and-length references (`String` in C3, equivalent to `char[]`), completely eliminating heap allocations for task descriptions, tags, contexts, and projects.
2. **Integer-Space Temporal Engine**: Date strings formatted as `YYYY-MM-DD` are converted into Julian Day Numbers (JDN) immediately during the lexical scan. Queries for "today", "this week", or custom intervals execute as bounded integer comparisons ($O(1)$ or $O(K)$), completely forbidding string comparisons at query time.
3. **Inverted & Temporal Indexing**: To circumvent $O(N)$ linear scans across large task lists, tasks are indexed into hash-based inverted indices upon insertion, mapping tags (`@Context`, `+Project`, `key:value`) and JDN dates directly to task pointer arrays.
4. **Strict Bipartite Separation in a Multi-File Architecture**: The codebase is partitioned across dedicated modular files enforcing a strict bipartite boundary between the backend memory model (`src/backend/`) and presentation layer (`src/presentation/`).
5. **Deferred Persistence**: Disk I/O is separated from the interactive loop. Mutations mark an in-memory `dirty` flag; serialization only occurs on explicit save, graceful exit, or `SIGINT` interruption.

---

## 2. Multi-File Modular Architecture

The codebase organizes functionality across dedicated, isolated C3 modules:

```
src/
├── backend/
│   ├── ast.c3            # struct Task (48 bytes), JDN arithmetic (date_to_jdn, jdn_to_date)
│   ├── arena.c3          # MemoryArena, contiguous buffer allocation, zero-copy append
│   ├── parser.c3         # Strict todo.txt grammar scanner, ISO 8601 parser
│   ├── index.c3          # InvertedIndex & TemporalIndex using PostingNode linked lists
│   └── storage.c3        # Workspace, XDG paths, ingestion, deferred O_TRUNC serialization
├── presentation/
│   ├── tty.c3            # is_stdout_tty, single-pass streaming ANSI token colorizer
│   └── repl.c3           # ReplState, command dispatcher, @pool() memory-bounded loop
└── main.c3               # CLI entry point, argument parsing, POSIX SIGINT handler
```

### Module Responsibilities:

| Module | File | Responsibility | Dependencies |
| :--- | :--- | :--- | :--- |
| `backend::ast` | `src/backend/ast.c3` | `Task` struct (48B) and Julian Day Number arithmetic | None |
| `backend::arena` | `src/backend/arena.c3` | Contiguous memory arena buffer allocation and zero-copy string appending | `std::io` |
| `backend::parser` | `src/backend/parser.c3` | Strict lexical scanner for `todo.txt` syntax lines; zero-copy slicing | `backend::ast` |
| `backend::index` | `src/backend/index.c3` | Inverted tag index & JDN temporal lookup index using `PostingNode` | `backend::ast`, `backend::arena`, `std::collections::map` |
| `backend::storage` | `src/backend/storage.c3` | XDG directory resolution, file loading into arena, deferred write protocol | `backend::ast`, `backend::arena`, `backend::parser`, `backend::index`, `std::collections::list` |
| `presentation::tty` | `src/presentation/tty.c3` | ANSI escape sequencing, streaming token colorization, terminal capability detection (`isatty`) | `backend::ast`, `libc` |
| `presentation::repl` | `src/presentation/repl.c3` | Command tokenizer, interactive execution loop, query & mutation dispatcher, `@pool()` scoping | `backend::ast`, `backend::storage`, `backend::index`, `presentation::tty` |
| `app` | `src/main.c3` | CLI entry point, argument parsing, POSIX `SIGINT` signal installation | `backend::storage`, `presentation::repl`, `presentation::tty`, `libc` |

---

## 3. Project Directory Structure

```
todo_cli/
├── c3lib/                # Local standard library modules for C3 0.8.3
├── docs/                 # Detailed architectural and implementation guides
│   ├── 00_architecture_overview.md
│   ├── 01_memory_model_and_zerocopy.md
│   ├── 02_todo_txt_grammar_and_parser.md
│   ├── 03_temporal_engine_and_jdn.md
│   ├── 04_indexing_and_query_complexity.md
│   ├── 05_storage_and_xdg_protocol.md
│   ├── 06_presentation_layer_and_repl.md
│   └── 07_step_by_step_build_guide.md
├── resources/            # Sample workspace datasets
│   └── sample_todo.txt
├── src/                  # Multi-file modular source tree
│   ├── backend/
│   ├── presentation/
│   └── main.c3
├── Makefile              # Build automation
└── project.json          # C3 project configuration
```

---

## 4. Build & Execution Workflow

The project includes a `Makefile` configured to compile all files in `src/**`:

```bash
# Build the binary
make build

# Run with default XDG workspace ($XDG_DATA_HOME/usyuo/todo.txt)
make run

# Run with a specific test workspace
./usyuo resources/sample_todo.txt

# Run automated quick test
make test

# Clean build artifacts
make clean
```
