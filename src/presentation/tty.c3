
module presentation::tty;
import backend::ast;
import std::io;
import libc;

// ANSI Terminal Escape Sequences
const String RESET      = "\x1b[0m";
const String BOLD       = "\x1b[1m";
const String DIM        = "\x1b[2m";
const String STRIKE     = "\x1b[9m";
const String RED        = "\x1b[31m";
const String GREEN      = "\x1b[32m";
const String YELLOW     = "\x1b[33m";
const String BLUE       = "\x1b[34m";
const String MAGENTA    = "\x1b[35m";
const String CYAN       = "\x1b[36m";
const String WHITE      = "\x1b[37m";

<*
 * Determines if standard output is connected to an interactive TTY.
 *>
fn bool is_stdout_tty()
{
    return libc::isatty(1) == 1;
}

<*
 * Renders a task with single-pass streaming ANSI syntax highlighting.
 * Preserves original word ordering without duplicate tags.
 *>
fn void render_task(Task* task, bool use_color)
{
    if (!use_color)
    {
        io::printfn("[%3d] %s", task.id, task.raw_line);
        return;
    }

    // Operational ID
    io::printf("%s[%3d]%s ", BOLD, task.id, RESET);

    // Completed task: dim and strikethrough
    if (task.completed)
    {
        io::printf("%s%s%s%s\n", DIM, STRIKE, task.raw_line, RESET);
        return;
    }

    // Priority
    if (task.priority != 0)
    {
        String pri_col = YELLOW;
        if (task.priority == 'A')
        {
            pri_col = RED;
        }
        else if (task.priority == 'C')
        {
            pri_col = CYAN;
        }
        io::printf("%s%s(%c)%s ", BOLD, pri_col, task.priority, RESET);
    }

    // Stream description tokens with inline colorization
    String rem = task.description;
    usz pos = 0;
    while (pos < rem.len)
    {
        // Print whitespace
        while (pos < rem.len && (rem[pos] == ' ' || rem[pos] == '\t'))
        {
            io::print(rem[pos : 1]);
            pos++;
        }
        if (pos >= rem.len) break;

        usz token_start = pos;
        while (pos < rem.len && rem[pos] != ' ' && rem[pos] != '\t') pos++;
        String token = rem[token_start : pos - token_start];

        if (token.starts_with("@") && token.len > 1)
        {
            io::printf("%s%s%s", CYAN, token, RESET);
        }
        else if (token.starts_with("+") && token.len > 1)
        {
            io::printf("%s%s%s", MAGENTA, token, RESET);
        }
        else if (token.starts_with("due:") && token.len >= 14)
        {
            io::printf("%s%s%s%s", BOLD, YELLOW, token, RESET);
        }
        else if (token.contains(":"))
        {
            io::printf("%s%s%s", YELLOW, token, RESET);
        }
        else
        {
            io::print(token);
        }
    }

    io::printn("");
}
