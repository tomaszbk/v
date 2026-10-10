module parser

import os

// Generated VML code must compile without notices: guards, payload blocks and
// aliases must not leave constant conditions or unused variables behind.
fn test_vml_generated_code_has_no_constant_conditions_or_unused_aliases() {
	dir := os.join_path(os.vtmp_dir(), 'vml_codegen_hygiene_${os.getpid()}')
	os.mkdir_all(dir)!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'row.vml'), 'component Row(title string, removed event(), changed event(value int)) {
    Column {
        Label(text: title)
        Button(text: "x", on_click: removed())
        Button(text: "y", on_click: { changed(1); changed(2) })
    }
}')!
	document := os.join_path(dir, 'main.vml')
	os.write_file(document, 'import Row
Screen {
    Column {
        Repeater(model: app.tasks, key: item.id) {
            Row(title: item.title, on_removed: app.remove(item.id))
        }
    }
}')!
	root := parse_compiled_vml_file(document, '', [])!
	mut compiler := VmlCompiler{
		uses_app:     true
		guard_prefix: 'vml_check_hygiene'
	}
	generated := compiler.compile(root)
	assert !generated.contains('if false'), generated
	assert !generated.contains('if true'), generated
	assert generated.contains('if vml_check_hygiene_unreachable() { vml_check_hygiene_')
	assert generated.contains('fn vml_check_hygiene_unreachable() bool { return false }')
	assert generated.contains('{\nvml_payload_0 := 1')
	// The list-owned item signal is aliased mutably without a mutability notice.
	assert generated.contains(':= unsafe { vml_item_signal_')
	lines := generated.split_into_lines()
	for i, line in lines {
		trimmed := line.trim_space()
		if trimmed.starts_with('vml_element_') && trimmed.contains(' := vml_element_')
			&& trimmed.ends_with('_root') {
			name := trimmed.all_before(' :=')
			assert i + 1 < lines.len && lines[i + 1].trim_space() == '_ = ${name}', line
		}
	}
}
