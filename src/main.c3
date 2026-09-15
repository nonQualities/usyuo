
module usyuo;
import backend::storage;
import presentation::repl;
import presentation::tty;
import std::io;
import libc;

storage::Workspace* g_active_workspace = null;

fn void handle_sigint(CInt sig)
{
    if (g_active_workspace != null)
    {
        io::printn("\nInterrupt received. Executing deferred write...");
        g_active_workspace.save_if_dirty();
    }
    libc::exit(0);
}

fn int main(String[] args)
{
    libc::signal(libc::SIGINT, &handle_sigint);

    String xdg_dir = storage::resolve_xdg_directory(mem);
    storage::ensure_directory_exists(xdg_dir);

    String target_file = string::format(mem, "%s/todo.txt", xdg_dir);
    if (args.len > 1 && args[1].len > 0)
    {
        if (args[1] == "--help" || args[1] == "-h")
        {
            io::printn("Usage: usyuo [OPTIONS] [WORKSPACE_FILE.txt]");
            io::printn("High-performance, zero-copy todo.txt CLI engine in C3.\n");
            io::printn("Options:");
            io::printn("  -h, --help     Display this help reference and exit");
            io::printn("  -v, --version  Display version information and exit\n");
            io::printn("Interactive Commands:");
            io::printn("  list           Browse workspace tasks");
            io::printn("  search <term>  Search tasks by substring");
            io::printn("  sort [date]    Sort tasks chronologically and re-index");
            io::printn("  today          Query tasks scheduled or due today");
            io::printn("  tag <tag>      Query tasks by tag (@context, +project, key:val)");
            io::printn("  add <text>     Append new task to zero-copy memory runway");
            io::printn("  done <id>      Mark task as completed");
            io::printn("  save           Flush in-memory workspace state to disk");
            io::printn("  help           Display interactive command reference");
            io::printn("  exit / quit    Flush dirty state and exit gracefully");
            return 0;
        }
        if (args[1] == "--version" || args[1] == "-v")
        {
            io::printn("usyuo v0.8.9 (薄様 · Zero-Copy todo.txt Engine)");
            return 0;
        }
        target_file = storage::isolate_external_workspace(args[1], xdg_dir, mem);
    }

    storage::Workspace ws;
    ws.load_from_file(target_file);
    g_active_workspace = &ws;

    bool is_tty = tty::is_stdout_tty();
    if (is_tty)
    {
        sz completed_count = 0;
        for (sz i = 0; i < ws.tasks.len(); i++)
        {
            if (ws.tasks[i].completed) completed_count++;
        }
        sz total = ws.tasks.len();
        sz pending = total - completed_count;
        tty::render_banner(target_file, total, pending, completed_count);
    }

    repl::ReplState repl_state;
    repl_state.workspace = &ws;
    repl_state.running = true;
    repl_state.tty_mode = is_tty;
    repl_state.system_jdn = repl::get_current_system_jdn();

    while (repl_state.running)
    {
        @pool()
        {
            if (is_tty) io::printf("\n%susyuo %s❯%s ", tty::PURPLE, tty::CYAN_ACCENT, tty::RESET);
            if (try String line = io::treadline(io::stdin()))
            {
                repl_state.execute_command(line);
            }
            else
            {
                repl_state.running = false;
            }
        };
    }

    ws.save_if_dirty();
    if (is_tty) io::printfn("\n  %s✔%s Session ended. Workspace persisted.", tty::GREEN, tty::RESET);
    return 0;
}
