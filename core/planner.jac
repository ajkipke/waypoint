"""Waypoint planner: the persistent, per-user planning graph.

Every endpoint is `def:protect`, so each signed-in user works on their own
root. Web, mobile and CLI all call these same functions.
"""
import re;
import datetime;
import from jaclang.runtime.runtime { JacRuntime }
import from core.dates { to_date, days_left, due_label, human_minutes }
import from core.coach {
    StepView,
    TaskView,
    Draft,
    Plan,
    Breakdown,
    parse_quick,
    resolve_date,
    build_plan,
    breakdown
}

glob PALETTE: list[str] = [
    "#2f4bd8",
    "#d9480f",
    "#2b8a3e",
    "#ae3ec9",
    "#e67700",
    "#0c8599",
    "#c2255c",
    "#5f3dc4"
];

node Settings {
    has username: str = "",
        capacity: int = 180,
        day_start: str = "09:00",
        next_num: int = 1;
}

node Course {
    has name: str,
        color: str = "#64748b";
}

node Task {
    has num: int,
        title: str,
        course: str = "",
        due: str = "",
        priority: int = 2,
        minutes: int = 30,
        notes: str = "",
        done: bool = False,
        done_on: str = "",
        created: str = "";
}

node Step {
    has text: str,
        done: bool = False,
        order: int = 0;
}

node Habit {
    has name: str,
        days: list[str] = [],
        created: str = "";
}

obj CourseView {
    has name: str = "",
        color: str = "#64748b",
        open: int = 0;
}

obj HabitView {
    has id: str = "",
        name: str = "",
        done_today: bool = False,
        streak: int = 0,
        best: int = 0,
        last7: list[bool] = [],
        total: int = 0;
}

obj Day {
    has date: str = "",
        label: str = "",
        tasks: list[TaskView] = [],
        minutes: int = 0,
        load: str = "free";
}

obj Stats {
    has done_today: int = 0,
        done_week: int = 0,
        open: int = 0,
        overdue: int = 0,
        focus_week: str = "0m",
        best_streak: int = 0;
}

obj Board {
    has viewer: str = "",
        today: str = "",
        today_label: str = "",
        tasks: list[TaskView] = [],
        done: list[TaskView] = [],
        courses: list[CourseView] = [],
        habits: list[HabitView] = [],
        plan: Plan = Plan(),
        week: list[Day] = [],
        stats: Stats = Stats(),
        capacity: int = 180,
        day_start: str = "09:00";
}

# ---------------------------------------------------------------- helpers

def today_or(value: str = "") -> str {
    return value if to_date(value) else datetime.date.today().isoformat();
}

def settings -> Settings {
    found = [root-->[?:Settings]];
    if found {
        return found[0];
    }
    return root ++> Settings();
}

def course_color(name: str) -> str {
    for c in [root-->[?:Course]] {
        if c.name.lower() == name.lower() {
            return c.color;
        }
    }
    return "#64748b";
}

"""Return the canonical course name, creating the course with the next palette color."""
def ensure_course(name: str) -> str {
    clean = name.strip().lstrip("#")[:24];
    if not clean {
        return "";
    }
    courses = [root-->[?:Course]];
    for c in courses {
        if c.name.lower() == clean.lower() {
            return c.name;
        }
    }
    root ++> Course(name=clean, color=PALETTE[len(courses) % len(PALETTE)]);
    return clean;
}

def find_task(ref: str) -> Task {
    key = ref.strip().lstrip("#");
    for t in [root-->[?:Task]] {
        if jid(t) == key or str(t.num) == key {
            return t;
        }
    }
    raise ValueError(f"No task matches '{ref}'.");
}

def find_habit(ref: str) -> Habit {
    key = ref.strip().lower();
    habits = [root-->[?:Habit]];
    for h in habits {
        if jid(h) == ref.strip() or h.name.lower() == key {
            return h;
        }
    }
    matches = [h for h in habits if h.name.lower().startswith(key)];
    if len(matches) == 1 {
        return matches[0];
    }
    raise ValueError(f"No single habit matches '{ref}'.");
}

def steps_of(t: Task) -> list[Step] {
    return sorted([t-->[?:Step]], key=lambda (s: Step) -> int { return s.order; });
}

def view(t: Task, today: str) -> TaskView {
    steps = steps_of(t);
    left = days_left(t.due, today);
    return TaskView(
        id=jid(t),
        num=t.num,
        title=t.title,
        course=t.course,
        color=course_color(t.course) if t.course else "#64748b",
        due=t.due,
        due_label=due_label(t.due, today),
        priority=t.priority,
        minutes=t.minutes,
        notes=t.notes,
        done=t.done,
        done_on=t.done_on,
        overdue=not t.done and left is not None and left < 0,
        steps=[StepView(id=jid(s), text=s.text, done=s.done) for s in steps],
        steps_done=len([s for s in steps if s.done])
    );
}

def streak_of(days: list[str], today: str) -> int {
    marked = set(days);
    cursor = to_date(today) or datetime.date.today();
    if cursor.isoformat() not in marked {
        cursor = cursor - datetime.timedelta(days=1);
    }
    count = 0;
    while cursor.isoformat() in marked {
        count += 1;
        cursor = cursor - datetime.timedelta(days=1);
    }
    return count;
}

def best_streak_of(days: list[str]) -> int {
    best = 0;
    run = 0;
    prev: datetime.date | None = None;
    for d in sorted({x for x in days if to_date(x)}) {
        cur = to_date(d);
        if cur is None {
            continue;
        }
        run = run + 1 if prev is not None and (cur - prev).days == 1 else 1;
        best = max(best, run);
        prev = cur;
    }
    return best;
}

def habit_view(h: Habit, today: str) -> HabitView {
    t = to_date(today) or datetime.date.today();
    marked = set(h.days);
    return HabitView(
        id=jid(h),
        name=h.name,
        done_today=today in marked,
        streak=streak_of(h.days, today),
        best=best_streak_of(h.days),
        last7=[
            (t - datetime.timedelta(days=6 - i)).isoformat() in marked
            for i in range(7)
        ],
        total=len(marked)
    );
}

def check_title(title: str) -> str {
    clean = " ".join(title.split());
    if not clean or len(clean) > 140 {
        raise ValueError("Give the task a name, like 'Lab 4' or 'Read chapter 5'.");
    }
    return clean;
}

def check_due(due: str) -> str {
    clean = due.strip();
    if not clean {
        return "";
    }
    resolved = resolve_date(clean, today_or());
    if not resolved {
        raise ValueError(
            f"I couldn't understand the due date '{clean}'. Try: today, tomorrow, fri, or 10/12."
        );
    }
    return resolved;
}

def make_task(
    title: str, course: str, due: str, priority: int, minutes: int, notes: str
) -> Task {
    s = settings();
    t = root ++> Task(
        num=s.next_num,
        title=check_title(title),
        course=ensure_course(course),
        due=check_due(due),
        priority=max(1, min(int(priority), 3)),
        minutes=max(5, min(int(minutes), 600)),
        notes=notes.strip()[:1000],
        created=datetime.datetime.now().isoformat(timespec="seconds")
    );
    s.next_num = s.next_num + 1;
    return t;
}

# -------------------------------------------------------------- endpoints

def:protect join(username: str) -> str {
    manager = JacRuntime.get_user_manager(JacRuntime.get_base_path_dir() or ".");
    user = manager.find_user_by_identity(username.strip());
    if not user or manager.get_root_id(str(user["user_id"])) != jid(root) {
        raise ValueError("This username does not belong to your signed-in account.");
    }
    name = manager.get_username(str(user["user_id"])) or username.strip();
    settings().username = name;
    return name;
}

def:protect add_task(
    title: str,
    course: str = "",
    due: str = "",
    priority: int = 2,
    minutes: int = 30,
    notes: str = ""
) -> TaskView {
    return view(make_task(title, course, due, priority, minutes, notes), today_or());
}

def:protect quick_add(text: str, today: str = "") -> TaskView {
    day = today_or(today);
    draft: Draft = parse_quick(text, day);
    return view(
        make_task(draft.title, draft.course, draft.due, draft.priority, draft.minutes, ""),
        day
    );
}

def:protect update_task(
    ref: str,
    title: str,
    course: str = "",
    due: str = "",
    priority: int = 2,
    minutes: int = 30,
    notes: str = ""
) -> TaskView {
    t = find_task(ref);
    t.title = check_title(title);
    t.course = ensure_course(course);
    t.due = check_due(due);
    t.priority = max(1, min(int(priority), 3));
    t.minutes = max(5, min(int(minutes), 600));
    t.notes = notes.strip()[:1000];
    return view(t, today_or());
}

def:protect toggle_task(ref: str, today: str = "") -> TaskView {
    day = today_or(today);
    t = find_task(ref);
    t.done = not t.done;
    t.done_on = day if t.done else "";
    return view(t, day);
}

def:protect snooze_task(ref: str, days: int = 1, today: str = "") -> TaskView {
    day = today_or(today);
    t = find_task(ref);
    base = to_date(t.due) or to_date(day);
    if base is None {
        raise ValueError("Cannot snooze this task.");
    }
    start = max(base, to_date(day) or base);
    t.due = (start + datetime.timedelta(days=max(1, min(days, 60)))).isoformat();
    return view(t, day);
}

def:protect delete_task(ref: str) -> bool {
    t = find_task(ref);
    for s in [t-->[?:Step]] {
        del s;
    }
    del t;
    return True;
}

def:protect break_down(ref: str) -> TaskView {
    t = find_task(ref);
    result: Breakdown = breakdown(
        (f"[{t.course}] " if t.course else "") + t.title, t.minutes
    );
    start = len([t-->[?:Step]]);
    for (i, text) in enumerate(result.steps) {
        t ++> Step(text=text[:140], order=start + i);
    }
    return view(t, today_or());
}

def:protect add_step(ref: str, text: str) -> TaskView {
    t = find_task(ref);
    clean = text.strip()[:140];
    if not clean {
        raise ValueError("Write a step first.");
    }
    t ++> Step(text=clean, order=len([t-->[?:Step]]));
    return view(t, today_or());
}

def:protect toggle_step(ref: str, step_id: str) -> TaskView {
    t = find_task(ref);
    for s in [t-->[?:Step]] {
        if jid(s) == step_id {
            s.done = not s.done;
            return view(t, today_or());
        }
    }
    raise ValueError("That step no longer exists.");
}

def:protect remove_step(ref: str, step_id: str) -> TaskView {
    t = find_task(ref);
    for s in [t-->[?:Step]] {
        if jid(s) == step_id {
            del s;
            return view(t, today_or());
        }
    }
    raise ValueError("That step no longer exists.");
}

def:protect add_course(name: str) -> str {
    clean = ensure_course(name);
    if not clean {
        raise ValueError("Name the course first.");
    }
    return clean;
}

def:protect remove_course(name: str) -> bool {
    for c in [root-->[?:Course]] {
        if c.name.lower() == name.strip().lower() {
            for t in [root-->[?:Task]] {
                if t.course == c.name {
                    t.course = "";
                }
            }
            del c;
            return True;
        }
    }
    raise ValueError(f"No course named '{name}'.");
}

def:protect add_habit(name: str) -> HabitView {
    clean = " ".join(name.split())[:40];
    if not clean {
        raise ValueError("Name the habit first.");
    }
    if any(h.name.lower() == clean.lower() for h in [root-->[?:Habit]]) {
        raise ValueError(f"You already track '{clean}'.");
    }
    h = root ++> Habit(
        name=clean, created=datetime.datetime.now().isoformat(timespec="seconds")
    );
    return habit_view(h, today_or());
}

def:protect toggle_habit(ref: str, day: str = "", today: str = "") -> HabitView {
    now = today_or(today);
    target = day if to_date(day) else now;
    h = find_habit(ref);
    if target in h.days {
        h.days = [d for d in h.days if d != target];
    } else {
        h.days = sorted(h.days + [target])[-400:];
    }
    return habit_view(h, now);
}

def:protect delete_habit(ref: str) -> bool {
    h = find_habit(ref);
    del h;
    return True;
}

def:protect set_capacity(minutes: int, day_start: str = "09:00") -> int {
    if not re.fullmatch(r"\d{1,2}:\d{2}", day_start.strip()) {
        raise ValueError("Use HH:MM for your start time.");
    }
    s = settings();
    s.capacity = max(30, min(minutes, 16 * 60));
    s.day_start = day_start.strip();
    return s.capacity;
}

def load_label(load: int, capacity: int) -> str {
    if load == 0 {
        return "free";
    }
    if load <= capacity // 2 {
        return "light";
    }
    return "full" if load <= capacity else "over";
}

def:protect load_board(today: str = "", now: str = "") -> Board {
    day = today_or(today);
    t0 = to_date(day) or datetime.date.today();
    clock = now or datetime.datetime.now().strftime("%H:%M");
    s = settings();
    all_tasks = [view(t, day) for t in [root-->[?:Task]]];
    open_tasks = [t for t in all_tasks if not t.done];
    week_ago = (t0 - datetime.timedelta(days=6)).isoformat();
    done_recent = sorted(
        [t for t in all_tasks if t.done and t.done_on >= week_ago],
        key=lambda (t: TaskView) -> str { return t.done_on; },
        reverse=True
    );
    plan: Plan = build_plan(
        all_tasks, day, capacity=s.capacity, day_start=s.day_start, now=clock
    );
    open_tasks.sort(
        key=lambda (t: TaskView) -> tuple { return (t.due == "", t.due, -t.priority, t.num); }
    );
    week: list[Day] = [];
    for i in range(7) {
        date = t0 + datetime.timedelta(days=i);
        due_here = [
            t
            for t in open_tasks
            if t.due == date.isoformat() or (i == 0 and t.overdue)
        ];
        load = sum(t.minutes for t in due_here);
        week.append(
            Day(
                date=date.isoformat(),
                label=["Today", "Tomorrow"][i] if i < 2 else date.strftime("%a %-d"),
                tasks=due_here,
                minutes=load,
                load=load_label(load, s.capacity)
            )
        );
    }
    habits = [habit_view(h, day) for h in [root-->[?:Habit]]];
    courses = [
        CourseView(
            name=c.name,
            color=c.color,
            open=len([t for t in open_tasks if t.course == c.name])
        )
        for c in [root-->[?:Course]]
    ];
    return Board(
        viewer=s.username,
        today=day,
        today_label=t0.strftime("%A, %B %-d"),
        tasks=open_tasks,
        done=done_recent[:30],
        courses=sorted(
            courses, key=lambda (c: CourseView) -> str { return c.name.lower(); }
        ),
        habits=sorted(
            habits, key=lambda (h: HabitView) -> str { return h.name.lower(); }
        ),
        plan=plan,
        week=week,
        stats=Stats(
            done_today=len([t for t in done_recent if t.done_on == day]),
            done_week=len(done_recent),
            open=len(open_tasks),
            overdue=len([t for t in open_tasks if t.overdue]),
            focus_week=human_minutes(sum(t.minutes for t in done_recent)),
            best_streak=max([h.streak for h in habits], `default=0)
        ),
        capacity=s.capacity,
        day_start=s.day_start
    );
}
