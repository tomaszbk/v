module main

import os

fn test_compiled_visual_dynamic_types_and_inactive_arms_report_vml_locations() {
	root := os.join_path(os.vtmp_dir(), 'vml_visual_types_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	view := os.join_path(root, 'view.vml')
	source := os.join_path(root, 'main.v')
	os.write_file(source, 'import ui2\nstruct Wrong { weight string align string count int flag bool color f64 }
	fn build(mut app Wrong) ui2.Element { return $vml("view.vml") }
	fn main() { mut app := Wrong{}; _ = build(mut app) }')!
	for entry in [
		['Label {\n    weight: app.weight\n}', '2:5'],
		['Label {\n    computed bool valid: app.count\n}', '2:19'],
		['Label {\n    computed string caption: app.count\n}', '2:21'],
		['Label {\n    computed f32 ratio: app.flag\n}', '2:18'],
		['Label {\n    width: app.flag\n}', '2:5'],
		['Label {\n    font_size: app.count > 0\n}', '2:5'],
		['Label {\n    color: app.flag\n}', '2:5'],
		['Grid {\n    columns: app.color\n}', '2:5'],
		['Label {\n    font_size: true ? 18 : app.flag\n}', '2:5'],
		['Label {\n    weight: app.flag\n}', '2:5'],
		['Label {\n    weight: app.color\n}', '2:5'],
		['Label {\n    weight: app.count > 0\n}', '2:5'],
		['Label {\n    color: app.color\n}', '2:5'],
		['Label {\n    align: app.align\n}', '2:5'],
		['Label {\n    text: app.count\n}', '2:5'],
		['Label {\n    text: app.count + app.count\n}', '2:5'],
		['Label {\n    text: app.count > 0\n}', '2:5'],
		['Label {\n    text: !app.flag\n}', '2:5'],
		['Label {\n    text: app.count ? "yes" : "no"\n}', '2:5'],
		['Label {\n    weight: true ? 400 : app.weight\n}', '2:5'],
		['Label {\n    text: true ? "valid" : app.count\n}', '2:5'],
		['Label {\n    bold: false ? app.count : true\n}', '2:5'],
		['Label {\n    Run {\n        weight: true ? 400 : app.weight\n    }\n}', '3:9'],
		['Label {\n    Run {\n        weight: app.weight\n    }\n}', '3:9'],
		['Label {\n    Run {\n        text: app.count\n    }\n}', '3:9'],
	] {
		os.write_file(view, entry[0])!
		result := os.exec([@VEXE, '-new-compiler', '-gc', 'boehm', '-path', '@vlib:@vmodules',
			'-d', 'ui2_custom_rendering', '-check', source])
		assert result.exit_code != 0, result.output
		assert result.output.contains('${view}:${entry[1]}:'), result.output
		assert result.output.contains('called from ${source}'), result.output
	}
}

fn test_compiled_visual_native_profile_rejects_unsupported_presentation() {
	root := os.join_path(os.vtmp_dir(), 'vml_visual_native_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	view := os.join_path(root, 'view.vml')
	source := os.join_path(root, 'main.v')
	os.write_file(source, 'fn main() { _ = $vml("view.vml") }')!
	for declaration in ['weight: 600', 'hover_background: "#000000"', 'letter_spacing: false ? 0 : 2',
		'border_pattern: .dashed', 'font_family: "Example Font"', 'background_color: "#000000"'] {
		os.write_file(view, 'Label {\n    ${declaration}\n}')!
		// macOS selects a real native profile even when this test runs on a
		// platform whose ui2 backend is always custom. This is a parser/typecheck.
		result := os.exec([@VEXE, '-new-compiler', '-gc', 'boehm', '-path', '@vlib:@vmodules',
			'-os', 'macos', '-check', source])
		assert result.exit_code != 0, result.output
		assert result.output.contains('${view}:2:5:'), result.output
		assert result.output.contains('requires the custom renderer'), result.output
	}
}
