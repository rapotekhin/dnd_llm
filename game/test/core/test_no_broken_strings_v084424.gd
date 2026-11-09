extends GdUnitTestSuite
## A line break typed inside a string literal (v0.8.4.42.4, the author: empty rows in the journal): a checkout with Windows
## line ends puts «\r\n» into the text, and a wrapped label breaks its rows on it. A string says «\n» instead.

const ROOTS: Array[String] = ["res://core", "res://ui", "res://autoload", "res://tools"]


func _files(dir: String, out: Array[String]) -> void:
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		_files(dir.path_join(d), out)


## The lines where a string literal of this source runs on past its line.
static func broken(src: String) -> Array[int]:
	var out: Array[int] = []
	var quote := ""
	var line := 1
	var i := 0
	while i < src.length():
		var ch := src[i]
		if ch == "\n":
			line += 1
		if not quote.is_empty():
			if ch == "\\":
				i += 2
				continue
			if src.substr(i, quote.length()) == quote:
				i += quote.length()
				quote = ""
				continue
			if ch == "\n" and quote.length() == 1 and not out.has(line - 1):
				out.append(line - 1)
		elif ch == "#":
			var j := src.find("\n", i)
			i = src.length() if j < 0 else j
			continue
		elif ch == "\"" or ch == "'":
			quote = ch.repeat(3) if src.substr(i, 3) == ch.repeat(3) else ch  # a triple-quoted string may span lines
			i += quote.length()
			continue
		i += 1
	return out


func test_the_scanner_finds_a_break_inside_a_string_only() -> void:
	assert_array(broken("var a := \"x\ny\"\n# \"z\nvar b := 'q'\n")).contains_exactly([1])
	assert_array(broken("var a := \"x\\ny\" # it's fine\nvar c := \"\"\"a\nb\"\"\"\n")).is_empty()


func test_no_string_of_the_game_runs_past_its_line() -> void:
	var files: Array[String] = []
	for root: String in ROOTS:
		_files(root, files)
	var bad: Array[String] = []
	for f: String in files:
		for n: int in broken(FileAccess.get_file_as_string(f)):
			bad.append("%s:%d" % [f, n])
	assert_array(bad).override_failure_message("a line break inside a string — write \\n: " + ", ".join(bad)).is_empty()
