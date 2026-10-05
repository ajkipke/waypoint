import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from jaclang.testing.testing { JacTestClient }

glob TODAY: str = "2026-10-05";

def call(client: JacTestClient, name: str, fields: dict[str, any] | None = None) -> any {
    response = client.post("/function/" + name, json=fields or {});
    assert response.ok , response.text;
    return response.data["result"];
}

def rejected(client: JacTestClient, name: str, fields: dict[str, any] | None = None) -> bool {
    return not client.post("/function/" + name, json=fields or {}).ok;
}

test "plans stay private, persist edits and drive the daily plan" {
    with TemporaryDirectory() as folder {
        client = JacTestClient.from_file(
            str(Path(__file__).with_name("planner.jac")), base_path=folder
        );
        try {
            assert rejected(client, "add_task", {"title": "anonymous"});
            for name in ["ana", "ben"] {
                assert client.register_user(name, "planner-secret-1").ok;
            }
            assert client.login("ana", "planner-secret-1").ok;
            assert call(client, "join", {"username": "ana"}) == "ana";
            assert rejected(client, "join", {"username": "ben"});
            assert rejected(client, "add_task", {"title": "   "});
            assert rejected(client, "add_task", {"title": "x", "due": "someday"});

            lab = call(
                client,
                "quick_add",
                {"text": "Lab 4 #EECS281 tomorrow !high 90m", "today": TODAY}
            );
            assert lab["num"] == 1 and lab["course"] == "EECS281";
            assert lab["due"] == "2026-10-06" and lab["priority"] == 3;
            essay = call(
                client,
                "add_task",
                {"title": "Essay draft", "course": "eecs281", "due": "2026-10-01"}
            );
            assert essay["num"] == 2 and essay["course"] == "EECS281";

            broken = call(client, "break_down", {"ref": "2"});
            assert len(broken["steps"]) >= 3;
            step = broken["steps"][0]["id"];
            assert call(client, "toggle_step", {"ref": "2", "step_id": step})["steps_done"] == 1;

            habit = call(client, "add_habit", {"name": "Gym"});
            assert rejected(client, "add_habit", {"name": "gym"});
            for d in ["2026-10-03", "2026-10-04", "2026-10-05"] {
                habit = call(client, "toggle_habit", {"ref": "gy", "day": d, "today": TODAY});
            }
            assert habit["streak"] == 3 and habit["done_today"];

            board = call(client, "load_board", {"today": TODAY, "now": "08:00"});
            assert board["viewer"] == "ana";
            assert board["stats"]["open"] == 2 and board["stats"]["overdue"] == 1;
            assert [b["num"] for b in board["plan"]["blocks"]] == [2, 1];
            assert board["week"][0]["tasks"][0]["num"] == 2;
            assert board["week"][1]["minutes"] == 90;
            assert board["courses"][0]["open"] == 2;

            assert call(client, "toggle_task", {"ref": "#1", "today": TODAY})["done"];
            assert call(client, "snooze_task", {"ref": "2", "days": 2, "today": TODAY})["due"] == "2026-10-07";
            board = call(client, "load_board", {"today": TODAY});
            assert board["stats"]["done_today"] == 1 and board["stats"]["overdue"] == 0;

            assert client.login("ben", "planner-secret-1").ok;
            call(client, "join", {"username": "ben"});
            assert call(client, "load_board", {"today": TODAY})["tasks"] == [];
            assert rejected(client, "toggle_task", {"ref": "1"});
            assert call(client, "add_task", {"title": "Ben's own"})["num"] == 1;

            assert client.login("ana", "planner-secret-1").ok;
            assert call(client, "delete_task", {"ref": "2"});
            assert call(client, "remove_course", {"name": "eecs281"});
            assert len(call(client, "load_board", {"today": TODAY})["tasks"]) == 0;
        } finally {
            client.close();
        }
    }
}
