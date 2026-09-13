
module presentation::repl;
import backend::ast;
import backend::arena;
import backend::storage;
import backend::index;
import backend::parser;
import presentation::tty;
import std::io;
import std::time::datetime;

<*
 * Encapsulates runtime state of the interactive REPL.
 *>
struct ReplState
{
    storage::Workspace* workspace;
    bool running;
    bool tty_mode;
    int system_jdn;
}

<*
 * Computes today's system Julian Day Number.
 *>
fn int get_current_system_jdn()
{
    DateTime dt = datetime::now();
    TzDateTime local = dt.to_local();
    return ast::date_to_jdn((int)local.year, (int)local.month + 1, (int)local.day);
}

<*
 * Parses an integer task ID from a string slice.
 *>
fn int parse_int(String s)
{
    int res = 0;
    for (usz i = 0; i < s.len; i++)
    {
        if (s[i] < '0' || s[i] > '9') break;
        res = res * 10 + (s[i] - '0');
    }
    return res;
}

<*
 * Dispatches a parsed command line to query or mutation handlers.
 *>
fn void ReplState.execute_command(&self, String cmd_line)
{
    String input = cmd_line.trim();
    if (input.len == 0) return;

    if (input == "exit" || input == "quit")
    {
        self.running = false;
        return;
    }

    if (input == "help")
    {
        io::printn("usyuo Commands:");
        io::printn("  list [all|done|pending]  - Display tasks");
        io::printn("  today                    - Tasks scheduled for today");
        io::printn("  tag <@context|+proj|tag> - O(K) lookup by tag");
        io::printn("  add <raw task text>      - Append new task to workspace");
        io::printn("  done <id>                - Mark task as completed");
        io::printn("  save                     - Flush changes to disk");
        io::printn("  exit / quit              - Exit and deferred flush");
        return;
    }

    if (input == "today")
    {
        io::printfn("--- Tasks for Today (JDN %d) ---", self.system_jdn);
        bool found = false;
        if (try PostingNode* node = self.workspace.temporal_index.lookup(self.system_jdn))
        {
            while (node != null)
            {
                int tid = node.task_id;
                if (tid >= 1 && tid <= (int)self.workspace.tasks.len())
                {
                    tty::render_task(&self.workspace.tasks[(sz)(tid - 1)], self.tty_mode);
                    found = true;
                }
                node = node.next;
            }
        }
        if (!found)
        {
            io::printn("No tasks scheduled for today.");
        }
        return;
    }

    if (input.starts_with("tag "))
    {
        String tag = input[4..].trim();
        bool found = false;
        if (try PostingNode* node = self.workspace.inverted_index.lookup(tag))
        {
            while (node != null)
            {
                int tid = node.task_id;
                if (tid >= 1 && tid <= (int)self.workspace.tasks.len())
                {
                    tty::render_task(&self.workspace.tasks[(sz)(tid - 1)], self.tty_mode);
                    found = true;
                }
                node = node.next;
            }
        }
        if (!found)
        {
            io::printfn("No tasks found matching tag '%s'.", tag);
        }
        return;
    }

    if (input.starts_with("add "))
    {
        String raw = input[4..].trim();
        if (raw.len == 0) return;

        String arena_slice = self.workspace.arena.append_string(raw);
        int new_id = (int)self.workspace.tasks.len() + 1;
        Task new_task;
        parser::parse_task_line(arena_slice, new_id, &new_task);
        self.workspace.tasks.push(new_task);

        // Index tokens directly
        String rem = new_task.description;
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
                self.workspace.inverted_index.insert(token, new_id, &self.workspace.arena);
            }
            else if (token.starts_with("+") && token.len > 1)
            {
                self.workspace.inverted_index.insert(token, new_id, &self.workspace.arena);
            }
            else if (token.contains(":"))
            {
                self.workspace.inverted_index.insert(token, new_id, &self.workspace.arena);
            }
        }

        int eff_jdn = new_task.get_effective_jdn();
        if (eff_jdn != 0)
        {
            self.workspace.temporal_index.insert(eff_jdn, new_id, &self.workspace.arena);
        }

        self.workspace.dirty = true;
        io::printfn("Added task #%d", new_id);
        return;
    }

    if (input.starts_with("done "))
    {
        String arg = input[5..].trim();
        int tid = parse_int(arg);
        if (tid >= 1 && tid <= (int)self.workspace.tasks.len())
        {
            Task* t = &self.workspace.tasks[(sz)(tid - 1)];
            if (!t.completed)
            {
                t.completed = true;
                t.completion_jdn = self.system_jdn;

                int y; int m; int d;
                ast::jdn_to_date(self.system_jdn, &y, &m, &d);
                String updated = string::format(tmem, "x %04d-%02d-%02d %s", y, m, d, t.raw_line);
                t.raw_line = self.workspace.arena.append_string(updated);

                self.workspace.dirty = true;
                io::printfn("Completed task #%d", tid);
                return;
            }
            else
            {
                io::printfn("Task #%d is already completed.", tid);
                return;
            }
        }
        io::printfn("Invalid task ID '%s'.", arg);
        return;
    }

    if (input == "list" || input == "ls")
    {
        for (sz i = 0; i < self.workspace.tasks.len(); i++)
        {
            tty::render_task(&self.workspace.tasks[i], self.tty_mode);
        }
        return;
    }

    if (input == "save")
    {
        self.workspace.save_if_dirty();
        io::printn("Workspace saved to disk.");
        return;
    }

    io::printfn("Unknown command '%s'. Type 'help' for available commands.", input);
}
