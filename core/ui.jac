import from "@jac/mobui" {
    View,
    Text,
    TextInput,
    Pressable,
    ScrollView,
    useWindowDimensions
}
import from "@jac/runtime" {
    jacSetToken,
    __getApiBaseUrl,
    jacLogout,
    jacIsLoggedIn,
    __getLocalStorage,
    __setLocalStorage
}
import from core.planner {
    Board,
    Stats,
    join,
    quick_add,
    toggle_task,
    snooze_task,
    delete_task,
    break_down,
    toggle_step,
    add_habit,
    toggle_habit,
    delete_habit,
    load_board
}
import from core.coach { Plan, TaskView }
import from core.theme { S, C }

def Button(
    label: str, action: Callable, quiet: bool = False, disabled: bool = False
) -> JsxElement {
    return
        <Pressable
            accessibilityRole="button"
            accessibilityLabel={label}
            disabled={disabled}
            onPress={action}
            style={[
                S.button,
                S.quiet if quiet else {},
                {"opacity": 0.45 if disabled else 1}
            ]}
        >
            <Text style={[S.buttonText, S.quietText if quiet else {}]}>{label}</Text>
        </Pressable>;
}

def Chip(label: str, color: str) -> JsxElement {
    return
        <View style={[S.chip, {"backgroundColor": color}]}>
            <Text style={S.chipText}>{label}</Text>
        </View>;
}

def Check(on: bool, label: str, action: Callable) -> JsxElement {
    return
        <Pressable
            accessibilityRole="checkbox"
            accessibilityLabel={label}
            onPress={action}
            style={[S.check, S.checkOn if on else {}]}
        >
            <Text style={S.buttonText}>{"✓" if on else ""}</Text>
        </Pressable>;
}

def StatBox(value: str, label: str) -> JsxElement {
    return
        <View style={S.stat}>
            <Text style={S.statNum}>{value}</Text>
            <Text style={S.small}>{label}</Text>
        </View>;
}

def:pub PlannerApp(remote: bool = False) -> JsxElement {
    has board: Board = Board(plan=Plan(), stats=Stats()),
        username: str = "",
        password: str = "",
        draft: str = "",
        habit_draft: str = "",
        tab: str = "today",
        open_id: str = "",
        signup: bool = False,
        logged: bool = False,
        busy: bool = False,
        loading: bool = True,
        error: str = "",
        server: str = "",
        connected: bool = not remote;
    wide = useWindowDimensions().width >= 820;

    async def refresh {
        if not logged {
            loading = False;
            return;
        }
        loading = True;
        try {
            board = await load_board();
        } except Exception as e {
            if "401" in str(e) or "nauthorized" in str(e) or "UNAUTHORIZED" in str(e) {
                jacLogout();
                logged = False;
                error = "Your session expired. Sign in again.";
            } else {
                error = "Could not reach the server. Check your connection and try again.";
            }
        } finally {
            loading = False;
        }
    }

    async def connect {
        server = server.strip();
        if server.count("://") != 1
            or not (server.startswith("http://") or server.startswith("https://")) {
            error = "Enter a server address starting with http:// or https://.";
            return;
        }
        server = server.rstrip("/");
        globalThis.__JAC_API_BASE_URL__ = server;
        __setLocalStorage("waypoint_server", server);
        jacLogout();
        logged = False;
        connected = True;
        error = "";
        loading = False;
    }

    can with entry {
        logged = jacIsLoggedIn();
        username = __getLocalStorage("waypoint_username") or "";
        server = __getLocalStorage("waypoint_server") or "";
        if remote and __getLocalStorage("waypoint_server") {
            globalThis.__JAC_API_BASE_URL__ = server;
            connected = True;
        }
        if connected {
            refresh();
        } else {
            loading = False;
        }
    }

    async def authenticate {
        if busy {
            return;
        }
        busy = True;
        error = "";
        try {
            if not username.strip() or not password {
                error = "Enter a username and password.";
                return;
            }
            identity = {"type": "username", "value": username.strip()};
            payload: dict[str, any] = {
                "credential": {"type": "password", "password": password}
            };
            if signup {
                payload["identities"] = [identity];
            } else {
                payload["identity"] = identity;
            }
            response = await fetch(
                __getApiBaseUrl() + "/user/" + ("register" if signup else "login"),
                {
                    "method": "POST",
                    "headers": {"Content-Type": "application/json"},
                    "body": JSON.stringify(payload)
                }
            );
            result: any = await response.json();
            if not response.ok {
                error = result.error.message or "Could not sign in.";
                return;
            }
            jacSetToken(result.data.token);
            username = await join(username.strip());
            __setLocalStorage("waypoint_username", username);
            logged = True;
            password = "";
            await refresh();
        } except Exception {
            error = "Could not sign in. Check your connection and try again.";
        } finally {
            busy = False;
        }
    }

    async def act(kind: str, ref: str = "", extra: str = "") {
        if busy {
            return;
        }
        busy = True;
        error = "";
        try {
            if kind == "add" {
                await quick_add(draft);
                draft = "";
            } elif kind == "toggle" {
                await toggle_task(ref);
            } elif kind == "snooze" {
                await snooze_task(ref, 1);
            } elif kind == "delete" {
                await delete_task(ref);
                open_id = "";
            } elif kind == "breakdown" {
                await break_down(ref);
            } elif kind == "step" {
                await toggle_step(ref, extra);
            } elif kind == "habit" {
                await add_habit(habit_draft);
                habit_draft = "";
            } elif kind == "checkin" {
                await toggle_habit(ref);
            } elif kind == "unhabit" {
                await delete_habit(ref);
            }
            await refresh();
        } except Exception as e {
            error = str(e) or "That action did not complete. Try again.";
        } finally {
            busy = False;
        }
    }

    def logout {
        jacLogout();
        logged = False;
        password = "";
        board = Board(plan=Plan(), stats=Stats());
    }

    def TaskRow(t: TaskView) -> JsxElement {
        expanded = open_id == t.id;
        return
            <View key={t.id} style={S.card}>
                <View style={S.row}>
                    <Check
                        on={t.done}
                        label={"Complete " + t.title}
                        action={lambda { act("toggle", t.id); }}
                    />
                    <Pressable
                        style={{"flex": 1, "gap": 4}}
                        accessibilityLabel={"Details for " + t.title}
                        onPress={lambda { open_id = "" if expanded else t.id; }}
                    >
                        <Text style={S.name}>#{t.num} {t.title}</Text>
                        <View style={S.row}>
                            {<Text style={S.danger}>HIGH</Text>
                                if t.priority == 3
                                else None}
                            {<Chip label={t.course} color={t.color}/> if t.course else None}
                            {<Text style={S.danger if t.overdue else S.small}>
                                {t.due_label}
                            </Text>
                                if t.due_label
                                else None}
                            <Text style={S.small}>{t.minutes} min</Text>
                            {<Text style={S.small}>
                                {t.steps_done}/{len(t.steps)} steps
                            </Text>
                                if t.steps
                                else None}
                        </View>
                    </Pressable>
                </View>
                {<View style={S.stack}>
                    {for s in t.steps {
                        <View key={s.id} style={S.row}>
                            <Check
                                on={s.done}
                                label={"Step " + s.text}
                                action={lambda { act("step", t.id, s.id); }}
                            />
                            <Text style={S.body}>{s.text}</Text>
                        </View>
                    }}
                    <View style={S.row}>
                        {<Button
                            label="Break it down"
                            quiet={True}
                            action={lambda { act("breakdown", t.id); }}
                            disabled={busy}
                        />
                            if not t.steps
                            else None}
                        <Button
                            label="+1 day"
                            quiet={True}
                            action={lambda { act("snooze", t.id); }}
                            disabled={busy}
                        />
                        <Button
                            label="Delete"
                            quiet={True}
                            action={lambda { act("delete", t.id); }}
                            disabled={busy}
                        />
                    </View>
                </View>
                    if expanded and not t.done
                    else None}
            </View>;
    }

    def TodayTab -> JsxElement {
        return
            <View style={S.stack}>
                <Text style={S.subtitle}>{board.plan.headline}</Text>
                {for b in board.plan.blocks {
                    <View key={b.task_id} style={[S.card, {"opacity": 0.55 if b.done else 1}]}>
                        <View style={S.row}>
                            <Check
                                on={b.done}
                                label={"Complete " + b.title}
                                action={lambda { act("toggle", b.task_id); }}
                            />
                            <View style={{"flex": 1, "gap": 4}}>
                                <Text style={S.eyebrow}>
                                    {(b.start + " – " + b.end) if b.start else "DONE"}
                                </Text>
                                <Text style={S.name}>{b.title}</Text>
                                <View style={S.row}>
                                    {<Chip label={b.course} color={b.color}/>
                                        if b.course
                                        else None}
                                    <Text style={S.small}>
                                        {b.reason} · {b.minutes} min
                                    </Text>
                                </View>
                            </View>
                        </View>
                    </View>
                }}
                {<View style={[S.card, {"borderColor": "#f5c2c2"}]}>
                    <Text style={S.danger}>WON'T FIT TODAY</Text>
                    {for t in board.plan.at_risk {
                        <View key={t.id} style={S.between}>
                            <Text style={[S.body, {"flex": 1}]}>{t.title}</Text>
                            <Button
                                label="Move to tomorrow"
                                quiet={True}
                                action={lambda { act("snooze", t.id); }}
                                disabled={busy}
                            />
                        </View>
                    }}
                </View>
                    if board.plan.at_risk
                    else None}
                {<View style={S.card}>
                    <Text style={S.name}>A clear day.</Text>
                    <Text style={S.small}>
                        Add something above and Waypoint will slot it into your day.
                    </Text>
                </View>
                    if not board.plan.blocks
                    else None}
            </View>;
    }

    def TasksTab -> JsxElement {
        return
            <View style={S.stack}>
                {for t in board.tasks {
                    <TaskRow key={t.id} t={t}/>
                }}
                {<Text style={S.small}>No open tasks. Nice work.</Text>
                    if not board.tasks
                    else None}
                {<Text style={S.eyebrow}>DONE THIS WEEK</Text>
                    if board.done
                    else None}
                {for t in board.done {
                    <TaskRow key={t.id} t={t}/>
                }}
            </View>;
    }

    def HabitsTab -> JsxElement {
        return
            <View style={S.stack}>
                <View style={[S.card, S.row]}>
                    <TextInput
                        accessibilityLabel="New habit"
                        style={[S.input, {"flex": 1}]}
                        placeholder="New habit, e.g. Gym"
                        placeholderTextColor={C.muted}
                        value={habit_draft}
                        onChangeText={lambda (v: str) { habit_draft = v; }}
                        onSubmitEditing={lambda { act("habit"); }}
                    />
                    <Button
                        label="Track"
                        action={lambda { act("habit"); }}
                        disabled={busy or not habit_draft.strip()}
                    />
                </View>
                {for h in board.habits {
                    <View key={h.id} style={S.card}>
                        <View style={S.row}>
                            <Check
                                on={h.done_today}
                                label={"Check in " + h.name}
                                action={lambda { act("checkin", h.id); }}
                            />
                            <View style={{"flex": 1, "gap": 6}}>
                                <Text style={S.name}>{h.name}</Text>
                                <View style={S.row}>
                                    {for (i, on) in enumerate(h.last7) {
                                        <View
                                            key={str(i)}
                                            style={[
                                                S.dot,
                                                {"backgroundColor": C.accent if on else C.line}
                                            ]}
                                        />
                                    }}
                                    <Text style={S.small}>
                                        🔥 {h.streak} day streak · best {h.best}
                                    </Text>
                                </View>
                            </View>
                            <Button
                                label="Remove"
                                quiet={True}
                                action={lambda { act("unhabit", h.id); }}
                                disabled={busy}
                            />
                        </View>
                    </View>
                }}
                {<Text style={S.small}>Track a habit to start building streaks.</Text>
                    if not board.habits
                    else None}
            </View>;
    }

    return
        <ScrollView
            style={S.screen}
            contentContainerStyle={[S.page, {"maxWidth": 860}]}
            keyboardShouldPersistTaps="handled"
        >
            <View style={S.header}>
                <Text style={S.brand}>
                    waypoint
                    <Text style={S.quietText}>.</Text>
                </Text>
                {<Button label="Sign out" quiet={True} action={logout}/>
                    if logged
                    else None}
            </View>
            {<Text accessibilityRole="alert" style={S.error}>{error}</Text>
                if error
                else None}
            {<View style={S.card}>
                <Text style={S.name}>Connect to your Waypoint server</Text>
                <TextInput
                    accessibilityLabel="Server address"
                    style={S.input}
                    placeholder="http://10.0.2.2:8000 (Android emulator)"
                    placeholderTextColor={C.muted}
                    value={server}
                    autoCapitalize="none"
                    onChangeText={lambda (v: str) { server = v; }}
                />
                <Button label="Connect" action={connect}/>
            </View>
                if not connected
                else None}
            {<View style={S.card}>
                <Text style={S.title}>
                    {"Make a plan." if signup else "Welcome back."}
                </Text>
                <Text style={S.subtitle}>
                    Your tasks, schedule and habits on web, phone and terminal.
                </Text>
                <TextInput
                    accessibilityLabel="Username"
                    style={S.input}
                    placeholder="Username"
                    value={username}
                    autoCapitalize="none"
                    autoCorrect={False}
                    onChangeText={lambda (v: str) { username = v; }}
                />
                <TextInput
                    accessibilityLabel="Password"
                    style={S.input}
                    placeholder="Password"
                    value={password}
                    secureTextEntry={True}
                    onChangeText={lambda (v: str) { password = v; }}
                    onSubmitEditing={authenticate}
                />
                <Button
                    label={"Please wait…"
                        if busy
                        else "Create account" if signup else "Sign in"}
                    action={authenticate}
                    disabled={busy}
                />
                <Button
                    label={"I already have an account"
                        if signup
                        else "New here? Create an account"}
                    quiet={True}
                    disabled={busy}
                    action={lambda {
                        signup = not signup;
                        error = "";
                    }}
                />
            </View>
                if connected and not logged
                else None}
            {<View style={S.stack}>
                <View style={S.stack}>
                    <Text style={S.eyebrow}>
                        {board.today_label.upper() if board.today_label else "TODAY"}
                    </Text>
                    <Text accessibilityRole="header" style={S.title}>
                        Hi {board.viewer or username}, here's your day.
                    </Text>
                </View>
                <View style={[S.card, S.stack]}>
                    <View style={S.row}>
                        <TextInput
                            accessibilityLabel="Quick add"
                            style={[S.input, {"flex": 1, "minWidth": 200}]}
                            placeholder="Add a task…"
                            placeholderTextColor={C.muted}
                            value={draft}
                            onChangeText={lambda (v: str) { draft = v; }}
                            onSubmitEditing={lambda { act("add"); }}
                        />
                        <Button
                            label="Add"
                            action={lambda { act("add"); }}
                            disabled={busy or not draft.strip()}
                        />
                    </View>
                    <Text style={S.small}>
                        Try: Lab 4 #EECS281 fri !high 90m · tomorrow, +3d, 10/12 · 30m, 2h
                    </Text>
                </View>
                <View style={[S.row, {"flexWrap": "wrap"}]}>
                    <StatBox value={str(board.stats.done_today)} label="done today"/>
                    <StatBox value={str(board.stats.open)} label="open tasks"/>
                    <StatBox value={str(board.stats.overdue)} label="overdue"/>
                    <StatBox
                        value={str(board.stats.best_streak)}
                        label="best habit streak"
                    />
                </View>
                <View style={S.tabs}>
                    {for (key, name) in [
                        ("today", "Today"),
                        ("tasks", "Tasks"),
                        ("habits", "Habits")
                    ] {
                        <Pressable
                            key={key}
                            accessibilityRole="tab"
                            accessibilityLabel={name}
                            onPress={lambda { tab = key; }}
                            style={[S.tab, S.tabOn if tab == key else {}]}
                        >
                            <Text style={[S.name, {"color": C.accent if tab == key else C.muted}]}>
                                {name}
                            </Text>
                        </Pressable>
                    }}
                </View>
                {<Text style={S.small}>Loading your plan…</Text> if loading else None}
                {<TodayTab/> if tab == "today" else None}
                {<TasksTab/> if tab == "tasks" else None}
                {<HabitsTab/> if tab == "habits" else None}
            </View>
                if connected and logged
                else None}
            <View style={S.footer}>
                {<Button
                    label="Change server"
                    quiet={True}
                    action={lambda {
                        logout();
                        connected = False;
                    }}
                />
                    if remote and connected
                    else None}
                <Text style={S.small}>
                    Waypoint · {"wide" if wide else "compact"} layout · same plan on every device
                </Text>
            </View>
        </ScrollView>;
}
