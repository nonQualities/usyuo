module test_sort;
import backend::ast;
import backend::index;
import backend::parser;
import backend::storage;
import std::io;

fn int main()
{
    io::printn("=== Testing Task Date Sorting & Index Rebuilding ===");

    // Test 1: compare_tasks_by_date unit verification
    ast::Task t_overdue;
    parser::parse_task_line("(A) Fix bug +urgent due:2026-09-01", 1, &t_overdue);

    ast::Task t_future;
    parser::parse_task_line("(B) Feature release due:2026-09-20", 2, &t_future);

    ast::Task t_nodue;
    parser::parse_task_line("(C) 2026-09-10 Refactor code", 3, &t_nodue);

    ast::Task t_done;
    parser::parse_task_line("x 2026-09-15 2026-09-01 Completed item due:2026-09-05", 4, &t_done);

    // Overdue task should precede future task
    if (storage::compare_tasks_by_date(&t_overdue, &t_future) >= 0)
    {
        io::printn("FAIL: overdue task should precede future task");
        return 1;
    }

    // Task with due date should precede task with only creation date
    if (storage::compare_tasks_by_date(&t_future, &t_nodue) >= 0)
    {
        io::printn("FAIL: task with due date should precede task without due date");
        return 1;
    }

    // Uncompleted task should precede completed task even if completed has earlier due date
    if (storage::compare_tasks_by_date(&t_nodue, &t_done) >= 0)
    {
        io::printn("FAIL: pending task should precede completed task");
        return 1;
    }
    io::printn("PASS: [1/3] compare_tasks_by_date enforces deadline priority and pending precedence!");

    // Test 2: Full Workspace.sort_by_date()
    storage::Workspace ws;
    ws.arena.init(65536);
    ws.tasks.init(mem);
    ws.inverted_index.init(mem);
    ws.temporal_index.init(mem);

    // Push tasks out of order: done first, future second, overdue third
    ws.tasks.push(t_done);
    ws.tasks.push(t_future);
    ws.tasks.push(t_overdue);
    ws.tasks.push(t_nodue);

    ws.sort_by_date();

    if (ws.tasks.len() != 4)
    {
        io::printfn("FAIL: expected 4 tasks, got %d", ws.tasks.len());
        return 1;
    }

    // Expected order after sort:
    // 1: t_overdue (due:2026-09-01)
    // 2: t_future (due:2026-09-20)
    // 3: t_nodue (created: 2026-09-10)
    // 4: t_done (completed)
    if (ws.tasks[0].due_jdn != t_overdue.due_jdn || ws.tasks[0].id != 1)
    {
        io::printn("FAIL: task 0 should be overdue task with re-indexed id 1");
        return 1;
    }
    if (ws.tasks[1].due_jdn != t_future.due_jdn || ws.tasks[1].id != 2)
    {
        io::printn("FAIL: task 1 should be future task with re-indexed id 2");
        return 1;
    }
    if (ws.tasks[2].creation_jdn != t_nodue.creation_jdn || ws.tasks[2].id != 3)
    {
        io::printn("FAIL: task 2 should be nodue task with re-indexed id 3");
        return 1;
    }
    if (!ws.tasks[3].completed || ws.tasks[3].id != 4)
    {
        io::printn("FAIL: task 3 should be completed task with re-indexed id 4");
        return 1;
    }
    io::printn("PASS: [2/3] Workspace.sort_by_date sorts tasks chronologically and re-indexes IDs!");

    // Test 3: Verify inverted index updated with new IDs
    if (try backend::index::PostingNode* node = ws.inverted_index.lookup("+urgent"))
    {
        if (node.task_id != 1)
        {
            io::printfn("FAIL: expected +urgent to point to task ID 1, got %d", node.task_id);
            return 1;
        }
    }
    else
    {
        io::printn("FAIL: +urgent tag lookup failed after index rebuild");
        return 1;
    }
    io::printn("PASS: [3/3] Inverted index reflects re-indexed task IDs after sort!");

    io::printn("=================================");
    io::printn(" ALL TESTS PASSED! SORT ENGINE OPERATIONAL! ");
    io::printn("=================================");
    return 0;
}
