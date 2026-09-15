module presentation::tty;
import backend::ast;
import std::io;
import libc;


const String RESET       = "\x1b[0m";
const String BOLD        = "\x1b[1m";
const String DIM          = "\x1b[2m";
const String STRIKE       = "\x1b[9m";
const String ITALIC      = "\x1b[3m";

const String PURPLE      = "\x1b[38;5;141m"; // Lavender (+Project)
const String TEAL        = "\x1b[38;5;43m";  // Mint / Cyan (@Context)
const String AMBER       = "\x1b[1;38;5;214m"; // Bold Amber (due:YYYY-MM-DD)
const String GOLD        = "\x1b[38;5;221m"; // Warm Gold (general key:val)
const String CORAL       = "\x1b[1;38;5;203m"; // Coral Red (Priority A)
const String ORANGE      = "\x1b[1;38;5;215m"; // Orange (Priority B)
const String SKY         = "\x1b[1;38;5;75m";  // Sky Blue (Priority C)
const String GREEN       = "\x1b[1;38;5;48m";  // Emerald Green (Done)
const String MUTED       = "\x1b[38;5;241m"; // Subtle Gray (IDs, borders)
const String DIM_TEXT    = "\x1b[2;9;38;5;245m"; // Completed text
const String BORDER      = "\x1b[38;5;141m"; // Border lavender
const String CYAN_ACCENT = "\x1b[1;38;5;51m";  // Cyan highlight



fn bool is_stdout_tty()
{
    return libc::isatty(1) == 1;
}


fn void render_banner(String workspace_path, sz total, sz pending, sz completed)
{
    io::printfn("%s╭─────────────────────────────────────────────────────────────────────────────╮%s", BORDER, RESET);
    io::printfn("%s│%s  %s✦ usyuo~ at your service, senpaii!%s  %s(薄様 · Zero-Copy Engine)%s  %s│%s", BORDER, RESET, CYAN_ACCENT, RESET, MUTED, RESET, BORDER, RESET);
    io::printfn("%s├─────────────────────────────────────────────────────────────────────────────┤%s", BORDER, RESET);
    io::printfn("%s│%s  %s📁 Workspace :%s %s%-55s%s %s                                          │%s", BORDER, RESET, MUTED, RESET, GOLD, workspace_path, RESET, BORDER, RESET);
    io::printfn("%s│%s  %s📊 Tasks     :%s %s%d loaded%s (%s%d pending%s · %s%d completed%s)   %s│%s", 
        BORDER, RESET, MUTED, RESET, GREEN, total, RESET, ORANGE, pending, RESET, MUTED, completed, RESET, BORDER, RESET);
    io::printfn("%s│%s  %s💡 Quick Tip :%s Type %shelp%s for commands                          %s│%s", 
        BORDER, RESET, MUTED, RESET, CYAN_ACCENT, RESET, CYAN_ACCENT, RESET);
    io::printfn("%s│%s  %s🌸 Gambare Senpaii! Good luck with your work!%s                      %s│%s", 
        BORDER, RESET, "\x1b[38;5;219m", RESET, BORDER, RESET);
    io::printfn("%s╰─────────────────────────────────────────────────────────────────────────────╯%s", BORDER, RESET);
}


fn void render_task(Task* task, bool use_color)
{
    if (!use_color)
    {
        io::printfn("[%3d] %s", task.id, task.raw_line);
        return;
    }

    
    io::printf("  %s#%02d%s  ", MUTED, task.id, RESET);


    if (task.completed)
    {
        io::printf("%s✓  %s", GREEN, RESET);
        io::printf("%s%s%s\n", DIM_TEXT, task.description, RESET);
        return;
    }

    if (task.priority != 0)
    {
        String pri_col = ORANGE;
        if (task.priority == 'A')
        {
            pri_col = CORAL;
        }
        else if (task.priority == 'C')
        {
            pri_col = SKY;
        }
        io::printf("%s● %c%s ", pri_col, task.priority, RESET);
    }
    else
    {
        io::printf("%s○  %s ", MUTED, RESET);
    }


    String rem = task.description;
    usz pos = 0;
    while (pos < rem.len)
    {
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
            io::printf("%s%s%s", TEAL, token, RESET);
        }
        else if (token.starts_with("+") && token.len > 1)
        {
            io::printf("%s%s%s", PURPLE, token, RESET);
        }
        else if (token.starts_with("due:") && token.len >= 14)
        {
            io::printf("%s◷ %s%s", AMBER, token, RESET);
        }
 
        else if (token.contains(":"))
        {
            io::printf("%s%s%s", GOLD, token, RESET);
        }
        
        else
        {
            io::print(token);
        }
    }
    io::printn("");
}


fn void render_section_header(String icon, String title)
{
    io::printf("%s╭─ %s %s%s%s ", BORDER, icon, BOLD, title, RESET);
    usz prefix_len = 5 + title.len;
    usz total = 77;
    usz remaining = total > prefix_len ? total - prefix_len : 5;
    for (usz i = 0; i < remaining; i++)
    {
        io::printf("%s─%s", BORDER, RESET);
    }
    io::printfn("%s╮%s", BORDER, RESET);
}


fn void render_section_footer()
{
    io::printfn("%s╰─────────────────────────────────────────────────────────────────────────────╯%s", BORDER, RESET);
}
