module main

import ui2

struct CombinedRow {
pub:
	id int
}

struct CombinedApp {
pub mut:
	count    int
	checked  bool
	message  string
	calls    int
	taps     int
	value    int
	rows     []CombinedRow
	named    ui2.ElementCallback = unsafe { nil }
	reentry  ui2.ElementCallback = unsafe { nil }
	payloads []ui2.ElementEvent
}

// record observes typed descendant locals and the live model.
pub fn (mut app CombinedApp) record(value int) {
	app.calls++
	app.value = value
}

// tap observes a tap independently of change bindings.
pub fn (mut app CombinedApp) tap(value int) {
	app.taps++
	app.value = value
}

fn combined_tree(mut app CombinedApp) ui2.Element { return $vml('combined_callbacks.vml') }

fn test_visual_structure_callbacks_keep_locals_binding_order_and_event_routes() {
	mut app := CombinedApp{ count: 3, rows: [CombinedRow{7}, CombinedRow{9}] }
	root := combined_tree(mut app)
	assert root.children[0].children.len == 2
	controls := root.children[0].children[0].children
	assert controls[0].id == 'checked'
	app.count = 100
	controls[0].on_event(ui2.ElementEvent{ kind: .change, checked: true })
	assert app.checked && app.calls == 1 && app.value == 116
	controls[0].on_event(ui2.ElementEvent{ kind: .change, checked: false })
	assert !app.checked && app.calls == 2 && app.value == 127
	controls[0].on_event(ui2.ElementEvent{ kind: .tap, checked: true })
	assert !app.checked && app.calls == 2 && app.taps == 1 && app.value == 105
	controls[1].on_event(ui2.ElementEvent{ kind: .tap })
	assert app.calls == 3 && app.value == 205
	controls[3].on_event(ui2.ElementEvent{ kind: .scroll, value: 12 })
	assert app.calls == 4 && app.value == 105 && app.taps == 1
	for kind in [ui2.ElementEventKind.change, .submit, .pointer_down, .pointer_drag, .pointer_up,
		.long_press, .swipe_left, .link] {
		controls[0].on_event(ui2.ElementEvent{ kind: kind, checked: false })
		controls[3].on_event(ui2.ElementEvent{ kind: kind })
	}
	// The one change above consumes the Checkbox binding; Scroll ignores all of them.
	assert app.calls == 5 && app.taps == 1
	controls[3].on_event(ui2.ElementEvent{ kind: .tap })
	assert app.calls == 5 && app.taps == 2 && app.value == 100

	retained := root.children[1].children[0].on_event
	assert root.children[1].key == '7'
	id := root.children[1].id
	app.rows.reverse_in_place()
	reordered := combined_tree(mut app)
	assert reordered.children[2].id == id && reordered.children[2].key == root.children[1].key
	app.rows = app.rows[..1]
	app.count = 200
	retained(ui2.ElementEvent{ kind: .tap })
	assert app.value == 214
}

fn test_shared_visual_named_callbacks_keep_original_payload_during_reentry() {
	mut app := &CombinedApp{}
	app.named = fn [mut app] (event ui2.ElementEvent) {
		assert event.kind == .change && app.message == event.text
		app.payloads << event
		if event.text == 'outer niño' {
			app.reentry(ui2.ElementEvent{ kind: .change, id: 'nested-origin', text: 'inner café', value: 9.5 })
			assert app.message == 'inner café'
		}
	}
	root := combined_tree(mut app)
	app.reentry = root.children[0].children[0].children[2].on_event
	outer := ui2.ElementEvent{ kind: .change, id: 'original-element', text: 'outer niño', value: 73.5, checked: true }
	app.reentry(outer)
	assert app.payloads.len == 2 && app.payloads[0] == outer
	assert app.payloads[1].id == 'nested-origin' && app.payloads[1].value == 9.5
	app.named = unsafe { nil }
	nil_root := combined_tree(mut app)
	nil_root.children[0].children[0].children[2].on_event(ui2.ElementEvent{ kind: .change, text: 'nil callback' })
	assert app.message == 'nil callback' && app.payloads.len == 2
}
