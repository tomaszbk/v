import os

fn test_vml_visual_direct_driver_reports_inactive_and_native_declarations() {
	root := os.join_path(os.vtmp_dir(), 'vml_visual_driver_${os.getpid()}')
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
	for entry in [
		['Label {\n    tracking: 2\n}', 'unsupported property `tracking`'],
		['Label {\n    weight: true ? 400 : "heavy"\n}', '`weight` requires a number'],
		['Label {\n    weight: 600\n}', 'requires the custom renderer'],
	] {
		os.write_file(view, entry[0])!
		// This bypasses the launcher and exercises v.driver -> flat VML parsing directly.
		result := os.exec([driver, '-gc', 'boehm', '-path', '${vlib_dir}:@vmodules', '-cc', 'clang',
			'-no-retry-compilation', '-check', source])
		assert result.exit_code != 0, result.output
		assert result.output.contains('${view}:2:5:'), result.output
		assert result.output.contains(entry[1]), result.output
		assert result.output.contains('called from ${source}'), result.output
	}
}
