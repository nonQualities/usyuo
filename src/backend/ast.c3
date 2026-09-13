module backend::ast;

<*
 * Represents a parsed todo.txt task node.
 * Uses zero-copy String slices referencing the contiguous workspace arena.
 * Streamlined to 48 bytes by eliminating dynamic sub-lists.
 *>
struct Task
{
    int id;                 // 1-based operational index
    bool completed;         // true if prefixed with 'x '
    char priority;          // 'A'..'Z' or 0 if unprioritized
    int completion_jdn;     // Julian Day Number of completion, or 0
    int creation_jdn;       // Julian Day Number of creation, or 0
    int due_jdn;            // Julian Day Number from due:YYYY-MM-DD, or 0
    String raw_line;        // Full original line slice in arena
    String description;     // Task body text slice (excluding tags/dates)
}

<*
 * Converts Gregorian calendar date (year, month, day) to Julian Day Number (JDN).
 * Strictly maps ISO 8601 strings to integer space to guarantee O(1)
 * comparison during temporal queries.
 *>
fn int date_to_jdn(int year, int month, int day)
{
    int a = (14 - month) / 12;
    int y = year + 4800 - a;
    int m = month + 12 * a - 3;
    return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045;
}

<*
 * Inverts Julian Day Number back to Gregorian calendar (year, month, day)
 * using the Richards-Hatcher algorithm in constant time.
 *>
fn void jdn_to_date(int jdn, int* year, int* month, int* day)
{
    int l = jdn + 68569;
    int n = (4 * l) / 146097;
    l = l - (146097 * n + 3) / 4;
    int i = (4000 * (l + 1)) / 1461001;
    l = l - (1461 * i) / 4 + 31;
    int j = (80 * l) / 2447;
    *day = l - (2447 * j) / 80;
    l = j / 11;
    *month = j + 2 - (12 * l);
    *year = 100 * (n - 49) + i + l;
}

<*
 * Returns the effective JDN for temporal queries on a task.
 * Adheres to Option A: priority on due_jdn, fallback to creation_jdn.
 *>
fn int Task.get_effective_jdn(Task* self)
{
    if (self.due_jdn != 0) return self.due_jdn;
    return self.creation_jdn;
}
