extends SceneTree
## The automatic checks of the author's checklist (ChecklistProbe): every row of every sheet run on the engine, the results
## written to game/test/fixtures/checklist_probes.json for the test and tools/checklist.py.
##   godot --headless --path game -s res://tools/checklist_probes.gd [-- <sheet>…]
## With sheet names only those are run again, the rest of the file stays. Prints a status count per sheet.

const OUT := "res://test/fixtures/checklist_probes.json"


func _init() -> void:
	var data := TestUtils.data()
	var only := OS.get_cmdline_user_args()
	var out: Dictionary = {}
	if FileAccess.file_exists(OUT):
		out = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	for sheet: String in ChecklistProbe.SHEETS:
		if not only.is_empty() and not only.has(sheet):
			continue
		var t := Time.get_ticks_msec()
		var rows := ChecklistProbe.sheet_rows(TestUtils.data(), sheet)
		out[sheet] = rows
		var count := {}
		for id: String in rows:
			var st := str(rows[id]["status"])
			count[st] = int(count.get(st, 0)) + 1
		print("%s: %d строк, %s, %d мс" % [sheet, rows.size(), count, Time.get_ticks_msec() - t])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t", false) + "\n")
	f.close()
	quit()
