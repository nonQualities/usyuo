
module backend::storage;
import backend::ast;
import backend::arena;
import backend::parser;
import backend::index;
import std::collections::list;
import std::io;
import std::io::path;
import std::os::env;
import libc;

alias TaskArray = List{Task};

<*
 * Represents active workspace state, memory, and deferred persistence.
 *>
struct Workspace
{
    String workspace_path;
    String workspace_name;
    MemoryArena arena;
    TaskArray tasks;
    InvertedIndex inverted_index;
    TemporalIndex temporal_index;
    bool dirty;
}

<*
 * Ensures the target directory exists, creating parent directories as needed.
 *>
fn bool ensure_directory_exists(String dir_path)
{
    if (path::exists((Path)dir_path)) return true;
    return (bool)(path::mkdir((Path)dir_path, true) ?? false);
}

<*
 * Resolves the primary XDG workspace directory: $XDG_DATA_HOME/usyuo/
 * falling back to ~/.local/share/usyuo/, or ./usyuo_data if read-only.
 *>
fn String resolve_xdg_directory(Allocator allocator)
{
    String xdg_home = env::get_var(allocator, "XDG_DATA_HOME") ?? "";
    if (xdg_home.len > 0)
    {
        String p = string::format(allocator, "%s/usyuo", xdg_home);
        if (ensure_directory_exists(p)) return p;
    }
    String home = env::get_var(allocator, "HOME") ?? "";
    if (home.len > 0)
    {
        String p = string::format(allocator, "%s/.local/share/usyuo", home);
        if (ensure_directory_exists(p)) return p;
    }
    String local_fallback = "./usyuo_data";
    ensure_directory_exists(local_fallback);
    return local_fallback;
}

<*
 * Copies an external file into the XDG directory to isolate the workspace (FR-1).
 *>
fn String isolate_external_workspace(String external_path, String xdg_dir, Allocator allocator)
{
    if (!path::exists((Path)external_path)) return external_path;
    if (!ensure_directory_exists(xdg_dir)) return external_path;

    // Extract filename from external path
    String filename = external_path;
    usz last_slash = 0;
    bool found_slash = false;
    for (usz i = 0; i < external_path.len; i++)
    {
        if (external_path[i] == '/')
        {
            last_slash = i + 1;
            found_slash = true;
        }
    }
    if (found_slash && last_slash < external_path.len)
    {
        filename = external_path[last_slash..];
    }

    String isolated_path = string::format(allocator, "%s/%s", xdg_dir, filename);

    // If source and destination are identical, already isolated
    if (external_path == isolated_path) return isolated_path;

    // Read external source file
    if (try File src_f = file::open(external_path, "rb"))
    {
        defer (void)src_f.close();
        usz sz_bytes = (usz)(file::get_size(external_path) ?? 0);
        char[] buf = mem::alloc_array(char, (sz)sz_bytes);
        defer mem::free(buf.ptr);

        if (sz_bytes > 0)
        {
            src_f.read(buf[0 : sz_bytes])!!;
        }

        // Write to isolated target path
        if (try File dst_f = file::open(isolated_path, "wb"))
        {
            defer (void)dst_f.close();
            if (sz_bytes > 0)
            {
                dst_f.write((String)buf[0 : sz_bytes])!!;
            }
            return isolated_path;
        }
    }

    return external_path;
}

<*
 * Loads a workspace file into the arena and parses all tasks into the AST.
 *>
fn bool Workspace.load_from_file(&self, String file_path)
{
    self.dirty = false;
    self.workspace_path = file_path;
    self.arena.init(1048576);
    self.tasks.init(mem);
    self.inverted_index.init(mem);
    self.temporal_index.init(mem);

    if (!path::exists((Path)file_path))
    {
        return true;
    }

    usz sz_bytes = (usz)(file::get_size(file_path) ?? 0);
    if (sz_bytes == 0) return true;

    // Read entire file contents directly into the contiguous arena
    File f = file::open(file_path, "rb")!!;
    defer (void)f.close();

    if (sz_bytes + 1024 > self.arena.capacity)
    {
        self.arena.buffer = (char*)mem::realloc(self.arena.buffer, (sz)(sz_bytes + 65536));
        self.arena.capacity = sz_bytes + 65536;
    }

    f.read(self.arena.buffer[0 : sz_bytes])!!;
    self.arena.buffer[sz_bytes] = 0;
    self.arena.used = sz_bytes;

    // Zero-copy line-by-line parsing
    usz line_start = 0;
    int task_id = 1;
    for (usz i = 0; i <= sz_bytes; i++)
    {
        if (i == sz_bytes || self.arena.buffer[i] == '\n')
        {
            usz len = i - line_start;
            if (len > 0 && self.arena.buffer[line_start + len - 1] == '\r') len--;
            if (len > 0)
            {
                String line_slice = (String)self.arena.buffer[line_start : len];
                Task task;
                parser::parse_task_line(line_slice, task_id++, &task);
                self.tasks.push(task);

                // Index tokens in line directly
                String rem = task.description;
                usz pos = 0;
                while (pos < rem.len)
                {
                    while (pos < rem.len && (rem[pos] == ' ' || rem[pos] == '\t')) pos++;
                    if (pos >= rem.len) break;

                    usz token_start = pos;
                    while (pos < rem.len && rem[pos] != ' ' && rem[pos] != '\t') pos++;
                    String token = rem[token_start : pos - token_start];

                    if (token.starts_with("@") && token.len > 1)
                    {
                        self.inverted_index.insert(token, task.id, &self.arena);
                    }
                    else if (token.starts_with("+") && token.len > 1)
                    {
                        self.inverted_index.insert(token, task.id, &self.arena);
                    }
                    else if (token.contains(":"))
                    {
                        self.inverted_index.insert(token, task.id, &self.arena);
                    }
                }

                int eff_jdn = task.get_effective_jdn();
                if (eff_jdn != 0)
                {
                    self.temporal_index.insert(eff_jdn, task.id, &self.arena);
                }
            }
            line_start = i + 1;
        }
    }
    return true;
}

<*
 * Deferred serialization protocol (FR-5):
 * Flushes active in-memory tasks to disk with O_TRUNC in a single stream.
 *>
fn void Workspace.save_if_dirty(&self)
{
    if (!self.dirty) return;
    File f = file::open(self.workspace_path, "wb")!!;
    defer (void)f.close();

    for (sz i = 0; i < self.tasks.len(); i++)
    {
        Task* t = &self.tasks[i];
        if (t.raw_line.len > 0)
        {
            f.write(t.raw_line)!!;
            f.write("\n")!!;
        }
    }
    self.dirty = false;
}
