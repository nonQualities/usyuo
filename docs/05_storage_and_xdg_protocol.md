# 05: Storage, XDG Compliance & Deferred Serialization

## 1. The XDG Base Directory Specification

The SRS File System Conventions mandate:
> *"The system strictly adheres to the XDG Base Directory Specification for data persistence. Workspaces (individual `.txt` files) must be localized within a dedicated application directory.*  
> *Primary path: `$XDG_DATA_HOME/usyuo/` (defaulting to `~/.local/share/usyuo/`)."*

### Resolving the Path
1. Check if the environment variable `XDG_DATA_HOME` is set and non-empty.
   * If yes: use `$XDG_DATA_HOME/usyuo`.
2. Fall back to `$HOME/.local/share/usyuo`.
3. If neither is available, fall back safely to `./usyuo`.

### Directory Initialization
Upon startup, the engine verifies whether the directory exists using `path::exists()`. If absent, it invokes recursive directory creation (`path::mkdir(path, true)` or POSIX `mkdir(path, 0755)`).

```c
fn String resolve_xdg_directory(Allocator allocator)
{
    String xdg_home = env::get_var(allocator, "XDG_DATA_HOME") ?? "";
    if (xdg_home.len > 0)
    {
        return string::format(allocator, "%s/usyuo", xdg_home);
    }
    String home = env::get_var(allocator, "HOME") ?? ".";
    return string::format(allocator, "%s/.local/share/usyuo", home);
}
```

---

## 2. Workspace Ingestion & Isolation Protocol (FR-1)

The SRS states:
> *"If launched with a file path argument referencing an external file, the system must copy the target file into the XDG data directory before loading it, thereby isolating the workspace."*

### Why Workspace Isolation is Enforced:
1. **Sandboxed Data Management**: By copying foreign `.txt` files into `$XDG_DATA_HOME/usyuo/`, the user's task ecosystem remains centrally managed in one predictable directory.
2. **Protection Against Accidental Modification**: External files in arbitrary project trees or temp directories are not modified in-place; the user works on an isolated workspace snapshot.

### Loading Flow:
```
CLI Argument Provided?
   |
   +-- YES (e.g. /path/to/my_tasks.txt)
   |     |
   |     +--> Extract basename ("my_tasks.txt")
   |     +--> Check if already inside XDG dir
   |     +--> If external: Copy file -> $XDG_DATA_HOME/usyuo/my_tasks.txt
   |     +--> Mount $XDG_DATA_HOME/usyuo/my_tasks.txt
   |
   +-- NO
         |
         +--> Mount default workspace: $XDG_DATA_HOME/usyuo/todo.txt
```

---

## 3. Deferred Serialization Protocol (FR-5)

The SRS specifies:
> *"To minimize disk thrashing, absolute parity between the disk and memory is not maintained concurrently.*  
> *Dirty Flag: Any operation modifying the task array sets a global boolean `dirty` flag.*  
> *Flushing: Upon graceful REPL exit, if `dirty == true`, the system truncates the active workspace file (`O_TRUNC`) and sequentially writes the string representation of all task nodes back to disk in a single continuous stream."*

### Problems with Synchronous Disk I/O:
* **Disk Thrashing**: If every keystroke, status toggle, or added task flushes the entire file to disk immediately, heavy I/O operations stall the interactive REPL.
* **Flash Wear**: Repeatedly overwriting flash memory cells for small changes degrades SSD performance and longevity.

### The In-Memory `dirty` Flag Protocol:
1. When the workspace is initially ingested into the memory arena:
   $$\text{dirty} = \text{false}$$
2. Any state mutation (`add`, `done`, `del`, `pri`) sets:
   $$\text{dirty} = \text{true}$$
3. Flushing only occurs when:
   * The user runs the `save` command explicitly.
   * The user runs `exit` or `quit`.
   * The application receives a `SIGINT` (Ctrl+C) termination signal.
4. If `dirty == false` when exiting, disk I/O is skipped completely.

### High-Throughput Sequential Stream Serialization:
```c
fn void Workspace.save_if_dirty(&self)
{
    if (!self.dirty) return;

    // Truncate existing file and open for sequential write
    File f = file::open(self.workspace_path, "wb")!!;
    defer (void)f.close();

    for (sz i = 0; i < self.tasks.len(); i++)
    {
        Task* t = self.tasks[i];
        if (t.raw_line.len > 0)
        {
            f.write(t.raw_line)!!;
            f.write("\n")!!;
        }
    }
    self.dirty = false;
}
```
