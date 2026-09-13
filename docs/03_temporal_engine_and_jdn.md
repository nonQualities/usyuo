# 03: Temporal Engine & Julian Day Number (JDN)

## 1. Why String Date Processing is Forbidden

The SRS Algorithmic Mandate specifies:
> *"String-based date processing is forbidden at query time. Temporal data must be mapped to integer space upon parsing to guarantee bounded time complexity for interval queries."*

### Flaws with String Date Filtering:
1. **Redundant Character Comparisons**: Comparing `"2026-09-13"` against `"2026-09-20"` requires 10 byte comparisons per task. Across 100,000 tasks, an interval filter performs millions of redundant ASCII comparisons.
2. **Calendar Arithmetic at Query Time**: Asking for "tasks due in the next 7 days" requires computing calendar day roll-overs, 28/29/30/31-day month boundaries, and leap-year rules inside the query loop.
3. **Loss of Mathematical Continuity**: Strings do not support arithmetic subtraction ($date_2 - date_1$). Computing the elapsed days between two dates requires repeated parsing.

---

## 2. Mathematical Derivation of Julian Day Number

The **Julian Day Number (JDN)** is an integer representing the count of days elapsed since the epoch of January 1, 4713 BC in the Julian proleptic calendar.

### The Five-Month Repeating Pattern
A key insight in calendar mathematics is the sequence of month lengths in the Gregorian calendar:
* March to July: 31, 30, 31, 30, 31 (Total: 153 days)
* August to December: 31, 30, 31, 30, 31 (Total: 153 days)

The arithmetic term:
$$\left\lfloor \frac{153m + 2}{5} \right\rfloor$$
where $m$ is the 0-indexed month from March ($m=0$ for March, $m=1$ for April, ..., $m=11$ for February), generates the exact cumulative sum of days for every month without any branching!

By shifting January and February to months 10 and 11 of the *preceding* year:
1. February (with its variable 28 or 29 days) becomes the last month of the year.
2. Leap years only add a day to the very end of the calendar year, eliminating conditional adjustments for earlier months.

### The Conversion Formula (Fliegel-Van Flandern Algorithm)

Given year $Y$, month $M \in [1, 12]$, and day $D \in [1, 31]$:

$$a = \left\lfloor \frac{14 - M}{12} \right\rfloor$$
$$y = Y + 4800 - a$$
$$m = M + 12a - 3$$
$$JDN = D + \left\lfloor \frac{153m + 2}{5} \right\rfloor + 365y + \left\lfloor \frac{y}{4} \right\rfloor - \left\lfloor \frac{y}{100} \right\rfloor + \left\lfloor \frac{y}{400} \right\rfloor - 32045$$

In C3:
```c
fn int date_to_jdn(int year, int month, int day)
{
    int a = (14 - month) / 12;
    int y = year + 4800 - a;
    int m = month + 12 * a - 3;
    return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045;
}
```

### Strict Monotonic Property
For any two consecutive calendar dates $d_1$ and $d_2 = d_1 + 1\text{ day}$:
$$JDN(d_2) - JDN(d_1) \equiv 1$$
This holds true across month transitions, leap years, century boundaries, and 400-year Gregorian cycles.

---

## 3. Inverting JDN back to Gregorian Calendar

When rendering or serializing tasks (e.g. formatting dates or stamping completion dates), the engine converts the integer JDN back into $(Year, Month, Day)$ in constant time using the **Richards-Hatcher Algorithm**:

```c
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
```

---

## 4. Query Complexity in Integer Space

Because dates are represented as 32-bit signed integers:

| Query Type | Evaluation Logic | Complexity |
| :--- | :--- | :--- |
| **Tasks for Today** | `task.effective_jdn == current_system_jdn` | $O(1)$ per task / $O(K)$ via index |
| **Due this Week** | `task.effective_jdn >= today && task.effective_jdn <= today + 6` | $O(1)$ bounds check |
| **Interval Range** | `task.effective_jdn >= start_jdn && task.effective_jdn <= end_jdn` | $O(1)$ bounds check |
| **Days Remaining** | `task.effective_jdn - current_system_jdn` | $O(1)$ arithmetic subtraction |

### Effective Date Resolution (Option A)

The engine evaluates a task's effective date using the following precedence:
```c
fn int Task.get_effective_jdn(Task* self)
{
    // Priority 1: Explicit due:YYYY-MM-DD tag
    if (self.due_jdn != 0) return self.due_jdn;
    // Priority 2: Creation date fallback
    return self.creation_jdn;
}
```
