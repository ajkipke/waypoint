import argparse;
import asyncio;
import getpass;
import json;
import os;
import sys;
import urllib.request;
import from pathlib { Path }
import from jaclang.server { sv_client }
import from core.planner {
    join,
    quick_add,
    toggle_task,
    snooze_task,
    delete_task,
    break_down,
    add_habit,
    toggle_habit,
    load_board
}

glob COLOR: bool = sys.stdout.isatty() and not os.environ.get("NO_COLOR");

def paint(text: str, code: str) -> str {
    return f"\033[{code}m{text}\033[0m" if COLOR else text;
}

def auth_request(base: str, username: str, password: str, register: bool) -> str {
    identity = {"type": "username", "value": username};
    body: dict[str, any] = {"credential": {"type": "password", "password": password}};
    if register {
        body["identities"] = [identity];
    } else {
        body["identity"] = identity;
    }
    request = urllib.request.Request(
        base + "/user/" + ("register" if register else "login"),
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"}
    );
    try {
        with urllib.request.urlopen(request, timeout=15) as response {
            return str(json.loads(response.read())["data"]["token"]);
        }
    } except urllib.error.HTTPError as e {
        detail = json.loads(e.read() or b"{}").get("error") or {};
        raise ValueError(detail.get("message") or f"Sign-in failed ({e.code}).");
    }
}

def task_line(t: any) -> str {
    mark = paint("✓", "32") if t.done else "○";
    due = "";
    if t.due_label {
        due = "  " + paint(t.due_label, "31;1" if t.overdue else "36");
    }
    course = f"  [{t.course}]" if t.course else "";
    flag = paint("  HIGH", "31") if t.priority == 3 else "";
    steps = f"  {t.steps_done}/{len(t.steps)} steps" if t.steps else "";
    return f"{mark} {paint('#' + str(t.num), '2'):>4} {t.title}{paint(course, '35')}{due}{flag}  {paint(str(t.minutes) + 'm', '2')}{steps}";
}

async def main -> int {
    parser = argparse.ArgumentParser(
        prog="waypoint",
        description="Waypoint planner from your terminal.",
        epilog='examples:  add "Lab 4 #EECS281 fri !high 90m"   done 3   today   check gym'
    );
    parser.add_argument(
        "--url", `default=os.environ.get("WAYPOINT_URL", "http://127.0.0.1:8000")
    );
    parser.add_argument(
        "command",
        choices=[
            "login",
            "register",
            "logout",
            "today",
            "tasks",
            "week",
            "add",
            "done",
            "snooze",
            "delete",
            "break",
            "habits",
            "habit",
            "check"
        ]
    );
    parser.add_argument("value", nargs="*");
    args = parser.parse_args();
    value = " ".join(args.value).strip();
    base = str(args.url).rstrip("/");
    session = Path(
        os.environ.get("WAYPOINT_SESSION", str(Path.home() / ".waypoint.json"))
    );
    os.environ["JAC_APP_PLANNER_URL"] = base + "/api/planner";
    try {
        if args.command == "logout" {
            session.unlink(missing_ok=True);
            print("Signed out.");
            return 0;
        }
        if args.command in ["login", "register"] {
            if not value {
                parser.error(args.command + " needs a username");
            }
            password = os.environ.get("WAYPOINT_PASSWORD")
                or getpass.getpass("Password: ");
            token = auth_request(base, value, password, args.command == "register");
            sv_client.set_bearer_token(token);
            name = await join(value);
            fd = os.open(str(session), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600);
            with os.fdopen(fd, "w") as handle {
                json.dump({"url": base, "token": token}, handle);
            }
            print(f"Signed in as {name}. Try: waypoint today");
            return 0;
        }
        if not session.exists() {
            raise ValueError("Not signed in. Run: login <username>");
        }
        saved = json.loads(session.read_text());
        if saved.get("url") != base {
            raise ValueError(f"Your session is for {saved.get('url')}. Run login again.");
        }
        sv_client.set_bearer_token(str(saved["token"]));
        needs_value = ["add", "done", "snooze", "delete", "break", "habit", "check"];
        if args.command in needs_value and not value {
            parser.error(args.command + " needs a task number, text or habit name");
        }
        if args.command == "add" {
            t = await quick_add(value, "");
            print("Added " + task_line(t));
        } elif args.command == "done" {
            t = await toggle_task(value, "");
            print(("Completed " if t.done else "Reopened ") + task_line(t));
        } elif args.command == "snooze" {
            t = await snooze_task(value, 1, "");
            print("Moved " + task_line(t));
        } elif args.command == "delete" {
            await delete_task(value);
            print("Deleted #" + value.lstrip("#"));
        } elif args.command == "break" {
            t = await break_down(value);
            print(task_line(t));
            for s in t.steps {
                print(("   ✓ " if s.done else "   · ") + s.text);
            }
        } elif args.command == "habit" {
            h = await add_habit(value);
            print(f"Tracking {h.name}. Check in with: check {h.name.lower()}");
        } elif args.command == "check" {
            h = await toggle_habit(value, "", "");
            print(
                f"{h.name}: {'checked in' if h.done_today else 'unchecked'} · "
                    + paint(f"{h.streak} day streak", "33")
            );
        } else {
            board = await load_board("", "");
            if args.command == "today" {
                print(paint(board.today_label, "1") + "  " + paint(board.plan.headline, "2"));
                for b in board.plan.blocks {
                    when = f"{b.start}-{b.end}" if b.start else "   done   ";
                    title = paint(b.title, "2;9") if b.done else b.title;
                    print(f"  {paint(when, '34')}  #{b.num} {title}  {paint(b.reason, '2')}");
                }
                for t in board.plan.at_risk {
                    print(paint(f"  won't fit: #{t.num} {t.title} (snooze {t.num})", "31"));
                }
                for h in board.habits {
                    print(
                        f"  {'✓' if h.done_today else '○'} habit {h.name}  "
                            + paint(f"{h.streak}d streak", "33")
                    );
                }
            } elif args.command == "tasks" {
                for t in board.tasks {
                    print(task_line(t));
                }
                if not board.tasks {
                    print("No open tasks. Add one: add \"Essay draft #ENGL125 fri 2h\"");
                }
            } elif args.command == "week" {
                for d in board.week {
                    load = paint(d.load, "31" if d.load == "over" else "2");
                    print(paint(f"{d.label:<10}", "1") + f" {d.minutes:>4}m  {load}");
                    for t in d.tasks {
                        print("    " + task_line(t));
                    }
                }
            } else {
                for h in board.habits {
                    dots = "".join("●" if on else "·" for on in h.last7);
                    print(f"{'✓' if h.done_today else '○'} {h.name:<16} {dots}  {h.streak}d streak (best {h.best})");
                }
                if not board.habits {
                    print("No habits yet. Add one: habit Gym");
                }
            }
        }
        return 0;
    } except Exception as e {
        message = str(e);
        if "401" in message or "UNAUTHORIZED" in message.upper() {
            message = "Session expired. Run: login <username>";
        }
        print("waypoint: " + message, file=sys.stderr);
        return 1;
    }
}

with entry:__main__ {
    sys.`exit(asyncio.run(main()));
}
