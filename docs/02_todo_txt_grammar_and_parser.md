# 02: `todo.txt` Grammar & Lexical Scanner

## 1. Formal Grammar Specification

The system implements a strict, deterministic lexical scanner for the `todo.txt` format. Each line represents an independent task record parsed linearly from left to right.

### Grammar Rules (EBNF Representation)

```ebnf
Line            ::= [ Completion ] [ Priority ] [ Date [ Date ] ] Description
Completion      ::= "x "
Priority        ::= "(" [A-Z] ") "
Date            ::= [0-9]{4} "-" [0-9]{2} "-" [0-9]{2} " "
Description     ::= ( Word | Context | Project | Tag )*
Context         ::= "@" [^ \t\r\n]+
Project         ::= "+" [^ \t\r\n]+
Tag             ::= [^ \t\r\n:]+ ":" [^ \t\r\n:]+
```

### Semantic Token Ordering Rules:
1. **Completion Marker**: An initial lowercase `x ` denotes that a task is completed. Any task lacking `x ` at position 0 is treated as active/incomplete.
2. **Priority Marker**: A single uppercase ASCII letter enclosed in parentheses and followed by a space (e.g., `(A) `). It must appear immediately at line start or directly after the completion marker.
3. **Temporal Markers**:
   * **Incomplete Tasks**: An ISO 8601 date string (`YYYY-MM-DD`) directly following the priority (or start) represents the **creation date**.
   * **Completed Tasks**: An ISO 8601 date directly following `x ` (or priority) represents the **completion date**. If a second ISO 8601 date immediately follows, it represents the **creation date**.
4. **Metadata Tags**:
   * Contexts: Tokens prefixed with `@` (e.g. `@backend`, `@errands`).
   * Projects: Tokens prefixed with `+` (e.g. `+c3engine`, `+v1`).
   * Key-Value Pairs: Tokens matching `key:value` (e.g. `due:2026-09-13`, `pri:A`).

---

## 2. Linear State-Machine Scanner

The parser does not use regular expressions or backtracking. It runs as a linear single-pass state machine across each line slice:

```
[Line Slice]
     |
     +---> Check starts_with("x ") ---------> task.completed = true
     |
     +---> Check "(A) " pattern ------------> task.priority = 'A'
     |
     +---> Check Date 1 (YYYY-MM-DD) -------> task.completion_jdn or creation_jdn
     |
     +---> Check Date 2 (YYYY-MM-DD) -------> task.creation_jdn
     |
     +---> Tokenize Remaining Description
             |
             +---> starts_with("@") ---------> task.contexts.push(token)
             +---> starts_with("+") ---------> task.projects.push(token)
             +---> contains(":") ------------> task.tags.push(token)
                     +---> starts_with("due:") -> task.due_jdn = parse_jdn()
```

---

## 3. High-Performance ISO 8601 Date Parsing

String date parsing is performed using integer arithmetic directly on character ASCII values, avoiding library calls or string allocations:

```c
fn bool is_digit(char c) => c >= '0' && c <= '9';

fn bool parse_iso_date(String s, int* year, int* month, int* day)
{
    // Must be exactly 10 characters: YYYY-MM-DD
    if (s.len != 10) return false;
    if (s[4] != '-' || s[7] != '-') return false;
    
    // Bounds check ASCII digits
    for (usz i = 0; i < 4; i++) if (!is_digit(s[i])) return false;
    for (usz i = 5; i < 7; i++) if (!is_digit(s[i])) return false;
    for (usz i = 8; i < 10; i++) if (!is_digit(s[i])) return false;

    *year = (s[0] - '0') * 1000 + (s[1] - '0') * 100 + (s[2] - '0') * 10 + (s[3] - '0');
    *month = (s[5] - '0') * 10 + (s[6] - '0');
    *day = (s[8] - '0') * 10 + (s[9] - '0');
    return true;
}
```

---

## 4. Edge Cases & Robustness Considerations

1. **Line Ending Independence**: The parser strips trailing `\r` (CR) characters before scanning to ensure uniform behavior across POSIX (`\n`) and Windows (`\r\n`) workspace files.
2. **Whitespace Normalization**: Multiple consecutive whitespace characters are skipped linearly without modifying the underlying arena buffer.
3. **Email vs. Context**: A token like `user@domain.com` does not start with `@`, so it is correctly parsed as regular body text rather than a context tag.
4. **Isolated Math Operators**: An isolated `+` (e.g. `1 + 1 = 2`) is rejected as a project tag by checking `token.len > 1`.
5. **Zero Allocation**: Every context, project, and tag pushed into `task.contexts`, `task.projects`, and `task.tags` is a `String` slice pointing directly into the arena line buffer.
