================================================================================
                                    usyuo - 
                          An overengineered todo app
which is an interpreter for todo.txt syntax, a REPL and a persistant DB in disguise.
================================================================================



1. WHAT IS THIS?
----------------
modern software has been often degraded to slop. for even the simple things, one needs
criminal amount of memory, and things are just slow in general, in pursuit of clean code 
we have lost all the performance one needs. this is not an unreabable codebase, but with
my limited knowledge I have tried to make it as fast as possible. Even more optimizations are in order.

It treats your tasks as an in-memory, structured database:
- Contiguous virtual memory arena (no secondary heap allocations).
- Integer-space calendar engine (Julian Day Numbers).
- Arena-backed inverted and temporal indices (O(1) insert, O(K) lookup).
- Deferred persistence (O_TRUNC atomic disk flushes).

|---------------------------------------------------------------------|
|=====================================================================|
|                BUT HOW FAST IT ACTUALLY IS:                         |
| usyuo isolates, parses, indexes, and validates all 200,000 tasks    | 
| in ~0.49 seconds (~400,000 tasks/second).                           |
|=====================================================================|
|----------------------------------------------------------------------|


2. WHAT DOES "USYUO" MEAN?
--------------------------
I generated the name thruogh a random name generator, I liked it and later appropriated
it to some meaningful entity. Here is an attempt to induce meaning into usyuo.
Derived from classical Japanese usuyo (薄様 / うすよう): an ultra-thin, high-density
paper beaten from wild mountain gampi fibers during the Heian court era. It had
virtually zero physical mass, extreme tensile strength, and crisp ink retention.
Officials carried it for pocket ledgers and sequential task memoranda.

It also nods to Latin "usus" (functional utility, practical execution).

How the inducted meaning can be oriented to software:
- Paper-thin overhead: The entire file lives in a single contiguous arena. Slices
  point directly into raw bytes. Literally no strings attached--just an 8-byte
  pointer with commitment issues and an 8-byte length.
- Durable plain-text: Like centuries-old gampi parchment, todo.txt outlives every
  proprietary cloud vendor charging $12/month for push notifications.


3. THE ZERO-COPY MEMORY MODEL
-----------------------------
Traditional parsers split text into hundreds of dynamic heap strings, scattering
pointers across your cache lines.

usyuo ingests the file in one read. The core Task AST node is trimmed down to
48 bytes:
  - id (4B)
  - completed (1B) + priority (1B) + padding (2B)
  - completion_jdn (4B) + creation_jdn (4B) + due_jdn (4B) + padding (4B)
  - raw_line slice (16B: char* ptr + usz len)
  - description slice (16B: char* ptr + usz len)

Allocations in the arena use an 8-byte aligned bump pointer. It moves strictly
forward--like software deadlines, the arena does not look back.


4. THE TEMPORAL ENGINE (DATING IS HARD)
-----------------------------------------------------------
Dating is notoriously difficult, but running string comparisons in a query loop
is pure self-inflicted heartbreak.

usyuo strictly forbids string date processing at query time. During lexical
parsing, ISO 8601 dates (YYYY-MM-DD) are immediately projected into integer
Julian Day Numbers (JDN) using the Fliegel-van Flandern algorithm.

The payoff, and I have not tested if these complexities are true
but my algos seem correct and these makes sense to me:
- Checking if a task is due today? A single integer comparison (O(1)).
- Checking if a task is in a date range? Two integer bounds checks (O(1)).
- Formatting back to YYYY-MM-DD on save? Constant-time Richards-Hatcher inversion.


5. INVERTED & TEMPORAL INDEXING
-------------------------------
For 20 tasks, linear search is fine. For 20,000 uncompleted tasks, you need to
reconsider your life choices--but the CPU shouldn't suffer with you.

usyuo builds two arena-backed indices at startup:
- InvertedIndex: Maps tag slices (@context, +project, key:val) to a singly-linked
  posting list of task IDs.
- TemporalIndex: Maps integer JDN dates to task IDs.

Posting nodes are bumped directly from the arena. Inserting is O(1) prepend;
querying a tag or date is O(1) hash lookup + O(K) traversal of matching tasks.


6. PERSISTENCE & ISOLATION
--------------------------
- Canonical storage: $XDG_DATA_HOME/usyuo/todo.txt (fallback: ./usyuo_data).
- External file isolation: Passing an external file snapshots it into the XDG
  repository before mounting, protecting your original from in-place corruption.
- Disciplined laziness: Mutations set a dirty bit in memory. Disk writes only
  occur on explicit "save", clean "exit", or when you mash Ctrl+C in an
  existential panic (caught via POSIX SIGINT).


7. COMMAND REFERENCE
--------------------
  list [all|done|pending]  List tasks (defaults to pending)
  search <term>            Case-insensitive search across task descriptions & tags
  sort [date]              Sort tasks chronologically (deadlines first) and re-index
  today                    Tasks scheduled or due today (O(K))
  tag <@ctx|+proj|key:val> Instant tag lookup via inverted index (O(K))
  add <raw text>           Append task to arena and update indices (O(L))
  done <task_id>           Mark completed (the closest a dev gets to closure)
  save                     Flush dirty workspace to disk immediately (O_TRUNC)
  help                     Show command cheat-sheet
  exit / quit              Flush dirty state and exit gracefully


8. BUILD & RUN
--------------
Prerequisites: C3 compiler (c3c 0.8.x), make, libc.

  make build               Compile executable to ./build/usyuo
  make test                Run sanity checks and verify test suite
  make run                 Build and launch interactive REPL
  ./build/usyuo [file.txt] Launch interactive REPL with custom file
