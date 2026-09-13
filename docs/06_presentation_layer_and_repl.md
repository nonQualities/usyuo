# 06: Presentation Layer, TTY Formatting & REPL

## 1. Separation of Concerns in the Presentation Layer

The SRS Section 5.2 establishes:
> *"A function handling TTY character rendering must not directly perform substring checks on a line buffer; it must iterate over the parsed `Task` struct. Separation of concerns must survive the single-file structure."*

### Why Presentation Logic Must Never Reparse Strings:
1. **Performance**: If the renderer re-scanned lines for `+` or `@` symbols, every `list` command would redundantly execute the lexical scanner again.
2. **Correctness**: Substring checks in the presentation layer lead to false positives (e.g. rendering `user@email.com` in cyan because it contains `@`).
3. **Purity of Representation**: The presentation layer (`presentation::tty`) receives a typed `Task*` and consumes structured fields (`task.priority`, `task.contexts`, `task.projects`, `task.completed`), acting strictly as a view layer.

---

## 2. Terminal Detection & ANSI Syntax Highlighting

Terminal output must adapt dynamically to the environment:
* When connected to an interactive terminal (`isatty(1) == 1`), ANSI color sequences provide rich visual hierarchy.
* When redirected to a file, pipe, or test harness (`isatty(1) == 0`), color codes are disabled to avoid polluting downstream utilities (e.g. `grep`, `awk`).

### ANSI Styling Palette

| Syntax Element | Visual Style | ANSI Escape Sequence |
| :--- | :--- | :--- |
| **Operational ID** | Bold White | `\x1b[1m` |
| **Priority `(A)`** | Bold Red | `\x1b[1;31m` |
| **Priority `(B)`** | Bold Yellow | `\x1b[1;33m` |
| **Priority `(C)`** | Bold Cyan | `\x1b[1;36m` |
| **Context (`@work`)**| Cyan | `\x1b[36m` |
| **Project (`+c3`)** | Magenta | `\x1b[35m` |
| **Tags (`due:...`)** | Yellow | `\x1b[33m` |
| **Completed Task** | Dim + Strikethrough | `\x1b[2;9m` |

### Rendering Implementation:
```c
module presentation::tty;
import backend::ast;
import std::io;
import libc;

fn bool is_stdout_tty()
{
    return libc::isatty(1) == 1;
}

fn void render_task(Task* task, bool use_color)
{
    if (!use_color)
    {
        io::printfn("[%3d] %s", task.id, task.raw_line);
        return;
    }

    // Operational ID
    io::printf("\x1b[1m[%3d]\x1b[0m ", task.id);

    // Completed tasks rendered with dim + strikethrough
    if (task.completed)
    {
        io::printf("\x1b[2;9mx %s\x1b[0m\n", task.raw_line[2..]);
        return;
    }

    // Color-coded priority
    if (task.priority != 0)
    {
        String pri_color = "\x1b[33m";
        if (task.priority == 'A') pri_color = "\x1b[31m";
        else if (task.priority == 'C') pri_color = "\x1b[36m";
        io::printf("\x1b[1m%s(%c)\x1b[0m ", pri_color, task.priority);
    }

    // Description body
    io::printf("%s ", task.description);

    // Contexts in cyan
    for (sz i = 0; i < task.contexts.len(); i++)
        io::printf("\x1b[36m%s\x1b[0m ", task.contexts[i]);

    // Projects in magenta
    for (sz i = 0; i < task.projects.len(); i++)
        io::printf("\x1b[35m%s\x1b[0m ", task.projects[i]);

    // Metadata tags in yellow
    for (sz i = 0; i < task.tags.len(); i++)
        io::printf("\x1b[33m%s\x1b[0m ", task.tags[i]);

    io::printn("");
}
```

---

## 3. The Interactive REPL Engine (FR-2)

The REPL operates as a non-terminating input loop:
```
[Start REPL]
     |
     v
[Display Prompt: "c3todo> "]
     |
     v
[Read Line from stdin (io::treadline)]
     |
     +---> "today"               --> O(K) lookup in TemporalIndex
     |
     +---> "tag <name>"          --> O(K) lookup in InvertedIndex
     |
     +---> "add <task text>"     --> Append to Arena, parse, update indices
     |
     +---> "done <id>"           --> Mark completed, stamp date, set dirty=true
     |
     +---> "list" / "ls"         --> Iterate active tasks & render
     |
     +---> "save"                --> Workspace.save_if_dirty()
     |
     +---> "exit" / "quit"       --> Break loop -> Workspace.save_if_dirty()
```

---

## 4. Signal Handling & Graceful Exit (`SIGINT`)

To satisfy FR-5 and guarantee data integrity:
* If the user presses `Ctrl+C` (`SIGINT`), execution must **not** terminate abruptly with lost in-memory mutations.
* The application registers a POSIX signal handler via `libc::signal(libc::SIGINT, &handle_sigint)`.
* When triggered, the signal handler checks `g_active_workspace.save_if_dirty()`, cleanly flushing modified tasks to disk before calling `libc::exit(0)`.

```c
fn void handle_sigint(CInt sig)
{
    if (g_active_workspace != null)
    {
        io::printn("\nInterrupt received. Executing deferred write...");
        g_active_workspace.save_if_dirty();
    }
    libc::exit(0);
}
```
