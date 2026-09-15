module presentation::repl;
import backend::ast;
import backend::arena;
import backend::storage;
import backend::index;
import backend::parser;
import presentation::tty;
import std::io;
import std::time::datetime;


struct ReplState
{
    storage::Workspace* workspace;
    bool running;
    bool tty_mode;
    int system_jdn;
}


fn int get_current_system_jdn()
{
    DateTime dt = datetime::now();
    TzDateTime local = dt.to_local();
    return ast::date_to_jdn((int)local.year, (int)local.month + 1, (int)local.day);
}


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
        if (self.tty_mode)
        {
            tty::render_section_header("📖", "Command Reference");
            io::printfn("  %s%-24s%s  Browse workspace tasks", tty::CYAN_ACCENT, "list [all|done|pending]", tty::RESET);
            io::printfn("  %s%-24s%s  Case-insensitive task search", tty::CYAN_ACCENT, "search <term>", tty::RESET);
            io::printfn("  %s%-24s%s  Sort tasks by date and re-index", tty::CYAN_ACCENT, "sort | sort due", tty::RESET);
            io::printfn("  %s%-24s%s  Tasks scheduled or due today", tty::CYAN_ACCENT, "today", tty::RESET);
            io::printfn("  %s%-24s%s  Instant inverted index tag lookup", tty::CYAN_ACCENT, "tag <@ctx|+proj|tag>", tty::RESET);
            io::printfn("  %s%-24s%s  Append new task to zero-copy memory runway", tty::CYAN_ACCENT, "add <raw text>", tty::RESET);
            io::printfn("  %s%-24s%s  Mark task completed with date stamp", tty::CYAN_ACCENT, "done <id>", tty::RESET);
            io::printfn("  %s%-24s%s  Flush dirty in-memory state to disk", tty::CYAN_ACCENT, "save", tty::RESET);
            io::printfn("  %s%-24s%s  Flush modifications and exit gracefully", tty::CYAN_ACCENT, "exit / quit", tty::RESET);
            tty::render_section_footer();
        }
        else
        {
            io::printn("usyuo Commands:");
            io::printn("  list [all|done|pending]  - Display tasks");
            io::printn("  search <term>            - Search tasks by substring");
            io::printn("  sort [date]              - Sort tasks by date and re-index");
            io::printn("  today                    - Tasks scheduled for today");
            io::printn("  tag <@context|+proj|tag> - O(K) lookup by tag");
            io::printn("  add <raw task text>      - Append new task to workspace");
            io::printn("  done <id>                - Mark task as completed");
            io::printn("  save                     - Flush changes to disk");
            io::printn("  exit / quit              - Exit and deferred flush");
        }
        return;
    }

    if (input.starts_with("search ") || input.starts_with("find "))
    {
        usz prefix_len = input.starts_with("search ") ? 7 : 5;
        String query = input[prefix_len..].trim();
        if (query.len == 0) return;

        String query_lower = query.to_lower_tcopy();
        sz match_count = 0;

        for (sz i = 0; i < self.workspace.tasks.len(); i++)
        {
            Task* t = &self.workspace.tasks[i];
            if (t.description.to_lower_tcopy().contains(query_lower) ||
                t.raw_line.to_lower_tcopy().contains(query_lower))
            {
                match_count++;
            }
        }

        if (self.tty_mode)
        {
            if (match_count > 0)
            {
                tty::render_section_header("🔍", string::format(tmem, "Search Results for '%s' (%d match%s)", 
                    query, match_count, match_count == 1 ? "" : "es"));
            }
            else
            {
                tty::render_section_header("🔍", string::format(tmem, "Search Results for '%s'", query));
            }
        }
        else
        {
            io::printfn("--- Search Results for '%s' (%d matches) ---", query, match_count);
        }

        if (match_count == 0)
        {
            if (self.tty_mode)
            {
                io::printfn("  %s∅ No tasks found matching '%s'.%s", tty::MUTED, query, tty::RESET);
            }
            else
            {
                io::printfn("No tasks found matching '%s'.", query);
            }
        }
        else
        {
            for (sz i = 0; i < self.workspace.tasks.len(); i++)
            {
                Task* t = &self.workspace.tasks[i];
                if (t.description.to_lower_tcopy().contains(query_lower) ||
                    t.raw_line.to_lower_tcopy().contains(query_lower))
                {
                    tty::render_task(t, self.tty_mode);
                }
            }
        }

        if (self.tty_mode)
        {
            tty::render_section_footer();
        }
        return;
    }

    if (input == "sort" || input == "sort date" || input == "sort by date" || input == "sort due")
    {
        self.workspace.sort_by_date();

        if (self.tty_mode)
        {
            tty::render_section_header("📅", string::format(tmem, "Tasks Sorted by Date (%d total)", self.workspace.tasks.len()));
            for (sz i = 0; i < self.workspace.tasks.len(); i++)
            {
                tty::render_task(&self.workspace.tasks[i], self.tty_mode);
            }
            tty::render_section_footer();
            io::printfn("  %s✔%s %d tasks sorted by date and re-indexed.", tty::GREEN, tty::RESET, self.workspace.tasks.len());
        }
        else
        {
            io::printfn("--- Tasks Sorted by Date (%d total) ---", self.workspace.tasks.len());
            for (sz i = 0; i < self.workspace.tasks.len(); i++)
            {
                tty::render_task(&self.workspace.tasks[i], self.tty_mode);
            }
            io::printfn("Sorted %d tasks by date.", self.workspace.tasks.len());
        }
        return;
    }

    if (input == "today")
    {
        if (self.tty_mode)
        {
            tty::render_section_header("📅", string::format(tmem, "Scheduled for Today (JDN %d)", self.system_jdn));
        }
        else
        {
            io::printfn("--- Tasks for Today (JDN %d) ---", self.system_jdn);
        }

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
            if (self.tty_mode)
            {
                io::printfn("  %s∅ No tasks scheduled for today.%s", tty::MUTED, tty::RESET);
            }
            else
            {
                io::printn("No tasks scheduled for today.");
            }
        }
        if (self.tty_mode)
        {
            tty::render_section_footer();
        }
        return;
    }

    if (input.starts_with("tag "))
    {
        String tag = input[4..].trim();
        if (self.tty_mode)
        {
            tty::render_section_header("🏷️ ", string::format(tmem, "Tasks tagged with '%s'", tag));
        }
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
            if (self.tty_mode)
            {
                io::printfn("  %s∅ No tasks found matching tag '%s'.%s", tty::MUTED, tag, tty::RESET);
            }
            else
            {
                io::printfn("No tasks found matching tag '%s'.", tag);
            }
        }
        if (self.tty_mode)
        {
            tty::render_section_footer();
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
        self.workspace.index_task(&new_task);
        self.workspace.tasks.push(new_task);
        self.workspace.dirty = true;

        if (self.tty_mode)
        {
            io::printfn("  %s✔%s Added task %s#%d%s", tty::GREEN, tty::RESET, tty::BOLD, new_id, tty::RESET);
        }
        else
        {
            io::printfn("Added task #%d", new_id);
        }
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
                if (self.tty_mode)
                {
                    io::printfn("  %s✔%s Marked task %s#%d%s as completed!", tty::GREEN, tty::RESET, tty::BOLD, tid, tty::RESET);
                }
                else
                {
                    io::printfn("Completed task #%d", tid);
                }
                return;
            }
            else
            {
                if (self.tty_mode)
                {
                    io::printfn("  %s!%s Task #%d is already completed.", tty::ORANGE, tty::RESET, tid);
                }
                else
                {
                    io::printfn("Task #%d is already completed.", tid);
                }
                return;
            }
        }
        if (self.tty_mode)
        {
            io::printfn("  %s✘%s Invalid task ID '%s'.", tty::CORAL, tty::RESET, arg);
        }
        else
        {
            io::printfn("Invalid task ID '%s'.", arg);
        }
        return;
    }

    if (input == "list" || input == "ls" || input == "ls all" || input == "list all")
    {
        if (self.tty_mode)
        {
            tty::render_section_header("📋", string::format(tmem, "Workspace Tasks (%d total)", self.workspace.tasks.len()));
        }
        for (sz i = 0; i < self.workspace.tasks.len(); i++)
        {
            tty::render_task(&self.workspace.tasks[i], self.tty_mode);
        }
        if (self.tty_mode)
        {
            tty::render_section_footer();
        }
        return;
    }

	if(input == "list done" || input == "ls done"){

		if(self.tty_mode) tty::render_section_header("📋", string::format(tmem, "Workspace Completed Tasks (%d total)", self.workspace.tasks.len()));
        for(sz i = 0; i < self.workspace.tasks.len(); i++){
			if(self.workspace.tasks[i].completed) tty::render_task(&self.workspace.tasks[i], self.tty_mode);
		}

		if (self.tty_mode)
        {
            tty::render_section_footer();
        }
        return;
	}

	if(input == "list pending" || input == "ls pending"){

		if(self.tty_mode) tty::render_section_header("📋", string::format(tmem, "Workspace Pending Tasks (%d total)", self.workspace.tasks.len()));

		for(sz i = 0; i <self.workspace.tasks.len(); ++i){

		if(!self.workspace.tasks[i].completed) tty::render_task(&self.workspace.tasks[i], self.tty_mode);
		}
		return;
	}

    if (input == "save")
    {
        self.workspace.save_if_dirty();
        if (self.tty_mode)
        {
            io::printfn("  %s✔%s Workspace state persisted to disk.", tty::GREEN, tty::RESET);
        }
        else
        {
            io::printn("Saved workspace.");
        }
        return;
    }

    if (self.tty_mode)
    {
        io::printfn("  %s✘%s Unknown command '%s'. Type %shelp%s for available commands.", 
            tty::CORAL, tty::RESET, input, tty::CYAN_ACCENT, tty::RESET);
    }
    else
    {
        io::printfn("Unknown command '%s'. Type 'help' for available commands.", input);
    }
}
