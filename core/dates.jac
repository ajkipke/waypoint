"""Pure date and duration helpers shared by the coach, planner and CLI."""
import datetime;

"""Parse an ISO date, returning None for blank or malformed input."""
def to_date(value: str) -> datetime.date | None {
    try {
        return datetime.date.fromisoformat(value.strip());
    } except ValueError {
        return None;
    }
}

"""Days from today until due (negative when overdue); None if undated."""
def days_left(due: str, today: str) -> int | None {
    d = to_date(due);
    t = to_date(today);
    if d is None or t is None {
        return None;
    }
    return (d - t).days;
}

def due_label(due: str, today: str) -> str {
    left = days_left(due, today);
    if left is None {
        return "";
    }
    if left < -1 {
        return f"{-left}d overdue";
    }
    if left == -1 {
        return "Yesterday";
    }
    if left == 0 {
        return "Today";
    }
    if left == 1 {
        return "Tomorrow";
    }
    d = to_date(due);
    if d and left < 7 {
        return d.strftime("%a");
    }
    return d.strftime("%b %-d") if d else due;
}

def human_minutes(total: int) -> str {
    if total < 60 {
        return f"{total}m";
    }
    return f"{total // 60}h" + (f" {total % 60}m" if total % 60 else "");
}

