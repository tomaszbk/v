// vtest build: ui2_tests? // Requires the ui2 module; opt in with -d ui2_tests.
module main

import ui2

@[heap]
pub struct MotionApp {
pub mut:
	motion ui2.MotionConfig = ui2.MotionConfig{ reduced_motion: true }
}

fn motion_tree(mut app MotionApp) ui2.Element {
	return $vml('view.vml', ui2.rect(0, 0, 200, 100))
}

fn test_motion_opacity_and_transform_arguments_patch_one_retained_node() ! {
	mut app := &MotionApp{}
	initial := motion_tree(mut app)
	mut root := initial.compiled_node
	defer { root.dispose_document() or { panic(err) } }
	assert initial.opacity == 1 && initial.translate_x == 0 && !initial.hidden
	assert (initial.motion or { panic('missing motion') }).reduced_motion

	initial.children[0].on_event(ui2.ElementEvent{ kind: .click })
	changed := root.element()
	assert changed.opacity == 0.25 && changed.translate_x == 16 && changed.hidden
	assert changed.compiled_node == initial.compiled_node
	assert changed.children[0].compiled_node == initial.children[0].compiled_node

	app.motion = ui2.MotionConfig{ reduced_motion: false }
	root.component.invalidate_app()!
	configured := root.element()
	assert !(configured.motion or { panic('missing motion') }).reduced_motion
	assert configured.compiled_node == initial.compiled_node
	assert configured.opacity == 0.25 && configured.translate_x == 16
}
