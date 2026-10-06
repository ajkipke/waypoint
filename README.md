# Waypoint: a personal planner in Jac

**Name:** Anya Kipke · **UMID:** _your UMID here_

Waypoint is a student planner for coursework, deadlines and habits. You type a
task in one line, and Waypoint turns your open work into a realistic, time-blocked
plan for today. The web app, mobile app and terminal CLI all share one server and
one plan.

## Main features

- **Simple add-task form** (web and phone): type what you need to do, then
  optionally pick a course, a due date (Today, Tomorrow, or type `fri` / `10/12`),
  a priority (Low / Normal / High) and roughly how long it will take.
- **One-line add in the terminal**: `./waypoint add "Lab 4 #EECS281 fri !high 90m"`
  adds "Lab 4" for EECS281, due Friday, high priority, taking 90 minutes.
  - `#course` sets the course; due date: `today`, `tomorrow`, `fri`, `+3d`, `10/12`
  - priority: `!high`, `!low`; time: `30m`, `2h`, `1h30m`; everything else is the task name
- **Today plan.** Open tasks are ranked by deadline pressure, priority and quick
  wins, then packed into time blocks starting from the current time. A 10-minute
  break is added after every 50 minutes of work, and the plan respects a daily
  capacity (3h by default). Overdue or due-today work that won't fit is flagged so
  you can push it to tomorrow.
- **Task breakdown.** "Break it down" turns a task into concrete steps (exam,
  essay, project, reading, presentation and application templates) that you check
  off one at a time.
- **Habits** with daily check-ins, a 7-day history, current streak and best streak.
- **Week view** (CLI) showing each day's workload against your capacity.
- **Accounts.** Every user's plan is private to their own login.

## Prerequisites

- Jac **0.37.23** (`jac --version`). The CLI, server and web app need nothing else.
- For the native mobile app only: Android Studio with an emulator (or a phone), or Xcode on macOS.

## Run the server and web app

From the repository root:

```bash
jac run
```

Open http://localhost:8000, choose **New here? Create an account**, and sign in.
Data is stored by the server in `.jac/data` and persists between runs.

## Mobile app

The mobile app (`mobile.jac`) is a React Native app built with Jac's mobUI. It uses
the same backend as the web app. On launch it asks for the server address, then
for your login.

**Browser preview (quickest):**

```bash
jac build --platform web mobile        # compile the mobile bundle (repeat after edits)
jac run --dev --platform web mobile    # serves the preview and its own API on the same project data
```

Open the address it prints (e.g. http://localhost:8003). For the server address,
enter **that same address** and sign in with your account. If you also want the
web app open at the same time, start it with `jac run --no-dev`, because two dev
servers in one project overwrite each other's files.

**Native Android / iOS:** start the server with `jac run`, then:

```bash
jac run --dev mobile                   # Metro; press a (Android) or i (iOS)
```

Server address: `http://10.0.2.2:8000` in the Android emulator, or
`http://<your-computer's-LAN-IP>:8000` on a real phone on the same Wi-Fi.
To package an app: `jac build --platform android mobile` or `jac build --platform ios mobile`.

## CLI

The server must be running (`jac run`). Use the `./waypoint` shortcut, or the
equivalent `jac run cli -- <command>`:

```bash
./waypoint register anya          # or: login anya (prompts for the password)
./waypoint add "Problem set 3 #MATH217 tomorrow 60m"
./waypoint today                  # time-blocked plan, at-risk tasks, habits
./waypoint tasks                  # every open task with its #number
./waypoint week                   # next 7 days and how loaded each day is
./waypoint done 3                 # complete (or reopen) task #3
./waypoint snooze 3               # push task #3 back a day
./waypoint break 3                # split task #3 into steps
./waypoint delete 3
./waypoint habit Gym              # start tracking a habit
./waypoint check gym              # check in for today
./waypoint habits                 # streaks and the last 7 days
./waypoint logout
```

The session is saved to `~/.waypoint.json` (owner-only permissions). Set
`WAYPOINT_URL` (or pass `--url`) to use a server other than http://127.0.0.1:8000.

## How the pieces fit together

```
 web.jac ─┐
          ├─ core/ui.jac (one responsive mobUI screen) ─┐
mobile.jac┘                                             ├─▶ core/planner.jac  (server)
 cli.jac ───────────────────────────────────────────────┘     │  per-user graph: Settings, Course,
                                                              │  Task ─▶ Step, Habit
                                                              └─ core/coach.jac  (planning logic)
                                                                 quick-add parser, ranking,
                                                                 day scheduler, breakdown templates
```

- **Server.** `core/planner.jac` is a Jac service app. Its `def:protect` functions
  (`quick_add`, `toggle_task`, `load_board`, …) become authenticated HTTP endpoints,
  and each user's data lives on their own graph root, so plans never mix.
- **Web and mobile.** Both entry points render the same `PlannerApp` component.
  It uses a wide layout in a desktop browser and a compact one on a phone. The
  mobile version adds a "connect to server" step.
- **CLI.** `cli.jac` imports the *same* server functions. Jac turns those imports
  into network calls to the running server, so the terminal goes through exactly
  the same logic as the apps.
- **Planning logic.** `core/coach.jac` and `core/dates.jac` hold pure functions
  (parsing, ranking, scheduling), so every client gets identical behavior.

**What makes it stand out:** the plan is *computed*, not just listed. Waypoint
decides what to do first, when, and what won't fit, from the live state shared by
all three clients. A task added in the terminal shows up on your phone as a time
block, and checking it off on your phone updates `./waypoint today`.

## Project layout

| Path | Purpose |
| --- | --- |
| `jac.toml` | Workspace: `web` (default app), `mobile`, `cli`, `planner` service |
| `core/planner.jac` | Persistent data model and authenticated endpoints |
| `core/coach.jac`, `core/dates.jac` | Quick-add parser, prioritizer, day scheduler, breakdowns |
| `core/ui.jac`, `core/theme.jac` | Shared mobUI screen and styles |
| `web.jac`, `mobile.jac`, `cli.jac` | Client entry points |
| `waypoint` | Shell shortcut for `jac run cli --` |
