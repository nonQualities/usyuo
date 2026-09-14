module test_parser;
import backend::ast;
import backend::parser;
import std::io;

fn int main()
{
    io::printn("=== Testing Todo.txt Parser ===");

    // Test 1: Date parser
    int yr; int mo; int da;
    if (!parser::parse_iso_date("2026-09-15", &yr, &mo, &da))
    {
        io::printn("FAIL: parse_iso_date rejected valid date 2026-09-15");
        return 1;
    }
    if (yr != 2026 || mo != 9 || da != 15)
    {
        io::printfn("FAIL: parsed date values wrong: %d-%d-%d", yr, mo, da);
        return 1;
    }
    if (parser::parse_iso_date("2026-9-15", &yr, &mo, &da)) // invalid: single digit month
    {
        io::printn("FAIL: parse_iso_date accepted invalid date 2026-9-15");
        return 1;
    }
    io::printn("PASS: [1/4] parse_iso_date validates and parses ISO 8601 strings!");

    // Test 2: Full task line parsing with priority, dates, contexts, projects, tags
    String line1 = "(A) 2026-09-14 Review architecture docs +Core @Meeting due:2026-09-15 pri:high";
    ast::Task t1;
    parser::parse_task_line(line1, 1, &t1);

    if (t1.completed)
    {
        io::printn("FAIL: t1 should not be completed");
        return 1;
    }
    if (t1.priority != 'A')
    {
        io::printfn("FAIL: expected priority 'A', got '%c'", t1.priority);
        return 1;
    }
    if (t1.creation_jdn == 0)
    {
        io::printn("FAIL: expected non-zero creation_jdn for 2026-09-14");
        return 1;
    }
    if (t1.due_jdn == 0)
    {
        io::printn("FAIL: expected non-zero due_jdn for due:2026-09-15");
        return 1;
    }
    io::printn("PASS: [2/4] parse_task_line parses priority, creation date, and due date!");

    // Test 3: Option B - Verify parsed contexts, projects, and tag map
    if (t1.contexts.len() != 1 || t1.contexts[0] != "@Meeting")
    {
        io::printn("FAIL: expected context '@Meeting' in t1");
        return 1;
    }
    if (t1.projects.len() != 1 || t1.projects[0] != "+Core")
    {
        io::printn("FAIL: expected project '+Core' in t1");
        return 1;
    }
    if (try String due_val = t1.tags.get("due"))
    {
        if (due_val != "2026-09-15")
        {
            io::printfn("FAIL: expected tag due='2026-09-15', got '%s'", due_val);
            return 1;
        }
    }
    else
    {
        io::printn("FAIL: tag 'due' not found in t1.tags");
        return 1;
    }
    if (try String pri_val = t1.tags.get("pri"))
    {
        if (pri_val != "high")
        {
            io::printfn("FAIL: expected tag pri='high', got '%s'", pri_val);
            return 1;
        }
    }
    else
    {
        io::printn("FAIL: tag 'pri' not found in t1.tags");
        return 1;
    }
    io::printn("PASS: [3/4] Option B verified! contexts, projects, and tag map populated in single pass!");

    // Test 4: Completed task with completion date and creation date
    String line2 = "x 2026-09-14 2026-09-01 Done task +Project @Work";
    ast::Task t2;
    parser::parse_task_line(line2, 2, &t2);

    if (!t2.completed)
    {
        io::printn("FAIL: t2 should be completed");
        return 1;
    }
    if (t2.completion_jdn == 0 || t2.creation_jdn == 0)
    {
        io::printn("FAIL: expected both completion_jdn and creation_jdn on t2");
        return 1;
    }
    if (t2.description != "Done task +Project @Work")
    {
        io::printfn("FAIL: description mismatch: '%s'", t2.description);
        return 1;
    }
    if (t2.contexts.len() != 1 || t2.contexts[0] != "@Work")
    {
        io::printn("FAIL: expected context '@Work' in t2");
        return 1;
    }
    if (t2.projects.len() != 1 || t2.projects[0] != "+Project")
    {
        io::printn("FAIL: expected project '+Project' in t2");
        return 1;
    }
    io::printn("PASS: [4/4] parse_task_line parses completed task with two dates!");

    t1.free();
    t2.free();

    io::printn("=================================");
    io::printn(" ALL TESTS PASSED! OPTION B IS FULLY OPERATIONAL! ");
    io::printn("=================================");
    return 0;
}
