import os

fn test_vml_direct_driver_reports_document_errors_at_their_location() {
	root := os.join_path(os.vtmp_dir(), 'vml_driver_${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	v3_dir := os.dir(os.dir(@FILE))
	vlib_dir := os.dir(v3_dir)
	driver := os.join_path(root, 'driver')
	// gc none is limited to constructing the compiler. Application checks use Boehm.
	build := os.exec([@VEXE, '-new-compiler', '-gc', 'none', '-path', '${vlib_dir}:@vmodules',
		'-cc', 'clang', '-no-retry-compilation', '-o', driver, os.join_path(v3_dir, 'v.v')])
	assert build.exit_code == 0, build.output
	source := os.join_path(root, 'main.v')
	view := os.join_path(root, 'view.vml')
	os.write_file(source, 'fn main() { _ = $vml("view.vml") }')!
	// Each entry is the view source, the extra driver flags, the authored
	// view.vml location and the expected diagnostic.
	for entry in [
		['Column {\n    Repeater(model: app.rows) { Label() }\n}', '', '2:5',
			'Repeater requires a stable `key`'],
		['Label(\n    bind.text: "fixed",\n)', '', '2:16', '`bind.text` must target a writable path'],
		['import Missing\nLabel()', '', '1:8', 'could not find VML import `Missing`'],
	] {
		os.write_file(view, entry[0])!
		// This bypasses the launcher and exercises v.driver -> flat VML parsing directly.
		mut args := [driver, '-gc', 'boehm', '-path', '${vlib_dir}:@vmodules', '-cc', 'clang',
			'-no-retry-compilation']
		if entry[1] != '' {
			args << entry[1].split(' ')
		}
		args << ['-check', source]
		result := os.exec(args)
		assert result.exit_code != 0, result.output
		assert result.output.contains('${view}:${entry[2]}:'), result.output
		assert result.output.contains(entry[3]), result.output
		assert result.output.contains('called from ${source}'), result.output
	}
}
