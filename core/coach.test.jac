glob TODAY: str = "2026-10-05";  # a Monday

test "quick-add understands courses, dates, priorities and durations" {
    d = parse_quick("Lab 4 writeup #EECS281 fri !high 1h30m", TODAY);
    assert d.title == "Lab 4 writeup";
    assert d.course == "EECS281";
    assert d.due == "2026-10-09";
    assert d.priority == 3;
    assert d.minutes == 90;
    assert parse_quick("call mom tomorrow 15m", TODAY).due == "2026-10-06";
    assert parse_quick("read ch 3 +3d", TODAY).due == "2026-10-08";
    assert parse_quick("pay rent 11/1", TODAY).due == "2026-11-01";
    assert parse_quick("standup monday", TODAY).due == TODAY;
    plain = parse_quick("just a thought", TODAY);
    assert plain.title == "just a thought" and plain.due == "" and plain.priority == 2;
}

test "due labels read naturally" {
    assert due_label("2026-10-05", TODAY) == "Today";
    assert due_label("2026-10-06", TODAY) == "Tomorrow";
    assert due_label("2026-10-09", TODAY) == "Fri";
    assert due_label("2026-10-02", TODAY) == "3d overdue";
    assert due_label("2026-11-20", TODAY) == "Nov 20";
    assert due_label("", TODAY) == "";
}

test "plan puts overdue and due-today work first and respects capacity" {
    tasks = [
        TaskView(id="a", title="Someday idea", priority=1, minutes=30),
        TaskView(id="b", title="Overdue quiz", due="2026-10-03", minutes=30),
        TaskView(id="c", title="Due today", due=TODAY, priority=3, minutes=60),
        TaskView(id="d", title="Huge thing", due=TODAY, minutes=200),
        TaskView(id="e", title="Finished", done=True, done_on=TODAY, minutes=20)
    ];
    plan = build_plan(tasks, TODAY, capacity=120, day_start="09:00");
    open_blocks = [b for b in plan.blocks if not b.done];
    assert [b.task_id for b in open_blocks] == ["b", "c", "a"];
    assert open_blocks[0].start == "09:00" and open_blocks[0].end == "09:30";
    assert open_blocks[1].reason == "Due today";
    assert open_blocks[2].start == "10:40";  # 10-minute break after 90 minutes
    assert plan.planned_minutes == 120;
    assert [t.id for t in plan.at_risk] == ["d"];
    assert any(b.done and b.task_id == "e" for b in plan.blocks);
    late = build_plan(tasks, TODAY, capacity=120, day_start="09:00", now="13:07");
    assert [b for b in late.blocks if not b.done][0].start == "13:15";
}

test "breakdown falls back to useful templates without an API key" {
    exam = breakdown("Study for EECS 281 midterm", 120);
    assert exam.source == "template";
    assert len(exam.steps) >= 3;
    assert len(template_steps("Mystery chore", 75)) == 5;
    assert human_minutes(95) == "1h 35m" and human_minutes(45) == "45m";
}
