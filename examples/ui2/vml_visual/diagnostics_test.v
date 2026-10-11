// vtest vflags: -d ui2_custom_rendering
module main

import os

fn test_compiled_visual_ios_custom_flag_keeps_native_source_diagnostics() {
	root := os.join_path(os.real_path(os.vtmp_dir()), 'vml_ios_native_${os.getpid()}')
	os.mkdir_all(root)!
	defer {
		if os.getenv('VML_SIBLING_KEEP_FIXTURES') != '1' { os.rmdir_all(root) or {} }
	}
	view := os.join_path(root, 'view.vml')
	source := os.join_path(root, 'main.v')
	os.write_file(view, 'Label(\n    style: [weight(600)],\n)')!
	os.write_file(source, 'import ui2\nfn main() { _ = $vml("view.vml") }')!
	for custom in [false, true] {
		mut arguments := [@VEXE, '-b', 'c', '-gc', 'boehm', '-path', '@vlib:@vmodules', '-cc',
			'clang', '-no-retry-compilation', '-os', 'ios', '-check']
		if custom { arguments << ['-d', 'ui2_custom_rendering'] }
		arguments << source
		// Frontend diagnostics only: no SDK build or UIKit execution is needed.
		result := os.exec(arguments)
		profile := if custom { 'flag' } else { 'native' }
		os.write_file(os.join_path(root, '${profile}-argv.txt'), arguments.join('\n'))!
		os.write_file(os.join_path(root, '${profile}-diagnostics.log'), result.output)!
		os.write_file(os.join_path(root, '${profile}-exit.txt'), result.exit_code.str())!
		assert result.exit_code != 0, result.output
		assert result.output.contains('${view}:2:13:'), result.output
		assert result.output.contains('native weight supports 400 or 700'), result.output
		assert result.output.contains('called from ${source}:2:'), result.output
		assert !result.output.contains('<unknown>'), result.output
	}
}

fn test_compiled_visual_dynamic_types_and_inactive_arms_report_vml_locations() {
	root := os.join_path(os.real_path(os.vtmp_dir()), 'vml_visual_types_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	view := os.join_path(root, 'view.vml')
	source := os.join_path(root, 'main.v')
	os.write_file(source, 'import ui2\nstruct Wrong { weight string align string count int flag bool color f64 }
	fn build(mut app Wrong) ui2.Element { return $vml("view.vml") }
	fn main() { mut app := Wrong{}; _ = build(mut app) }')!
	for entry in [
		['Label(\n    style: [weight(app.weight)],\n)', '2:5'],
		['component Typed(valid bool = app.count) { Label(text: "value") }', '1:17'],
		['component Typed(caption string = app.count) { Label(text: caption) }', '1:17'],
		['component Typed(ratio f32 = app.flag) { Label(text: ratio) }', '1:17'],
		['Label(\n    width: app.flag\n)', '2:5'],
		['Label(\n    style: [font_size(app.count > 0)],\n)', '2:5'],
		['Label(\n    style: [foreground(app.flag)],\n)', '2:5'],
		['Grid(\n    columns: app.color\n)', '2:5'],
		['Label(\n    style: [font_size(true ? 18 : app.flag)],\n)', '2:5'],
		['Label(\n    style: [weight(app.flag)],\n)', '2:5'],
		['Label(\n    style: [weight(app.color)],\n)', '2:5'],
		['Label(\n    style: [weight(app.count > 0)],\n)', '2:5'],
		['Label(\n    style: [foreground(app.color)],\n)', '2:5'],
		['Label(\n    style: [text_align(app.align)],\n)', '2:5'],
		['Label(\n    text: app.flag\n)', '2:5'],
		['Label(\n    text: app.flag && app.flag\n)', '2:5'],
		['Label(\n    text: app.count > 0\n)', '2:5'],
		['Label(\n    text: !app.flag\n)', '2:5'],
		['Label(\n    text: app.count ? "yes" : "no"\n)', '2:5'],
		['Label(\n    style: [weight(true ? 400 : app.weight)],\n)', '2:5'],
		['Label(\n    text: true ? "valid" : app.flag\n)', '2:5'],
		['Label(\n    style: [italic(false ? app.count : true)],\n)', '2:5'],
		['Label() {
    Run(
        style: [weight(true ? 400 : app.weight)],
    )
}', '3:9'],
		['Label() {
    Run(
        style: [weight(app.weight)],
    )
}', '3:9'],
		['Label() {
    Run(
        text: app.flag
    )
}', '3:9'],
	] {
		os.write_file(view, entry[0])!
		result := os.exec([@VEXE, '-b', 'c', '-gc', 'boehm', '-path', '@vlib:@vmodules', '-d',
			'ui2_custom_rendering', '-cc', 'clang', '-o', os.join_path(root, 'probe'), source])
		assert result.exit_code != 0, result.output
		assert result.output.contains('${view}:${entry[1]}:'), result.output
		assert result.output.contains('called from ${source}'), result.output
	}
}

fn test_compiled_visual_native_profile_rejects_unsupported_presentation() {
	root := os.join_path(os.real_path(os.vtmp_dir()), 'vml_visual_native_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	view := os.join_path(root, 'view.vml')
	source := os.join_path(root, 'main.v')
	os.write_file(source, 'fn main() { _ = $vml("view.vml") }')!
	for declaration in ['weight(600)', 'hover([background("#000000")])', 'letter_spacing(false ? 0 : 2)',
		'border_pattern(dashed)', 'font_family("Example Font")', 'text_background("#000000")'] {
		os.write_file(view, 'Label(\n    style: [${declaration}]\n)')!
		// macOS selects a real native profile even when this test runs on a
		// platform whose ui2 backend is always custom. This is a parser/typecheck.
		result := os.exec([@VEXE, '-b', 'c', '-gc', 'boehm', '-path', '@vlib:@vmodules', '-os',
			'macos', '-check', source])
		assert result.exit_code != 0, result.output
		assert result.output.contains('${view}:2:13:'), result.output
		assert result.output.contains('custom renderer'), result.output
	}
}
