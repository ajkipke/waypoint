"""Waypoint coach: pure planning logic used by the planner service.

Parses quick-add text, ranks open work by urgency, packs a realistic day
into time blocks, and breaks big tasks into steps (curated templates).
"""
import re;
import datetime;
import from core.dates { to_date, days_left, due_label, human_minutes }

glob WEEKDAYS: list[str] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

obj StepView {
    has id: str = "",
        text: str = "",
        done: bool = False;
}

obj TaskView {
    has id: str = "",
        num: int = 0,
        title: str = "",
        course: str = "",
        color: str = "#64748b",
        due: str = "",
        due_label: str = "",
        priority: int = 2,
        minutes: int = 30,
        notes: str = "",
        done: bool = False,
        done_on: str = "",
        overdue: bool = False,
        steps: list[StepView] = [],
        steps_done: int = 0;
}

obj Draft {
    has title: str = "",
        course: str = "",
        due: str = "",
        priority: int = 2,
        minutes: int = 30,
        hints: list[str] = [];
}

obj Block {
    has task_id: str = "",
        num: int = 0,
        title: str = "",
        course: str = "",
        color: str = "#64748b",
        start: str = "",
        end: str = "",
        minutes: int = 0,
        reason: str = "",
        done: bool = False;
}

obj Plan {
    has blocks: list[Block] = [],
        at_risk: list[TaskView] = [],
        planned_minutes: int = 0,
        capacity: int = 180,
        headline: str = "";
}

obj Breakdown {
    has steps: list[str] = [],
        source: str = "template";
}

"""Resolve a date word (today, fri, 10/12, 2026-10-12, +3d) relative to today."""
def resolve_date(word: str, today: str) -> str {
    t = to_date(today) or datetime.date.today();
    w = word.lower().strip().removeprefix("due:").removeprefix("@");
    if w in ["today", "tod", "tonight", "eod"] {
        return t.isoformat();
    }
    if w in ["tomorrow", "tmr", "tmrw", "tom"] {
        return (t + datetime.timedelta(days=1)).isoformat();
    }
    if w in ["yesterday", "yday"] {
        return (t - datetime.timedelta(days=1)).isoformat();
    }
    if w in ["nextweek", "next-week"] {
        return (t + datetime.timedelta(days=7)).isoformat();
    }
    if w[:3] in WEEKDAYS and (len(w) == 3 or w.endswith("day") or w in ["tues", "thur", "thurs"]) {
        ahead = (WEEKDAYS.index(w[:3]) - t.weekday()) % 7;
        return (t + datetime.timedelta(days=ahead)).isoformat();
    }
    rel = re.fullmatch(r"\+(\d{1,3})(d|w)?", w);
    if rel {
        n = int(rel.group(1)) * (7 if rel.group(2) == "w" else 1);
        return (t + datetime.timedelta(days=n)).isoformat();
    }
    if to_date(w) {
        return w;
    }
    md = re.fullmatch(r"(\d{1,2})/(\d{1,2})", w);
    if md {
        try {
            d = datetime.date(t.year, int(md.group(1)), int(md.group(2)));
            if (t - d).days > 60 {
                d = datetime.date(t.year + 1, d.month, d.day);
            }
            return d.isoformat();
        } except ValueError {
            return "";
        }
    }
    return "";
}

"""Read a duration token like 45m, 2h, 1.5h or 1h30m into minutes (0 if not one)."""
def parse_minutes(word: str) -> int {
    m = re.fullmatch(r"(?:(\d+(?:\.\d+)?)h(?:rs?)?)?(?:(\d+)m(?:in)?)?", word.lower());
    if m is None {
        return 0;
    }
    (h, mm) = m.groups();
    if not h and not mm {
        return 0;
    }
    return int(float(h or "0") * 60) + int(mm or "0");
}

def parse_quick(text: str, today: str) -> Draft {
    draft = Draft();
    words: list[str] = [];
    for word in text.split() {
        low = word.lower();
        if low.startswith("#") and len(word) > 1 {
            draft.course = word[1:];
            draft.hints = draft.hints + [f"course {word[1:]}"];
        } elif low in ["!", "!low", "!1", "p3"] {
            draft.priority = 1;
            draft.hints = draft.hints + ["low priority"];
        } elif low in ["!!", "!med", "!2", "p2"] {
            draft.priority = 2;
            draft.hints = draft.hints + ["medium priority"];
        } elif low in ["!!!", "!high", "!3", "!hi", "p1", "!urgent"] {
            draft.priority = 3;
            draft.hints = draft.hints + ["high priority"];
        } elif parse_minutes(low) > 0 {
            draft.minutes = min(parse_minutes(low), 600);
            draft.hints = draft.hints + [f"{draft.minutes} min"];
        } elif resolve_date(low, today) and not draft.due {
            draft.due = resolve_date(low, today);
            draft.hints = draft.hints + [f"due {due_label(draft.due, today)}"];
        } else {
            words.append(word);
        }
    }
    draft.title = " ".join(words).strip();
    return draft;
}

"""Higher means do it sooner: blends deadline pressure, priority and quick wins."""
def urgency(t: TaskView, today: str) -> float {
    score = {1: 8.0, 2: 18.0, 3: 30.0}.get(t.priority, 18.0);
    left = days_left(t.due, today);
    if left is None {
        score += 2;
    } elif left < 0 {
        score += 60 + 5 * min(-left, 6);
    } elif left == 0 {
        score += 45;
    } elif left == 1 {
        score += 35;
    } elif left <= 3 {
        score += 24;
    } elif left <= 7 {
        score += 12;
    } else {
        score += 4;
    }
    if t.minutes <= 20 {
        score += 3;
    }
    return score;
}

def reason_for(t: TaskView, today: str) -> str {
    left = days_left(t.due, today);
    if left is not None and left < 0 {
        return f"Overdue by {-left} day" + ("" if left == -1 else "s");
    }
    if left == 0 {
        return "Due today";
    }
    if left == 1 {
        return "Due tomorrow";
    }
    if t.priority == 3 {
        return "High priority";
    }
    if left is not None and left <= 3 {
        return f"Due in {left} days";
    }
    if t.minutes <= 20 {
        return "Quick win";
    }
    return "Keeps you ahead";
}

def clock(minutes: int) -> str {
    m = max(0, min(minutes, 24 * 60 - 1));
    return f"{m // 60:02d}:{m % 60:02d}";
}

def to_minutes(hhmm: str, fallback: int) -> int {
    m = re.fullmatch(r"(\d{1,2}):(\d{2})", hhmm.strip());
    if not m {
        return fallback;
    }
    return min(int(m.group(1)), 23) * 60 + min(int(m.group(2)), 59);
}

def rank(tasks: list[TaskView], today: str) -> list[TaskView] {
    return sorted(
        [t for t in tasks if not t.done],
        key=lambda (t: TaskView) -> float { return -urgency(t, today); }
    );
}

"""Greedily fit the most urgent open work into today's capacity, with breaks."""
def build_plan(
    tasks: list[TaskView],
    today: str,
    capacity: int = 180,
    day_start: str = "09:00",
    now: str = ""
) -> Plan {
    cursor = to_minutes(day_start, 9 * 60);
    if now {
        cursor = max(cursor, ((to_minutes(now, cursor) + 14) // 15) * 15);
    }
    plan = Plan(capacity=capacity);
    used = 0;
    since_break = 0;
    for t in rank(tasks, today) {
        size = max(5, t.minutes);
        if used + size > capacity or cursor + size > 23 * 60 {
            left = days_left(t.due, today);
            if left is not None and left <= 0 {
                plan.at_risk = plan.at_risk + [t];
            }
            continue;
        }
        if since_break >= 50 {
            cursor += 10;
            since_break = 0;
        }
        plan.blocks = plan.blocks
            + [
                Block(
                    task_id=t.id,
                    num=t.num,
                    title=t.title,
                    course=t.course,
                    color=t.color,
                    start=clock(cursor),
                    end=clock(cursor + size),
                    minutes=size,
                    reason=reason_for(t, today)
                )
            ];
        cursor += size;
        used += size;
        since_break += size;
    }
    for t in tasks {
        if t.done and t.done_on == today {
            plan.blocks = plan.blocks
                + [
                    Block(
                        task_id=t.id,
                        num=t.num,
                        title=t.title,
                        course=t.course,
                        color=t.color,
                        minutes=t.minutes,
                        reason="Done today",
                        done=True
                    )
                ];
        }
    }
    plan.planned_minutes = used;
    open_blocks = len([b for b in plan.blocks if not b.done]);
    if open_blocks == 0 and not plan.at_risk {
        plan.headline = "Nothing pressing. Enjoy the breathing room.";
    } else {
        plan.headline = f"{open_blocks} focus block" + ("" if open_blocks == 1 else "s")
            + f" · {human_minutes(used)} of {human_minutes(capacity)}";
        if plan.at_risk {
            plan.headline += f" · {len(plan.at_risk)} won't fit";
        }
    }
    return plan;
}

glob TEMPLATES: list[tuple[str, list[str]]] = [
    (
        r"exam|midterm|final|quiz|test\b",
        [
            "List every topic that will be covered",
            "Re-read lecture notes and mark weak spots",
            "Do a timed set of practice problems",
            "Review mistakes and redo them",
            "Make a one-page summary sheet"
        ]
    ),
    (
        r"essay|paper|report|write|writing|reflection|memo",
        [
            "Gather sources and jot key points",
            "Write a rough outline",
            "Draft the body without editing",
            "Revise for argument and flow",
            "Proofread, format and submit"
        ]
    ),
    (
        r"project|lab|homework|\bhw|pset|problem set|assignment|\bp\d|code|implement",
        [
            "Read the spec and note requirements",
            "Set up files and a minimal skeleton",
            "Implement the core logic",
            "Write tests and debug edge cases",
            "Clean up and submit"
        ]
    ),
    (
        r"read|chapter|article|textbook",
        [
            "Skim headings and summaries",
            "Read and annotate actively",
            "Write a 3-sentence summary"
        ]
    ),
    (
        r"present|slides|talk|pitch",
        [
            "Outline the story in 5 bullets",
            "Build the slides",
            "Rehearse out loud twice",
            "Polish timing and visuals"
        ]
    ),
    (
        r"apply|application|resume|cover letter|interview",
        [
            "Collect requirements and deadline",
            "Tailor resume to the role",
            "Draft the cover letter or answers",
            "Get feedback from one person",
            "Submit and log it"
        ]
    )
];

def template_steps(title: str, minutes: int) -> list[str] {
    low = title.lower();
    for (pattern, steps) in TEMPLATES {
        if re.search(pattern, low) {
            return list(steps);
        }
    }
    chunks = max(1, min(4, minutes // 25));
    return ["Define what “done” looks like"]
        + [f"Focus sprint {i + 1} (25 min)" for i in range(chunks)]
        + ["Review and wrap up"];
}

def breakdown(title: str, minutes: int = 30) -> Breakdown {
    return Breakdown(steps=template_steps(title, minutes), source="template");
}
