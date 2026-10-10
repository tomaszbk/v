// vtest vflags: -d ui2_custom_rendering
module main

import os

fn test_checkbox_binding_uses_change_checked_payload_in_both_directions() {
	run_bounded_layout_fixture('checkbox_binding', 'Checkbox(id: "consent", width: 100, height: 24, bind.checked: app.checked)', 'import ui2
@[heap]
struct State {
pub mut:
    checked bool
}
fn build(mut app State) ui2.Element { return $vml("view.vml") }
fn main() {
    mut app := &State{}
    checkbox := build(mut app)
    assert checkbox.kind == .checkbox && checkbox.id == "consent"
    assert !checkbox.checked
    // Synthetic typed events use the payload emitted by UI31 custom and AppKit checkboxes.
    checkbox.on_event(ui2.ElementEvent{ kind: .change, id: checkbox.id, checked: true })
    assert app.checked
    fresh := checkbox.compiled_node.element()
    assert fresh.id == checkbox.id && fresh.checked
    fresh.on_event(ui2.ElementEvent{ kind: .change, id: fresh.id, checked: false })
    assert !app.checked && !checkbox.compiled_node.element().checked
    checkbox.on_event(ui2.ElementEvent{ kind: .tap, id: checkbox.id, checked: true })
    checkbox.on_event(ui2.ElementEvent{ kind: .submit, id: checkbox.id, checked: true })
    assert !app.checked
    println("checkbox change true/false and unrelated events PASS")
}')
}

fn test_checkbox_change_binds_before_action_and_keeps_tap_and_sibling_actions_separate() {
	run_bounded_layout_fixture('checkbox_actions', 'Row(width: 200, height: 30, align_items: start) {
    View(width: 100, height: 24) {
        Checkbox(id: "consent", width: 100, height: 24, bind.checked: app.checked, on_change: app.changed(app.note), on_tap: app.tapped())
    }
    Absolute {
        Button(width: consent.width, height: 24, text: ("Consent ñ"), on_tap: app.accept("Consent ñ"))
    }
}', 'import ui2
@[heap]
struct State {
pub mut:
    checked bool
    note string = "construction"
    observations []bool
    notes []string
    taps int
    accepted string
}
// changed records the bound state and the live action argument.
pub fn (mut app State) changed(note string) {
    app.observations << app.checked
    app.notes << note
}
// tapped records the independent tap action.
pub fn (mut app State) tapped() { app.taps++ }
// accept records the independent sibling action argument.
pub fn (mut app State) accept(caption string) { app.accepted = caption }
fn build(mut app State) ui2.Element { return $vml("view.vml") }
fn main() {
    mut app := &State{}
    tree := build(mut app)
    checkbox := tree.children[0].children[0]
    button := tree.children[1].children[0]
    assert checkbox.frame == ui2.rect(0, 0, 100, 24)
    assert tree.children[1].frame == ui2.rect(100, 0, 100, 24)
    assert button.frame == ui2.rect(0, 0, 100, 24)
    assert button.text == "Consent ñ"
    app.note = "live true"
    checkbox.on_event(ui2.ElementEvent{ kind: .change, id: checkbox.id, checked: true })
    assert app.checked && app.observations == [true] && app.notes == ["live true"]
    assert app.taps == 0 && app.accepted == ""
    app.note = "live false"
    checkbox.on_event(ui2.ElementEvent{ kind: .change, id: checkbox.id, checked: false })
    assert !app.checked && app.observations == [true, false]
    assert app.notes == ["live true", "live false"] && app.taps == 0
    checkbox.on_event(ui2.ElementEvent{ kind: .tap, id: checkbox.id, checked: true })
    assert app.taps == 1 && !app.checked && app.observations.len == 2
    checkbox.on_event(ui2.ElementEvent{ kind: .submit, id: checkbox.id, checked: true })
    button.on_event(ui2.ElementEvent{ kind: .change, id: button.id, checked: true })
    assert app.taps == 1 && !app.checked && app.observations.len == 2 && app.accepted == ""
    button.on_event(ui2.ElementEvent{ kind: .tap, id: button.id })
    assert app.accepted == "Consent ñ" && !app.checked && app.observations.len == 2
    println("checkbox binding-before-action, live argument and descendant reads PASS")
}')
}

fn run_bounded_layout_fixture(name string, view string, program string) {
	root := sibling_fixture_root(name)
	defer {
		if os.getenv('VML_SIBLING_KEEP_FIXTURES') != '1' { os.rmdir_all(root) or {} }
	}
	os.write_file(os.join_path(root, 'view.vml'), view) or { panic(err) }
	os.write_file(os.join_path(root, 'main.v'), program) or { panic(err) }
	build := compile_sibling_fixture(root)
	assert build.exit_code == 0, build.output
	result := os.exec([os.join_path(root, 'app')])
	os.write_file(os.join_path(root, 'runtime.log'), result.output) or { panic(err) }
	os.write_file(os.join_path(root, 'runtime-exit.txt'), result.exit_code.str()) or { panic(err) }
	assert result.exit_code == 0, result.output
	println(result.output)
}

fn test_shared_builders_export_visible_children_to_parent_menu_declarations() {
	run_bounded_layout_fixture('shared_menu_scope', 'Absolute(width: 100, height: 30) {
    Row(width: 100, height: 30, align_items: start) {
        MenuItem(text: ("Menu caption"))
        Label(id: "item", width: 20, height: 20)
        MenuItem(text: "Width \${item.width}")
    }
}', 'import ui2
fn main() {
    tree := $vml("view.vml")
    assert tree.children[0].children[0].frame == ui2.rect(0, 0, 20, 20)
    assert tree.children[0].menu.len == 2
    assert tree.children[0].menu[0].title == "Menu caption"
    assert tree.children[0].menu[1].title == "Width 20.0"
}')
}

fn test_vertical_wrap_omitted_width_and_following_nested_sibling() {
	run_bounded_layout_fixture('vertical_wrap', 'Absolute(width: 500, height: 200) {
    Row(width: 300, height: 80, align_items: start) {
        Column(id: "wrapped", height: 40, wrap: true, gap: 5, align_items: start) {
            Label(width: 30, height: 20, text: "a")
            Label(width: 30, height: 20, text: "b")
            Label(width: 30, height: 20, text: "c")
        }
        Row(width: 80, height: 30) {
            Label(width: 20, height: 20, text: "next")
        }
    }
    Label(x: wrapped.width, width: wrapped.width, height: 20, text: "extent")
}', 'import ui2
fn main() {
    tree := $vml("view.vml")
    row := tree.children[0]
    wrapped := row.children[0]
    assert wrapped.frame == ui2.rect(0, 0, 100, 40)
    assert wrapped.children.map(it.frame) == [ui2.rect(0, 0, 30, 20), ui2.rect(35, 0, 30, 20), ui2.rect(70, 0, 30, 20)]
    assert row.children[1].frame == ui2.rect(100, 0, 80, 30)
    assert row.children[1].children[0].frame == ui2.rect(0, 0, 20, 30)
    assert tree.children[1].frame == ui2.rect(100, 0, 100, 20)
    println("vertical wrap literal geometry PASS")
}')
}

fn test_vertical_wrap_fractional_padding_and_distinct_gaps() {
	run_bounded_layout_fixture('fractional_wrap', 'Absolute(width: 500, height: 200) {
    Row(width: 400, height: 80, padding: 1.25, gap: 2.5, align_items: start) {
        Column(
            height: 48,
            wrap: true,
            gap: 4.25,
            line_gap: 6.75,
            align_items: start,
            padding_left: 2.5,
            padding_right: 3.25,
            padding_top: 1.5,
            padding_bottom: 2.5,
        ) {
            Label(width: 30.5, height: 21.25, text: "a")
            Label(width: 30.5, height: 21.25, text: "b")
            Label(width: 30.5, height: 21.25, text: "c")
        }
        Row(width: 80, height: 30) {
            Label(width: 20, height: 20, text: "next")
        }
    }
}', 'import ui2
fn main() {
    tree := $vml("view.vml")
    row := tree.children[0]
    assert row.children[0].frame == ui2.rect(1.25, 1.25, 110.75, 48)
    assert row.children[0].children.map(it.frame) == [ui2.rect(2.5, 1.5, 30.5, 21.25), ui2.rect(39.75, 1.5, 30.5, 21.25), ui2.rect(77, 1.5, 30.5, 21.25)]
    assert row.children[1].frame == ui2.rect(114.5, 1.25, 80, 30)
    println("fractional vertical wrap literal geometry PASS")
}')
}

fn test_nested_layout_build_work_is_bounded_and_fresh_per_build() {
	for depth in [1, 2, 4, 8, 16] {
		mut view := 'Label(width: app.leaf_width(), height: 20, text: "leaf", on_tap: app.accept(app.value))'
		for _ in 0 .. depth { view = 'Row(align_items: start) { ${view} }' }
		run_bounded_layout_fixture('growth_${depth}', view, 'import ui2
@[heap]
struct State {
pub mut:
    evaluations int
    value int = 30
    received int
}
// leaf_width records real property evaluations during construction.
pub fn (mut app State) leaf_width() f64 { app.evaluations++; return f64(app.value) }
// accept records the live action argument.
pub fn (mut app State) accept(value int) { app.received = value }
fn build(mut app State) ui2.Element { return $vml("view.vml") }
fn leaf(tree ui2.Element) ui2.Element {
    mut element := tree
    for _ in 0 .. ${depth} { assert element.children.len == 1; element = element.children[0] }
    return element
}
fn main() {
    mut app := &State{}
    first := build(mut app)
    println("depth=${depth} evaluations=" + app.evaluations.str())
    assert leaf(first).frame == ui2.rect(0, 0, 30, 20)
    assert app.evaluations <= 8 * (${depth} + 1), app.evaluations.str()
    app.value = 45
    leaf(first).on_event(ui2.ElementEvent{kind: .tap})
    assert app.received == 45
    previous := app.evaluations
    second := build(mut app)
    assert app.evaluations > previous
    assert leaf(second).frame == ui2.rect(0, 0, 45, 20)
    assert app.evaluations - previous <= 8 * (${depth} + 1)
    println("bounded build and fresh properties PASS")
}')
	}
}

fn test_shared_layout_builders_refresh_allocated_sibling_references() {
	run_bounded_layout_fixture('shared_grid_scope', 'Absolute(width: 300, height: 120) {
    Grid(width: 200, height: 100, columns: 2, rows: 1) {
        View(id: "seed", height: 20) {
            Label(width: 20, height: 20, text: "seed")
        }
        Row(align_items: start) {
            Absolute {
                Label(width: seed.width, height: 20, text: "receiving")
            }
        }
    }
    Label(x: seed.x, width: seed.width, height: 20, text: "following")
}', 'import ui2
fn main() {
    tree := $vml("view.vml")
    grid := tree.children[0]
    assert grid.children[0].frame == ui2.rect(0, 0, 100, 100)
    assert grid.children[1].frame == ui2.rect(100, 0, 100, 100)
    assert grid.children[1].children[0].frame == ui2.rect(0, 0, 100, 20)
    assert tree.children[1].frame == ui2.rect(0, 0, 100, 20)
    println("allocated sibling references refresh PASS")
}')
}

fn test_shared_layout_build_work_with_input_dependent_properties() {
	for depth in [2, 4, 8, 12] {
		mut view := 'Label(width: app.record(30), height: 20, text: "leaf")'
		// Supply offered dimensions as data instead of reading a container's own geometry.
		mut divisor := 1.0
		for _ in 1 .. depth { divisor *= 4 }
		for index in 0 .. depth {
			width := if index == depth - 1 { 512.0 } else { 1024.0 / divisor }
			view = 'Row(id: "level_${index}", width: app.offered * ${width} / 1024, height: 20, align_items: start) { ${view} }'
			divisor /= 4
		}
		view = 'Absolute(width: 1024, height: 60) { ${view} }'
		run_bounded_layout_fixture('responsive_growth_${depth}', view, 'import ui2
@[heap]
struct State {
pub mut:
    evaluations int
    offered f64 = 1024
}
// record counts actual property evaluation, without changing its value.
pub fn (mut app State) record(value f64) f64 { app.evaluations++; return value }
fn main() {
    mut app := &State{}
    tree := $vml("view.vml")
    mut element := tree.children[0]
    mut width := 512.0
    assert element.frame == ui2.rect(0, 0, width, 20)
    for index in 1 .. ${depth} {
        width /= if index == 1 { 2.0 } else { 4.0 }
        element = element.children[0]
        assert element.frame == ui2.rect(0, 0, width, 20)
    }
    leaf := element.children[0]
    expected_width := if width < 30 { width } else { 30.0 }
    assert leaf.frame == ui2.rect(0, 0, expected_width, 20)
    println("responsive depth=${depth} evaluations=" + app.evaluations.str())
    assert app.evaluations <= 8 * (${depth} + 1), app.evaluations.str()
    println("responsive bounded construction PASS")
}')
	}
}

fn sibling_fixture_root(name string) string {
	root := os.join_path(os.vtmp_dir(), 'vml_siblings_${name}_${os.getpid()}')
	os.mkdir_all(root) or { panic(err) }
	return os.real_path(root)
}

fn test_shared_builders_keep_slider_and_interaction_enum_types() {
	run_bounded_layout_fixture('shared_enum_types', 'Absolute(width: 300, height: 120) {
    Row(width: 150, height: 30, align_items: start) {
        Slider(width: 30, height: 20, orientation: horizontal)
        Slider(width: 30, height: 20, orientation: vertical)
        Button(
            width: 30,
            height: 20,
            text: "button",
            hover_border_pattern: dashed,
            focus_border_pattern: solid,
            pressed_border_pattern: dashed,
            disabled_border_pattern: solid,
        )
    }
    Grid(width: 150, height: 30, columns: 2, rows: 1) {
        Slider(width: 30, height: 20, orientation: horizontal)
        Slider(width: 30, height: 20, orientation: vertical)
    }
}', 'import ui2
fn main() {
    tree := $vml("view.vml")
    row := tree.children[0]
    assert row.children[0].orientation == .horizontal
    assert row.children[1].orientation == .vertical
    button := row.children[2]
    assert (button.interaction_style.hover.border_pattern or { ui2.BorderPattern.solid }) == .dashed
    assert (button.interaction_style.focus.border_pattern or { ui2.BorderPattern.dashed }) == .solid
    assert (button.interaction_style.pressed.border_pattern or { ui2.BorderPattern.solid }) == .dashed
    assert (button.interaction_style.disabled.border_pattern or { ui2.BorderPattern.dashed }) == .solid
    assert tree.children[1].children[0].orientation == .horizontal
    assert tree.children[1].children[1].orientation == .vertical
    println("shared slider and interaction enums PASS")
}')
}

fn test_vertical_wrap_measured_and_inherited_container_widths() {
	run_bounded_layout_fixture('inherited_vertical_wrap', 'Absolute(width: 500, height: 120) {
    View(width: 0, height: 40) {
        Column(id: "natural", height: 40, wrap: true, gap: 5, align_items: start) {
            Label(width: 30, height: 20, text: "a")
            Label(width: 30, height: 20, text: "b")
            Label(width: 30, height: 20, text: "c")
        }
    }
    View(width: 200, height: 40) {
        Column(id: "inherited", height: 40, wrap: true, gap: 5, align_items: start) {
            Label(width: 30, height: 20, text: "a")
            Label(width: 30, height: 20, text: "b")
            Label(width: 30, height: 20, text: "c")
        }
    }
    Label(x: natural.width, width: inherited.width, height: 20, text: "following")
}', 'import ui2
fn main() {
    tree := $vml("view.vml")
    assert tree.children[0].frame == ui2.rect(0, 0, 0, 40)
    assert tree.children[0].children[0].frame == ui2.rect(0, 0, 100, 40)
    assert tree.children[1].frame == ui2.rect(0, 0, 200, 40)
    assert tree.children[1].children[0].frame == ui2.rect(0, 0, 200, 40)
    assert tree.children[2].frame == ui2.rect(100, 0, 200, 20)
    println("vertical wrap auto and inherited widths PASS")
}')
}

fn compile_sibling_fixture(root string) os.Result {
	args := [@VEXE, '-b', 'c', '-nocache', '-path', '@vlib:@vmodules', '-cc', 'clang',
		'-no-retry-compilation', '-d', 'ui2_custom_rendering', '-o', os.join_path(root, 'app'),
		os.join_path(root, 'main.v')]
	os.write_file(os.join_path(root, 'compile-command.txt'), args.join('\n')) or { panic(err) }
	mut environment := []string{}
	for key in ['VFLAGS', 'VMODULES', 'V_MACOS_V3_NO_FALLBACK', 'VJOBS', 'PATH', 'VTMP', 'TMPDIR'] {
		environment << '${key}=${os.getenv(key)}'
	}
	os.write_file(os.join_path(root, 'compile-env.txt'), environment.join('\n')) or { panic(err) }
	result := os.exec(args)
	os.write_file(os.join_path(root, 'compile.log'), result.output) or { panic(err) }
	os.write_file(os.join_path(root, 'compile-exit.txt'), result.exit_code.str()) or { panic(err) }
	return result
}

fn run_sibling_geometry(tag string, config string, expected string, inner_x int, inner_y int) {
	inner_height := if tag == 'Grid' { 33 } else { 20 }
	root := sibling_fixture_root(tag)
	defer {
		if os.getenv('VML_SIBLING_KEEP_FIXTURES') != '1' { os.rmdir_all(root) or {} }
	}
	os.write_file(os.join_path(root, 'view.vml'), 'component Siblings() {
    computed unit := app.geometry.width
    computed caption := app.name
    computed strong := app.strong
    computed ink := app.ink
    computed half := unit / 2
    Absolute(width: 400, height: 400) {
        ${tag}(id: "layout", x: 10, y: 15, width: 200, height: 80, ${config}) {
            Label(id: "first", width: unit, height: 20, text: caption, bold: strong, color: ink, on_tap: app.accept(app.argument))
            Absolute(id: "middle") {
                Column(width: first.width, align_items: start) {
                    Absolute {
                        Label(id: "inner", width: half, height: first.height, font_size: 18) {
                            Run(text: caption, bold: strong, color: ink)
                        }
                    }
                }
            }
            Absolute {
                TextInput(id: "input", width: half, height: inner.height, bind.text: app.name, on_submit: app.submit(app.name))
            }
        }
        Label(x: middle.x, y: inner.y, width: half, height: inner.height, text: caption)
    }
}') or { panic(err) }
	os.write_file(os.join_path(root, 'main.v'), 'module main
import ui2
@[heap]
struct State {
pub mut:
    geometry &ui2.LayoutSize = &ui2.LayoutSize{width: 40}
    name string = "niñez"
    strong bool = true
    ink u32 = 0x123456
    argument int = 40
    received int
    submitted string
}
// accept records the callback argument.
pub fn (mut app State) accept(value int) { app.received = value }
// submit records the current bound text.
pub fn (mut app State) submit(value string) { app.submitted = value }
fn build(mut app State) ui2.Element { return $vml("view.vml") }
fn main() {
    mut app := &State{}
    tree := build(mut app)
    layout := tree.children[0]
    assert layout.children.map(it.frame) == ${expected}
    inner := layout.children[1].children[0].children[0].children[0]
    assert inner.frame == ui2.rect(${inner_x}, ${inner_y}, 20, ${inner_height})
    assert inner.text_runs[0].text == "niñez"
    assert inner.text_runs[0].style.bold
    assert inner.text_runs[0].style.size == 18
    assert inner.text_runs[0].style.color == 0x123456
    assert tree.children[1].frame == ui2.rect(layout.children[1].frame.x, ${inner_y}, 20, ${inner_height})
    assert tree.children[1].text == "niñez"
    first := layout.children[0]
    assert app.received == 0 && app.submitted == ""
    app.geometry = &ui2.LayoutSize{width: 55}
    app.argument = 55
    first.on_event(ui2.ElementEvent{kind: .tap, id: first.id})
    assert app.received == 55
    input := layout.children[2].children[0]
    assert input.id.len > 0 && input.id != "input"
    input.on_event(ui2.ElementEvent{kind: .change, id: input.id, text: "canción"})
    assert app.name == "canción"
    input.on_event(ui2.ElementEvent{kind: .submit, id: input.id, text: app.name})
    assert app.submitted == "canción"
    fresh := tree.compiled_node.element()
    assert fresh.children[0].children[0].text == "canción"
    assert fresh.children[0].children[2].children[0].id == input.id
    assert fresh.children[0].children[2].children[0].key == input.key
    assert fresh.children[0].children[2].children[0].compiled_node == input.compiled_node
    assert fresh.children[1].frame.width == 27.5
    println("${tag} sibling geometry and live callbacks PASS")
}') or { panic(err) }
	build := compile_sibling_fixture(root)
	assert build.exit_code == 0, build.output
	result := os.exec([os.join_path(root, 'app')])
	os.write_file(os.join_path(root, 'runtime.log'), result.output) or { panic(err) }
	os.write_file(os.join_path(root, 'runtime-exit.txt'), result.exit_code.str()) or { panic(err) }
	assert result.exit_code == 0, result.output
	assert result.output.contains('PASS'), result.output
}

fn test_row_sibling_scopes_with_skipped_height_and_nested_computed_properties() {
	run_sibling_geometry('Row', 'padding: 4, gap: 6, align_items: start',
		'[ui2.rect(4, 4, 40, 20), ui2.rect(50, 4, 40, 20), ui2.rect(96, 4, 20, 20)]', 0, 0)
}

fn test_column_sibling_scopes_with_typed_model_reference_and_bindings() {
	run_sibling_geometry('Column', 'padding: 4, gap: 6, align_items: start',
		'[ui2.rect(4, 4, 40, 20), ui2.rect(4, 30, 40, 20), ui2.rect(4, 56, 20, 20)]', 0, 0)
}

fn test_flex_sibling_scopes_with_independent_offsets() {
	run_sibling_geometry('Flex', 'orientation: horizontal, padding: 4, gap: 6, align_items: start',
		'[ui2.rect(4, 4, 40, 20), ui2.rect(50, 4, 40, 20), ui2.rect(96, 4, 20, 20)]', 0, 0)
}

fn test_grid_sibling_scopes_and_final_allocated_coordinates() {
	run_sibling_geometry('Grid', 'columns: 2, rows: 2, padding: 4, spacing: 6',
		'[ui2.rect(4, 4, 93, 33), ui2.rect(103, 4, 93, 33), ui2.rect(4, 43, 93, 33)]', 0, 0)
}

fn test_width_measurement_skips_only_the_current_child_scope() {
	root := sibling_fixture_root('width')
	defer {
		if os.getenv('VML_SIBLING_KEEP_FIXTURES') != '1' { os.rmdir_all(root) or {} }
	}
	os.write_file(os.join_path(root, 'view.vml'), 'Absolute(width: 300, height: 200) {
    Column(width: 300, height: 200, align_items: start) {
        Row(id: "row", width: 300, gap: 5, align_items: start) {
            Label(id: "fixed", width: 40, height: 20, text: "Fixed")
            Absolute(id: "measured") {
                Column(width: fixed.width, align_items: start) {
                    Label(id: "descendant", width: 40, height: 20, text: "Nested")
                }
            }
            Absolute {
                Label(width: descendant.width, height: 20, text: "Skipped")
            }
            Absolute {
                Column(width: fixed.width, align_items: start) {
                    Absolute {
                        Label(width: 40, height: (measured.width), text: "Last")
                    }
                }
            }
        }
    }
    Label(x: measured.x, width: descendant.width, height: row.height, text: "Final")
}') or { panic(err) }
	os.write_file(os.join_path(root, 'main.v'), 'import ui2
fn main() {
    root := $vml("view.vml")
    row := root.children[0].children[0]
    assert row.frame == ui2.rect(0, 0, 300, 40)
    assert row.children.map(it.frame) == [ui2.rect(0, 0, 40, 20), ui2.rect(45, 0, 40, 20), ui2.rect(90, 0, 40, 20), ui2.rect(135, 0, 40, 40)]
    assert root.children[1].frame == ui2.rect(45, 0, 40, 40)
}') or { panic(err) }
	build := compile_sibling_fixture(root)
	assert build.exit_code == 0, build.output
	result := os.exec([os.join_path(root, 'app')])
	os.write_file(os.join_path(root, 'runtime.log'), result.output) or { panic(err) }
	os.write_file(os.join_path(root, 'runtime-exit.txt'), result.exit_code.str()) or { panic(err) }
	assert result.exit_code == 0, result.output
}

fn test_invalid_sibling_references_keep_vml_positions_and_call_sites() {
	root := sibling_fixture_root('invalid')
	defer {
		if os.getenv('VML_SIBLING_KEEP_FIXTURES') != '1' { os.rmdir_all(root) or {} }
	}
	view := os.join_path(root, 'view.vml')
	source := os.join_path(root, 'main.v')
	os.write_file(source, 'import ui2\nfn main() { _ = $vml("view.vml") }') or { panic(err) }
	for index, entry in [
		[
			'Absolute() {
    Label(id: "first", width: later.width, height: 20)
    Label(id: "later", width: 40, height: 20)
}',
			'2:24',
			'undefined variable: `later`',
		],
		[
			'Absolute() {
    Label(id: "first", width: 40, height: 20)
    Label(width: ("bad"), height: 20)
}',
			'3:11',
			'`width` requires a number',
		],
		[
			'Absolute() {
    Label(id: "first", width: 40, height: 20)
    Label(width: missing.width)
}',
			'3:11',
			'undefined variable: `missing`',
		],
		[
			'Absolute() {
    Label(id: "first", width: 40, height: 20)
    Label(width: first.absent)
}',
			'3:11',
			'undefined ident: `first`',
		],
		[
			'Absolute() {
    Label(id: "first", width: 40, height: 20)
    Label(width: (true))
}',
			'3:11',
			'`width` requires a number',
		],
		[
			'Absolute() {
    View() {
        Label(id: "inner", text: "WWW")
    }
    Label(width: ("bad"), height: 20)
}',
			'5:11',
			'`width` requires a number',
		],
	] {
		os.write_file(view, entry[0]) or { panic(err) }
		result := compile_sibling_fixture(root)
		for name in ['view.vml', 'compile.log', 'compile-exit.txt'] {
			os.cp(os.join_path(root, name), os.join_path(root, '${index}_${name}')) or { panic(err) }
		}
		assert result.exit_code != 0, result.output
		assert result.output.contains('${view}:${entry[1]}: error: ${entry[2]}'), result.output
		assert result.output.contains('called from ${source}'), result.output
	}
}

fn run_intrinsic_sibling_fixture(name string, view string, program string) {
	root := sibling_fixture_root(name)
	defer {
		if os.getenv('VML_SIBLING_KEEP_FIXTURES') != '1' { os.rmdir_all(root) or {} }
	}
	os.write_file(os.join_path(root, 'view.vml'), view) or { panic(err) }
	os.write_file(os.join_path(root, 'main.v'), program) or { panic(err) }
	build := compile_sibling_fixture(root)
	assert build.exit_code == 0, build.output
	result := os.exec([os.join_path(root, 'app')])
	os.write_file(os.join_path(root, 'runtime.log'), result.output) or { panic(err) }
	os.write_file(os.join_path(root, 'runtime-exit.txt'), result.exit_code.str()) or { panic(err) }
	assert result.exit_code == 0, result.output
}

fn test_intrinsic_width_survives_explicit_height_skipped_sibling() {
	run_intrinsic_sibling_fixture('intrinsic_skipped', 'Column(width: 300, height: 100, gap: 7, align_items: start) {
    Label(id: "first", text: "WWW", height: 20)
    Absolute {
        Label(text: "Copy", width: first.width, height: 20)
    }
}', 'import ui2
fn main() {
    size := ui2.measure_layout_text("WWW", ui2.TextStyle{}, -1) or { panic(err) }
    assert size.width > 0
    tree := $vml("view.vml")
    assert tree.children.map(it.frame) == [ui2.rect(0, 0, size.width, 20), ui2.rect(0, 27, size.width, 20)]
}')
}

fn test_intrinsic_leaf_and_unsized_nested_layout_expose_measured_geometry() {
	run_intrinsic_sibling_fixture('intrinsic_nested', 'Absolute(width: 300, height: 300) {
    Column(id: "block", gap: 7, align_items: start) {
        Label(id: "first", text: "WWW")
        Absolute {
            Label(text: "Copy", width: first.width, height: first.height)
        }
    }
    Label(x: block.width, y: block.height, width: block.width, height: block.height, text: "Final")
}', 'import ui2
fn main() {
    size := ui2.measure_layout_text("WWW", ui2.TextStyle{}, -1) or { panic(err) }
    assert size.width > 0 && size.height > 0
    tree := $vml("view.vml")
    block := tree.children[0]
    height := size.height * 2 + 7
    assert block.frame == ui2.rect(0, 0, size.width, height)
    assert block.children.map(it.frame) == [ui2.rect(0, 0, size.width, size.height), ui2.rect(0, size.height + 7, size.width, size.height)]
    assert tree.children[1].frame == ui2.rect(size.width, height, size.width, height)
}')
}

fn test_width_pass_sibling_height_uses_wrapped_leaf_measurement() {
	run_intrinsic_sibling_fixture('intrinsic_width_pass', 'Row(width: 80, height: 200, align_items: start) {
    Label(id: "first", text: "WW WW WW WW", lines: 10, flex_basis: 40, flex_shrink: 0)
    Absolute(flex_basis: 40, flex_shrink: 0) {
        Label(id: "second", width: first.width, line_height: (first.height), text: "Copy")
    }
}', 'import ui2
fn main() {
    style := ui2.TextStyle{lines: 10}
    natural := ui2.measure_layout_text("WW WW WW WW", style, -1) or { panic(err) }
    wrapped := ui2.measure_layout_text("WW WW WW WW", style, 40) or { panic(err) }
    assert natural.width > 40 && wrapped.height > natural.height
    tree := $vml("view.vml")
    assert tree.children.map(it.frame) == [ui2.rect(0, 0, 40, wrapped.height), ui2.rect(40, 0, 40, wrapped.height)]
    assert tree.children[1].children[0].text_style.line_height == wrapped.height
}')
}

fn test_intrinsic_sibling_sizes_determine_wrapped_flex_autoheight() {
	run_intrinsic_sibling_fixture('intrinsic_wrap', 'Absolute(width: 300, height: 300) {
    Flex(id: "flow", width: app.width, wrap: true, gap: 5, line_gap: 9, align_items: start) {
        Label(id: "first", text: "WWW")
        Absolute {
            Label(text: "Copy", width: first.width, height: first.height)
        }
        Absolute {
            Label(text: "Last", width: first.width, height: first.height)
        }
    }
    Label(x: flow.width, y: flow.height, width: first.width, height: first.height, text: "Final")
}', 'import ui2
@[heap]
struct State {
pub mut:
    width f64
}
fn build(mut app State) ui2.Element { return $vml("view.vml") }
fn main() {
    size := ui2.measure_layout_text("WWW", ui2.TextStyle{}, -1) or { panic(err) }
    assert size.width > 0 && size.height > 0
    width := size.width * 2 + 5
    height := size.height * 2 + 9
    mut app := &State{width: width}
    tree := build(mut app)
    flow := tree.children[0]
    assert flow.frame == ui2.rect(0, 0, width, height)
    assert flow.children.map(it.frame) == [ui2.rect(0, 0, size.width, size.height), ui2.rect(size.width + 5, 0, size.width, size.height), ui2.rect(0, size.height + 9, size.width, size.height)]
    assert tree.children[1].frame == ui2.rect(width, height, size.width, size.height)
}')
}

fn test_nested_grid_width_measurement_keeps_explicit_height_descendant_ids() {
	root := sibling_fixture_root('grid_width')
	defer {
		if os.getenv('VML_SIBLING_KEEP_FIXTURES') != '1' { os.rmdir_all(root) or {} }
	}
	os.write_file(os.join_path(root, 'view.vml'), 'Absolute(width: 300, height: 200) {
    Column(width: 200, height: 120, align_items: start) {
        Grid(id: "grid", width: 200, columns: 2) {
            View(id: "cell", width: 50, height: 20) {
                Label(id: "seed", width: 50, height: 20, text: "Seed")
            }
            Absolute(id: "sized") {
                Column(width: seed.width, align_items: start) {
                    Absolute {
                        Label(width: seed.width, height: cell.width, text: "Sized")
                    }
                }
            }
        }
    }
    Label(x: sized.x, width: seed.width, height: grid.height, text: "Final")
}') or { panic(err) }
	os.write_file(os.join_path(root, 'main.v'), 'import ui2
fn main() {
    root := $vml("view.vml")
    grid := root.children[0].children[0]
    assert grid.frame == ui2.rect(0, 0, 200, 100)
    assert grid.children.map(it.frame) == [ui2.rect(0, 0, 100, 100), ui2.rect(100, 0, 100, 100)]
    assert grid.children[0].children[0].frame == ui2.rect(0, 0, 50, 20)
    assert grid.children[1].children[0].frame == ui2.rect(0, 0, 50, 100)
    assert root.children[1].frame == ui2.rect(100, 0, 50, 100)
}') or { panic(err) }
	build := compile_sibling_fixture(root)
	assert build.exit_code == 0, build.output
	result := os.exec([os.join_path(root, 'app')])
	os.write_file(os.join_path(root, 'runtime.log'), result.output) or { panic(err) }
	os.write_file(os.join_path(root, 'runtime-exit.txt'), result.exit_code.str()) or { panic(err) }
	assert result.exit_code == 0, result.output
}

fn test_auto_view_descendant_height_is_visible_to_following_sibling() {
	run_intrinsic_sibling_fixture('descendant_auto', 'Row(width: 300, height: 80, align_items: start) {
    View {
        Label(id: "inner", text: "WWW")
    }
    Absolute {
        Label(width: 40, height: inner.height, text: "Copy")
    }
}', 'import ui2
fn main() {
    size := ui2.measure_layout_text("WWW", ui2.TextStyle{}, -1) or { panic(err) }
    assert size.height > 0
    tree := $vml("view.vml")
    assert tree.children[0].frame == ui2.rect(0, 0, size.width, size.height)
    assert tree.children[0].children[0].frame == ui2.rect(0, 0, size.width, size.height)
    assert tree.children[1].frame == ui2.rect(size.width, 0, 40, size.height)
}')
}

fn test_nested_view_autoheight_keeps_offered_width_for_wrapping() {
	run_intrinsic_sibling_fixture('descendant_fixed_width', 'Row(width: 300, height: 200, align_items: start) {
    View(width: 120) {
        View {
            Label(id: "inner", text: "WW WW WW WW WW WW", lines: 10)
        }
    }
    Absolute {
        Label(width: 40, height: inner.height, text: "Copy")
    }
}', 'import ui2
fn main() {
    text := "WW WW WW WW WW WW"
    style := ui2.TextStyle{lines: 10}
    natural := ui2.measure_layout_text(text, style, -1) or { panic(err) }
    size := ui2.measure_layout_text(text, style, 120) or { panic(err) }
    assert size.height > natural.height
    tree := $vml("view.vml")
    assert tree.children.map(it.frame) == [ui2.rect(0, 0, 120, size.height), ui2.rect(120, 0, 40, size.height)]
    assert tree.children[0].children[0].frame == ui2.rect(0, 0, 120, size.height)
    assert tree.children[0].children[0].children[0].frame == ui2.rect(0, 0, 120, size.height)
}')
}

fn test_nested_view_autowidth_keeps_inherited_fixed_height() {
	run_intrinsic_sibling_fixture('descendant_fixed_height', 'Column(width: 300, height: 100, align_items: start) {
    View(height: 30) {
        View {
            Label(id: "inner", text: "WWW")
        }
    }
    Absolute {
        Label(width: inner.width, height: 20, text: "Copy")
    }
}', 'import ui2
fn main() {
    size := ui2.measure_layout_text("WWW", ui2.TextStyle{}, -1) or { panic(err) }
    assert size.width > 0
    tree := $vml("view.vml")
    assert tree.children.map(it.frame) == [ui2.rect(0, 0, size.width, 30), ui2.rect(0, 30, size.width, 20)]
    assert tree.children[0].children[0].children[0].frame == ui2.rect(0, 0, size.width, 30)
}')
}

fn test_view_measures_nested_layout_ids_with_inherited_width() {
	run_intrinsic_sibling_fixture('descendant_layouts', 'Row(width: 300, height: 100, align_items: start) {
    View(width: 100) {
        Row(id: "nested", padding: 5, gap: 7, align_items: start) {
            Label(width: 20, height: 10, text: "A")
            Label(width: 30, height: 15, text: "B")
        }
    }
    Absolute {
        Label(width: 40, height: nested.height, text: "Copy")
    }
}', 'import ui2
fn main() {
    tree := $vml("view.vml")
    assert tree.children.map(it.frame) == [ui2.rect(0, 0, 100, 25), ui2.rect(100, 0, 40, 25)]
    nested := tree.children[0].children[0]
    assert nested.frame == ui2.rect(0, 0, 100, 25)
    assert nested.children.map(it.frame) == [ui2.rect(5, 5, 20, 10), ui2.rect(32, 5, 30, 15)]
}')
	run_intrinsic_sibling_fixture('descendant_grid', 'Row(width: 300, height: 100, align_items: start) {
    View(width: 100) {
        Grid(id: "nested", columns: 2) {
            Label(width: 20, height: 10, text: "A")
            Label(width: 30, height: 15, text: "B")
        }
    }
    Absolute {
        Label(width: 40, height: nested.height, text: "Copy")
    }
}', 'import ui2
fn main() {
    tree := $vml("view.vml")
    assert tree.children.map(it.frame) == [ui2.rect(0, 0, 100, 15), ui2.rect(100, 0, 40, 15)]
    nested := tree.children[0].children[0]
    assert nested.frame == ui2.rect(0, 0, 100, 15)
    assert nested.children.map(it.frame) == [ui2.rect(0, 0, 50, 15), ui2.rect(50, 0, 50, 15)]
}')
}

fn test_generic_normal_containers_keep_fixed_axes_and_absolute_auto_axes() {
	run_intrinsic_sibling_fixture('descendant_normal', 'View(width: 400, height: 400) {
    View(width: 120, height: 30) {
        View() {
            Label(text: "WWW")
        }
    }
    Scroll(width: 120, height: 30) {
        View() {
            Label(text: "WWW")
        }
    }
    Screen(width: 120, height: 30) {
        View() {
            Label(text: "WWW")
        }
    }
    ScaledContent(width: 120, height: 30, content_width: 70, content_height: 25) {
        View() {
            Label(text: "WWW")
        }
    }
    Absolute(width: 120, height: 30) {
        View() {
            Label(text: "WWW")
        }
    }
    View(width: 0, height: 0) {
        Label(width: 0, height: 0, hidden: false, text: "Zero")
    }
}', 'import ui2
fn main() {
    size := ui2.measure_layout_text("WWW", ui2.TextStyle{}, -1) or { panic(err) }
    tree := $vml("view.vml")
    for i in [0, 2] {
        assert tree.children[i].children[0].frame == ui2.rect(0, 0, 120, 30)
        assert tree.children[i].children[0].children[0].frame == ui2.rect(0, 0, 120, 30)
    }
    // Nested Screens keep authored dimensions; mounted roots use the viewport.
    assert tree.children[2].frame == ui2.rect(0, 0, 120, 30)
    // Scroll content fills width and retains its independently measured height.
    assert tree.children[1].children[0].frame == ui2.rect(0, 0, 120, size.height)
    assert tree.children[1].children[0].children[0].frame == ui2.rect(0, 0, 120, size.height)
    assert tree.children[3].frame == ui2.rect(0, 0, 120, 30)
    assert tree.children[3].children[0].children[0].frame == ui2.rect(0, 0, 70, 25)
    assert tree.children[4].frame == ui2.rect(0, 0, 120, 30)
    assert tree.children[4].children[0].children[0].frame == ui2.rect(0, 0, size.width, size.height)
    assert tree.children[5].children[0].frame == ui2.Rect{}
    assert !tree.children[5].children[0].hidden
}')
}

fn test_measured_view_keeps_explicit_zero_and_live_bindings_callbacks() {
	run_intrinsic_sibling_fixture('descendant_live', 'Row(width: 300, height: 80, align_items: start) {
    View(width: 80, height: 30) {
        Label(id: "inner", width: 0, height: 0, hidden: false, on_tap: app.accept(app.argument))
        TextInput(width: 40, height: 20, bind.text: app.name, on_submit: app.submit(app.name))
    }
    Absolute {
        Label(width: inner.width, height: inner.height, text: "Copy")
    }
}', 'import ui2
@[heap]
struct State {
pub mut:
    argument int = 40
    received int
    name string = "niñez"
    submitted string
}
// accept records the live action argument.
pub fn (mut app State) accept(value int) { app.received = value }
// submit records the bound value when the event fires.
pub fn (mut app State) submit(value string) { app.submitted = value }
fn build(mut app State) ui2.Element { return $vml("view.vml") }
fn main() {
    mut app := &State{}
    tree := build(mut app)
    assert tree.children.map(it.frame) == [ui2.rect(0, 0, 80, 30), ui2.rect(80, 0, 0, 0)]
    inner := tree.children[0].children[0]
    assert inner.frame == ui2.Rect{} && !inner.hidden
    assert app.received == 0 && app.submitted == ""
    app.argument = 55
    inner.on_event(ui2.ElementEvent{kind: .tap, id: inner.id})
    assert app.received == 55
    input := tree.children[0].children[1]
    input.on_event(ui2.ElementEvent{kind: .change, id: input.id, text: "canción"})
    assert app.name == "canción"
    input.on_event(ui2.ElementEvent{kind: .submit, id: input.id, text: app.name})
    assert app.submitted == "canción"
    fresh := tree.compiled_node.element()
    assert fresh.children[0].children[1].text == "canción"
    assert fresh.children[0].children[1].id == input.id
    assert fresh.children[0].children[1].key == input.key
}')
}

fn test_selected_auto_grid_width_remeasures_five_rows_and_exports_final_geometry() {
	run_bounded_layout_fixture('selected_auto_grid_five', 'Absolute(width: 300, height: 300) {
    Grid(id: "cells", auto_columns_min_width: 100) {
        Label(id: "first", width: 20, height: 20)
        Label(width: 20, height: 20)
        Label(width: 20, height: 20)
        Label(width: 20, height: 20)
        Label(id: "last", width: 20, height: 20)
    }
    Label(x: cells.width, y: cells.height, width: last.width, height: last.height, text: ("five rows ñ"))
}', 'import ui2
fn main() {
    sizes := [ui2.rect(0, 0, 20, 20), ui2.rect(0, 0, 20, 20), ui2.rect(0, 0, 20, 20), ui2.rect(0, 0, 20, 20), ui2.rect(0, 0, 20, 20)]
    config := ui2.GridConfig{frame: ui2.rect(0, 0, 300, 300), auto_columns_min_width: 100}
    // Public API controls have literal expectations independent of the lowering.
    assert ui2.grid_preferred_size(config, sizes)! == ui2.rect(0, 0, 60, 40)
    assert ui2.grid_preferred_size(ui2.GridConfig{...config, frame: ui2.rect(0, 0, 60, 300)}, sizes)! == ui2.rect(0, 0, 20, 100)
    one_column := [ui2.rect(0, 0, 60, 20), ui2.rect(0, 20, 60, 20), ui2.rect(0, 40, 60, 20), ui2.rect(0, 60, 60, 20), ui2.rect(0, 80, 60, 20)]
    assert ui2.grid_frames(ui2.GridConfig{...config, frame: ui2.rect(0, 0, 60, 100)}, 5)! == one_column
    assert ui2.grid_preferred_size(ui2.GridConfig{...config, frame: ui2.rect(0, 0, 60, 300), auto_columns_min_width: 20}, sizes)! == ui2.rect(0, 0, 60, 40)
    assert ui2.grid_frames(ui2.GridConfig{...config, frame: ui2.rect(0, 0, 60, 40), auto_columns_min_width: 20}, 5)! == [ui2.rect(0, 0, 20, 20), ui2.rect(20, 0, 20, 20), ui2.rect(40, 0, 20, 20), ui2.rect(0, 20, 20, 20), ui2.rect(20, 20, 20, 20)]
    tree := $vml("view.vml")
    assert tree.children[0].frame == ui2.rect(0, 0, 60, 100)
    assert tree.children[0].children.map(it.frame) == one_column
    // Geometry references expose the final assigned child frames.
    assert tree.children[1].frame == ui2.rect(60, 100, 60, 20)
    assert tree.children[1].text == "five rows ñ"
    println("selected width 60, one column, five rows of 20, height 100 PASS")
}')
}

fn test_selected_auto_grid_width_thresholds_keep_natural_width_and_child_heights() {
	run_bounded_layout_fixture('selected_auto_grid_thresholds', 'Absolute(width: 300, height: 300) {
    Grid(auto_columns_min_width: app.minimum) {
        Label(width: app.child_width, height: 20)
        Label(width: app.child_width, height: 20)
        Label(width: app.child_width, height: 20)
        Label(width: app.child_width, height: 20)
        Label(width: app.child_width, height: 20)
    }
}', 'import ui2
@[heap]
struct State {
pub mut:
    minimum f64 = 30
    child_width f64 = 11.9375
}
fn build(mut app State) ui2.Element { return $vml("view.vml") }
fn main() {
    mut app := &State{}
    below := build(mut app).children[0]
    assert below.frame == ui2.rect(0, 0, 59.6875, 100)
    assert below.children.map(it.frame) == [ui2.rect(0, 0, 59.6875, 20), ui2.rect(0, 20, 59.6875, 20), ui2.rect(0, 40, 59.6875, 20), ui2.rect(0, 60, 59.6875, 20), ui2.rect(0, 80, 59.6875, 20)]
    app.child_width = 12
    boundary := build(mut app).children[0]
    assert boundary.frame == ui2.rect(0, 0, 60, 60)
    assert boundary.children.map(it.frame) == [ui2.rect(0, 0, 30, 20), ui2.rect(30, 0, 30, 20), ui2.rect(0, 20, 30, 20), ui2.rect(30, 20, 30, 20), ui2.rect(0, 40, 30, 20)]
    app.child_width = 12.0625
    above := build(mut app).children[0]
    assert above.frame == ui2.rect(0, 0, 60.3125, 60)
    assert above.children.map(it.frame) == [ui2.rect(0, 0, 30.15625, 20), ui2.rect(30.15625, 0, 30.15625, 20), ui2.rect(0, 20, 30.15625, 20), ui2.rect(30.15625, 20, 30.15625, 20), ui2.rect(0, 40, 30.15625, 20)]
    app.minimum = 12.0625
    five_columns := build(mut app).children[0]
    assert five_columns.frame == ui2.rect(0, 0, 60.3125, 20)
    assert five_columns.children.map(it.frame) == [ui2.rect(0, 0, 12.0625, 20), ui2.rect(12.0625, 0, 12.0625, 20), ui2.rect(24.125, 0, 12.0625, 20), ui2.rect(36.1875, 0, 12.0625, 20), ui2.rect(48.25, 0, 12.0625, 20)]
    sizes := [ui2.rect(0, 0, 12, 20), ui2.rect(0, 0, 12, 20), ui2.rect(0, 0, 12, 20), ui2.rect(0, 0, 12, 20), ui2.rect(0, 0, 12, 20)]
    assert ui2.grid_preferred_size(ui2.GridConfig{frame: ui2.rect(0, 0, 59.6875, 300), auto_columns_min_width: 30}, sizes)! == ui2.rect(0, 0, 12, 100)
    assert ui2.grid_preferred_size(ui2.GridConfig{frame: ui2.rect(0, 0, 60, 300), auto_columns_min_width: 30}, sizes)! == ui2.rect(0, 0, 24, 60)
    assert ui2.grid_preferred_size(ui2.GridConfig{frame: ui2.rect(0, 0, 60.3125, 300), auto_columns_min_width: 30}, sizes)! == ui2.rect(0, 0, 24, 60)
    println("selected widths below, at and above 60; live minimum control PASS")
}')
}

fn test_selected_auto_grid_fractional_padding_spacing_and_column_cap() {
	run_bounded_layout_fixture('selected_auto_grid_fractional', 'Absolute(width: 300, height: 300) {
    Grid(
        auto_columns_min_width: app.minimum,
        max_columns: app.cap,
        padding_left: 2.5,
        padding_right: 3.25,
        padding_top: 1.5,
        padding_bottom: 2.5,
        spacing_x: 2.5,
        spacing_y: 1.25,
    ) {
        Label(width: 20.5, height: 10.25)
        Label(width: 20.5, height: 10.25)
        Label(width: 20.5, height: 10.25)
        Label(width: 20.5, height: 10.25)
        Label(width: 20.5, height: 10.25)
    }
}', 'import ui2
@[heap]
struct State {
pub mut:
    minimum f64 = 100
    cap int
}
fn build(mut app State) ui2.Element { return $vml("view.vml") }
fn main() {
    sizes := [ui2.rect(0, 0, 20.5, 10.25), ui2.rect(0, 0, 20.5, 10.25), ui2.rect(0, 0, 20.5, 10.25), ui2.rect(0, 0, 20.5, 10.25), ui2.rect(0, 0, 20.5, 10.25)]
    config := ui2.GridConfig{frame: ui2.rect(0, 0, 300, 300), auto_columns_min_width: 100, padding: ui2.GridPadding{left: 2.5, right: 3.25, top: 1.5, bottom: 2.5}, spacing: ui2.GridSpacing{horizontal: 2.5, vertical: 1.25}}
    assert ui2.grid_preferred_size(config, sizes)! == ui2.rect(0, 0, 49.25, 37.25)
    assert ui2.grid_preferred_size(ui2.GridConfig{...config, frame: ui2.rect(0, 0, 49.25, 300)}, sizes)! == ui2.rect(0, 0, 26.25, 60.25)
    one_column := [ui2.rect(2.5, 1.5, 43.5, 10.25), ui2.rect(2.5, 13, 43.5, 10.25), ui2.rect(2.5, 24.5, 43.5, 10.25), ui2.rect(2.5, 36, 43.5, 10.25), ui2.rect(2.5, 47.5, 43.5, 10.25)]
    assert ui2.grid_frames(ui2.GridConfig{...config, frame: ui2.rect(0, 0, 49.25, 60.25)}, 5)! == one_column
    assert ui2.grid_preferred_size(ui2.GridConfig{...config, frame: ui2.rect(0, 0, 49, 300), auto_columns_min_width: 20.5}, sizes)! == ui2.rect(0, 0, 26.25, 60.25)
    assert ui2.grid_preferred_size(ui2.GridConfig{...config, frame: ui2.rect(0, 0, 49.25, 300), auto_columns_min_width: 20.5}, sizes)! == ui2.rect(0, 0, 49.25, 37.25)
    mut app := &State{}
    narrow := build(mut app).children[0]
    assert narrow.frame == ui2.rect(0, 0, 49.25, 60.25)
    assert narrow.children.map(it.frame) == one_column
    app.minimum = 20.5
    app.cap = 2
    capped := build(mut app).children[0]
    assert capped.frame == ui2.rect(0, 0, 49.25, 37.25)
    assert capped.children.map(it.frame) == [ui2.rect(2.5, 1.5, 20.5, 10.25), ui2.rect(25.5, 1.5, 20.5, 10.25), ui2.rect(2.5, 13, 20.5, 10.25), ui2.rect(25.5, 13, 20.5, 10.25), ui2.rect(2.5, 24.5, 20.5, 10.25)]
    println("fractional padding/gaps, selected-width threshold and max_columns PASS")
}')
}

fn test_selected_auto_grid_nested_height_measurement_has_bounded_fresh_child_builds() {
	run_bounded_layout_fixture('selected_auto_grid_nested', 'Absolute(width: 300, height: 300) {
    Grid(auto_columns_min_width: 100) {
        View() {
            View() {
                Label(width: app.leaf_width(), height: 20)
            }
        }
        View() {
            View() {
                Label(width: app.leaf_width(), height: 20)
            }
        }
        View() {
            View() {
                Label(width: app.leaf_width(), height: 20)
            }
        }
        View() {
            View() {
                Label(width: app.leaf_width(), height: 20)
            }
        }
        View() {
            View() {
                Label(width: app.leaf_width(), height: 20)
            }
        }
    }
}', 'import ui2
@[heap]
struct State {
pub mut:
    evaluations int
    value f64 = 20
}
// leaf_width counts property evaluation while returning a stable construction value.
pub fn (mut app State) leaf_width() f64 { app.evaluations++; return app.value }
fn build(mut app State) ui2.Element { return $vml("view.vml") }
fn main() {
    mut app := &State{}
    first := build(mut app).children[0]
    assert first.frame == ui2.rect(0, 0, 60, 100)
    assert first.children.map(it.frame) == [ui2.rect(0, 0, 60, 20), ui2.rect(0, 20, 60, 20), ui2.rect(0, 40, 60, 20), ui2.rect(0, 60, 60, 20), ui2.rect(0, 80, 60, 20)]
    for child in first.children {
        assert child.children[0].frame == ui2.rect(0, 0, 60, 20)
        assert child.children[0].children[0].frame == ui2.rect(0, 0, 20, 20)
    }
    assert app.evaluations > 0 && app.evaluations <= 20, app.evaluations.str()
    previous := app.evaluations
    app.value = 25
    second := build(mut app).children[0]
    assert second.frame == ui2.rect(0, 0, 75, 100)
    assert second.children.map(it.frame) == [ui2.rect(0, 0, 75, 20), ui2.rect(0, 20, 75, 20), ui2.rect(0, 40, 75, 20), ui2.rect(0, 60, 75, 20), ui2.rect(0, 80, 75, 20)]
    for child in second.children { assert child.children[0].children[0].frame == ui2.rect(0, 0, 25, 20) }
    assert app.evaluations > previous && app.evaluations - previous <= 20, app.evaluations.str()
    println("nested five-child selected Grid evaluations: first=" + previous.str() + " second=" + (app.evaluations - previous).str())
}')
}

fn test_selected_auto_grid_preserves_authored_inherited_and_allocated_zero_axes() {
	run_bounded_layout_fixture('selected_auto_grid_axes', 'Absolute(width: 300, height: 300) {
    Grid(width: 0, height: 0, auto_columns_min_width: 100, padding: 1.25) {
        Label(width: 20, height: 20)
        Label(width: 20, height: 20)
    }
    Row(width: 0, height: 120, align_items: start) {
        Grid(auto_columns_min_width: 100, padding: 1.25) {
            Label(width: 20, height: 20)
            Label(width: 20, height: 20)
        }
    }
    View(width: 60, height: 40) {
        Grid(auto_columns_min_width: 100) {
            Label(width: 20, height: 20)
            Label(width: 20, height: 20)
            Label(width: 20, height: 20)
            Label(width: 20, height: 20)
            Label(width: 20, height: 20)
        }
    }
    Grid(height: 0, auto_columns_min_width: 100) {
        Label(width: 20, height: 20)
        Label(width: 20, height: 20)
    }
}', 'import ui2
fn main() {
    tree := $vml("view.vml")
    zero := tree.children[0]
    assert zero.frame == ui2.rect(0, 0, 0, 0)
    assert zero.children.map(it.frame) == [ui2.rect(0, 0, 0, 0), ui2.rect(0, 0, 0, 0)]
    allocated := tree.children[1].children[0]
    assert allocated.frame == ui2.rect(0, 0, 0, 42.5)
    assert allocated.children.map(it.frame) == [ui2.rect(0, 1.25, 0, 20), ui2.rect(0, 21.25, 0, 20)]
    inherited := tree.children[2].children[0]
    assert inherited.frame == ui2.rect(0, 0, 60, 40)
    assert inherited.children.map(it.frame) == [ui2.rect(0, 0, 60, 8), ui2.rect(0, 8, 60, 8), ui2.rect(0, 16, 60, 8), ui2.rect(0, 24, 60, 8), ui2.rect(0, 32, 60, 8)]
    height_zero := tree.children[3]
    assert height_zero.frame == ui2.rect(0, 0, 40, 0)
    assert height_zero.children.map(it.frame) == [ui2.rect(0, 0, 40, 0), ui2.rect(0, 0, 40, 0)]
    println("authored/inherited height, explicit/allocated zero and fitted padding PASS")
}')
}

fn test_auto_grid_natural_padding_and_following_descendant_refs() {
	run_bounded_layout_fixture('auto_grid_natural', 'Row(width: 300, height: 100, align_items: start) {
    View(id: "shell") {
        Grid(id: "cells", columns: 2, padding: 10) {
            Label(id: "cell", width: 20, height: 20)
        }
    }
    Absolute {
        Label(width: cells.width, height: shell.height, font_size: cell.width)
    }
}', 'import ui2
fn main() {
    tree := $vml("view.vml")
    shell := tree.children[0]
    grid := shell.children[0]
    assert shell.frame == ui2.rect(0, 0, 60, 40)
    assert grid.frame == ui2.rect(0, 0, 60, 40)
    assert grid.children[0].frame == ui2.rect(10, 10, 20, 20)
    assert tree.children[1].frame == ui2.rect(60, 0, 60, 40)
    assert tree.children[1].children[0].text_style.size == 20
    println("auto padded Grid natural axes and descendant references PASS")
}')
}

fn test_auto_grid_constraint_axes_fractional_tracks_and_width_remeasurement() {
	run_bounded_layout_fixture('auto_grid_constraints', 'Absolute(width: 300, height: 300) {
    View(width: 100, height: 60) {
        Grid(id: "inherited", columns: 2, padding: 1.25, spacing_x: 2.5) {
            Label(width: 20.5, height: 10)
        }
    }
    View() {
        Grid(width: 80, height: 30, columns: 2, padding: 1.25, spacing_x: 2.5) {
            Label(width: 20.5, height: 10)
        }
    }
    Row(width: 100, height: 60, align_items: start) {
        Grid(columns: 2, padding: 1.25, spacing_x: 2.5, flex_grow: 1) {
            Label(width: 20.5, height: 10)
        }
    }
    Row(width: 100, height: 200, align_items: start) {
        Grid(columns: 2, padding: 5, flex_grow: 1) {
            Label(text: "WW WW WW WW WW WW", lines: 10)
        }
    }
    Label(x: inherited.width, width: inherited.height, height: 20)
}', 'import ui2
fn main() {
    tree := $vml("view.vml")
    inherited := tree.children[0].children[0]
    assert inherited.frame == ui2.rect(0, 0, 100, 60)
    assert inherited.children[0].frame == ui2.rect(1.25, 1.25, 47.5, 57.5)
    explicit := tree.children[1].children[0]
    assert tree.children[1].frame == ui2.rect(0, 0, 80, 30)
    assert explicit.frame == ui2.rect(0, 0, 80, 30)
    assert explicit.children[0].frame == ui2.rect(1.25, 1.25, 37.5, 27.5)
    allocated := tree.children[2].children[0]
    assert allocated.frame == ui2.rect(0, 0, 100, 12.5)
    assert allocated.children[0].frame == ui2.rect(1.25, 1.25, 47.5, 10)
    size := ui2.measure_layout_text("WW WW WW WW WW WW", ui2.TextStyle{lines: 10}, 45) or { panic(err) }
    text_grid := tree.children[3].children[0]
    assert text_grid.frame == ui2.rect(0, 0, 100, size.height + 10)
    assert text_grid.children[0].frame == ui2.rect(5, 5, 45, size.height)
    assert tree.children[4].frame == ui2.rect(100, 0, 60, 20)
    println("padded Grid inherited, explicit, allocated and fractional constraints PASS")
}')
}

fn test_auto_wrap_unoffered_main_axes_and_following_sibling_refs() {
	for tag, expected in {
		'Row':    '65, 20'
		'Column': '30, 45'
	} {
		run_bounded_layout_fixture('auto_wrap_${tag}', 'Absolute {
    View(id: "shell") {
        ${tag}(id: "flow", wrap: true, gap: 5, align_items: start) {
            Label(id: "first", width: 30, height: 20)
            Absolute {
                Label(width: first.width, height: first.height)
            }
        }
    }
    Label(x: flow.width, y: shell.height, width: shell.width, height: flow.height)
}', 'import ui2
fn main() {
    tree := $vml("view.vml")
    shell := tree.children[0]
    flow := shell.children[0]
    assert shell.frame == ui2.rect(0, 0, ${expected})
    assert flow.frame == shell.frame
    assert flow.children[0].frame == ui2.rect(0, 0, 30, 20)
    assert flow.children[1].frame == ${if tag == 'Row' { 'ui2.rect(35, 0, 30, 20)' } else { 'ui2.rect(0, 25, 30, 20)' }}
    assert tree.children[1].frame == ui2.rect(flow.frame.width, shell.frame.height, shell.frame.width, flow.frame.height)
    println("auto ${tag} chosen main axis and following references PASS")
}')
	}
}

fn test_auto_wrap_fractional_padding_gaps_and_explicit_constraints() {
	run_bounded_layout_fixture('auto_wrap_fractional', 'Absolute() {
    View() {
        Row(
            wrap: true,
            gap: 4.25,
            line_gap: 6.75,
            align_items: start,
            padding_left: 2.5,
            padding_right: 3.25,
            padding_top: 1.5,
            padding_bottom: 2.5,
        ) {
            Label(width: 30.5, height: 21.25)
            Label(width: 30.5, height: 21.25)
        }
    }
    View() {
        Column(
            wrap: true,
            gap: 4.25,
            line_gap: 6.75,
            align_items: start,
            padding_left: 2.5,
            padding_right: 3.25,
            padding_top: 1.5,
            padding_bottom: 2.5,
        ) {
            Label(width: 30.5, height: 21.25)
            Label(width: 30.5, height: 21.25)
        }
    }
    View(width: 36.25) {
        Row(
            wrap: true,
            gap: 4.25,
            line_gap: 6.75,
            align_items: start,
            padding_left: 2.5,
            padding_right: 3.25,
            padding_top: 1.5,
            padding_bottom: 2.5,
        ) {
            Label(width: 30.5, height: 21.25)
            Label(width: 30.5, height: 21.25)
        }
    }
    View(height: 25.25) {
        Column(
            wrap: true,
            gap: 4.25,
            line_gap: 6.75,
            align_items: start,
            padding_left: 2.5,
            padding_right: 3.25,
            padding_top: 1.5,
            padding_bottom: 2.5,
        ) {
            Label(width: 30.5, height: 21.25)
            Label(width: 30.5, height: 21.25)
        }
    }
    View() {
        Row(width: 30, height: 70, wrap: true, gap: 5, align_items: start) {
            Label(width: 30, height: 20)
            Label(width: 30, height: 20)
        }
    }
    View() {
        Column(width: 70, height: 20, wrap: true, gap: 5, align_items: start) {
            Label(width: 30, height: 20)
            Label(width: 30, height: 20)
        }
    }
}', 'import ui2
fn main() {
    tree := $vml("view.vml")
    assert tree.children[0].frame == ui2.rect(0, 0, 71, 25.25)
    assert tree.children[0].children[0].children.map(it.frame) == [ui2.rect(2.5, 1.5, 30.5, 21.25), ui2.rect(37.25, 1.5, 30.5, 21.25)]
    assert tree.children[1].frame == ui2.rect(0, 0, 36.25, 50.75)
    assert tree.children[1].children[0].children.map(it.frame) == [ui2.rect(2.5, 1.5, 30.5, 21.25), ui2.rect(2.5, 27, 30.5, 21.25)]
    assert tree.children[2].frame == ui2.rect(0, 0, 36.25, 53.25)
    assert tree.children[2].children[0].children[1].frame == ui2.rect(2.5, 29.5, 30.5, 21.25)
    assert tree.children[3].frame == ui2.rect(0, 0, 73.5, 25.25)
    assert tree.children[3].children[0].children[1].frame == ui2.rect(39.75, 1.5, 30.5, 21.25)
    assert tree.children[4].frame == ui2.rect(0, 0, 30, 70)
    assert tree.children[5].frame == ui2.rect(0, 0, 70, 20)
    println("auto wrapping fractional natural and fixed dimensions PASS")
}')
}

fn test_auto_wrap_and_grid_explicit_and_allocated_zero_are_not_natural_axes() {
	run_bounded_layout_fixture('auto_axes_zero', 'Absolute() {
    View() {
        Row(id: "row", width: 0, wrap: true, gap: 5, align_items: start) {
            Label(width: 30, height: 20)
            Label(width: 30, height: 20)
        }
    }
    View() {
        Column(id: "column", height: 0, wrap: true, gap: 5, align_items: start) {
            Label(width: 30, height: 20)
            Label(width: 30, height: 20)
        }
    }
    Row(width: 0, height: 50, align_items: start) {
        Row(wrap: true, gap: 5, align_items: start) {
            Label(width: 30, height: 20)
            Label(width: 30, height: 20)
        }
    }
    View() {
        Grid(width: 0, columns: 2) {
            Label(width: 20, height: 20)
        }
    }
    Row(width: 0, height: 50, align_items: start) {
        Grid(columns: 2) {
            Label(width: 20, height: 20)
        }
    }
    Label(x: row.width, width: column.height, height: 20)
}', 'import ui2
fn main() {
    tree := $vml("view.vml")
    assert tree.children[0].children[0].frame == ui2.rect(0, 0, 0, 45)
    assert tree.children[1].children[0].frame == ui2.rect(0, 0, 65, 0)
    assert tree.children[2].children[0].frame == ui2.rect(0, 0, 0, 45)
    assert tree.children[3].children[0].frame == ui2.rect(0, 0, 0, 20)
    assert tree.children[4].children[0].frame == ui2.rect(0, 0, 0, 20)
    assert tree.children[5].frame == ui2.rect(0, 0, 0, 20)
    println("explicit and width-pass allocated zero dimensions PASS")
}')
	root := sibling_fixture_root('auto_grid_invalid_zero')
	defer {
		if os.getenv('VML_SIBLING_KEEP_FIXTURES') != '1' { os.rmdir_all(root) or {} }
	}
	os.write_file(os.join_path(root, 'view.vml'), 'Absolute() {
    View() {
        Grid(width: 0, columns: 2, padding: 10) {
            Label(width: 20, height: 20)
        }
    }
}')!
	os.write_file(os.join_path(root, 'main.v'), 'import ui2\nfn main() { _ = $vml("view.vml") }')!
	build := compile_sibling_fixture(root)
	assert build.exit_code == 0, build.output
	result := os.exec([os.join_path(root, 'app')])
	os.write_file(os.join_path(root, 'runtime.log'), result.output)!
	os.write_file(os.join_path(root, 'runtime-exit.txt'), result.exit_code.str())!
	assert result.exit_code != 0
	assert result.output.contains('grid dimensions must be finite and non-negative'), result.output
}
