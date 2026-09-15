module backend::parser;
import backend::ast;
import std::io;

fn bool is_digit(char c) => c >= '0' && c <= '9';

fn bool is_upper(char c) => c >= 'A' && c <= 'Z';

fn bool parse_iso_date(String s, int* year, int* month, int* day)
{
    if (s.len != 10) return false;
    if (s[4] != '-' || s[7] != '-') return false;
    for (usz i = 0; i < 4; i++) {
        if (!is_digit(s[i])) return false;
    }
    for (usz i = 5; i < 7; i++) {
        if (!is_digit(s[i])) return false;
    }
    for (usz i = 8; i < 10; i++) {
        if (!is_digit(s[i])) return false;
    }

    *year = (s[0] - '0') * 1000 + (s[1] - '0') * 100 + (s[2] - '0') * 10 + (s[3] - '0');
    *month = (s[5] - '0') * 10 + (s[6] - '0');
    *day = (s[8] - '0') * 10 + (s[9] - '0');
    return true;
}


fn void parse_task_line(String line, int id, Task* task)
{
    mem::clear(task, Task::size);
    task.id = id;
    task.raw_line = line;
    task.contexts.init(mem);
    task.projects.init(mem);
    task.tags.init(mem);

    String rem = line.trim();
    if (rem.len == 0) return;

    if (rem.len >= 2 && rem[0] == 'x' && rem[1] == ' ')
    {
        task.completed = true;
        rem = rem[2..].trim_left();
    }

    if (rem.len >= 4 && rem[0] == '(' && is_upper(rem[1]) && rem[2] == ')' && rem[3] == ' ')
    {
        task.priority = rem[1];
        rem = rem[4..].trim_left();
    }

    int yr; int mo; int da;
    if (rem.len >= 10 && parse_iso_date(rem[0 : 10], &yr, &mo, &da))
    {
        int first_jdn = ast::date_to_jdn(yr, mo, da);
        if (rem.len == 10 || rem[10] == ' ')
        {
            rem = rem.len > 10 ? rem[11..].trim_left() : "";

            if (task.completed)
            {
                task.completion_jdn = first_jdn;

                if (rem.len >= 10 && parse_iso_date(rem[0 : 10], &yr, &mo, &da))
                {
                    if (rem.len == 10 || rem[10] == ' ')
                    {
                        task.creation_jdn = ast::date_to_jdn(yr, mo, da);
                        rem = rem.len > 10 ? rem[11..].trim_left() : "";
                    }
                }
            }
            else
            {
                task.creation_jdn = first_jdn;
            }
        }
    }

    task.description = rem;

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
            task.contexts.push(token);
        }
        else if (token.starts_with("+") && token.len > 1)
        {
            task.projects.push(token);
        }
        else if (token.contains(":"))
        {
            usz colon_idx = 0;
            for (usz ci = 0; ci < token.len; ci++)
            {
                if (token[ci] == ':')
                {
                    colon_idx = ci;
                    break;
                }
            }
            if (colon_idx > 0 && colon_idx + 1 < token.len)
            {
                String key = token[0 : colon_idx];
                String val = token[colon_idx + 1 ..];
                task.tags[key] = val;

                if (key == "due")
                {
                    int dy; int dm; int dd;
                    if (parse_iso_date(val, &dy, &dm, &dd))
                    {
                        task.due_jdn = ast::date_to_jdn(dy, dm, dd);
                    }
                }
            }
        }
    }
}
