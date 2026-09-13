
module usyo;
import backend::storage;
import presentation::repl;
import presentation::tty;
import std::io;
import libc;

// Global workspace pointer for deferred serialization on SIGINT
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
            io::printn("Usage: usyuo [workspace_file.txt]");
            io::printn("High-performance, zero-copy todo.txt CLI engine in C3.");
            return 0;
        }
        // Isolate external workspace into XDG directory (FR-1)
        target_file = storage::isolate_external_workspace(args[1], xdg_dir, mem);
    }

    storage::Workspace ws;
    ws.load_from_file(target_file);
    g_active_workspace = &ws;

    bool is_tty = tty::is_stdout_tty();
    if (is_tty)
    {
        io::printn("===============================================================================");
        io::printn("                      **usyuo~ at your service, senpaii!!   ");
        io::printfn("Your Active Workspace: %s", target_file);
        io::printfn("usyuo~ works hard...loaded %d tasks", ws.tasks.len());
        io::printn("Ohoo you do not know how to use usyuo? ask me for `help` ^^");
		io::printn("Gambare Senpaii!! Good Luck with your work!");
        io::printn("=================================================================================");
    }

    repl::ReplState repl_state;
    repl_state.workspace = &ws;
    repl_state.running = true;
    repl_state.tty_mode = is_tty;
    repl_state.system_jdn = repl::get_current_system_jdn();

    // REPL loop with @pool() to guarantee O(1) steady-state memory consumption
    while (repl_state.running)
    {
        @pool()
        {
            if (is_tty) io::print("usyuo> ");
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

    // Deferred serialization upon graceful REPL exit (FR-5)
    ws.save_if_dirty();
    if (is_tty) io::printn("Session ended. Workspace persisted.");
    return 0;
}
