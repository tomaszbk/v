module main

import ui2

enum CallbackChoice {
	left
	right
}

fn callback_event(kind ui2.ElementEventKind) ui2.ElementEvent {
	return ui2.ElementEvent{ kind: kind }
}

struct CallbackModel {
pub mut:
	count          int = 2
	received       int
	calls          int
	checked        bool
	active         bool
	level          f64
	message        string = 'before'
	received_text  string
	choice         CallbackChoice
	groups         []Group
	named_callback ui2.ElementCallback = unsafe { nil }
	nil_callback   ui2.ElementCallback = unsafe { nil }
}

// record observes the argument at event time.
pub fn (mut app CallbackModel) record(value int) {
	app.received = value
	app.calls++
}

// record_text observes a string argument after its text binding has written.
pub fn (mut app CallbackModel) record_text(value string) {
	app.received_text = value
	app.calls++
}

fn callback_tree(mut app CallbackModel) ui2.Element { return $vml('events.vml') }

fn callback_rows(mut app CallbackModel) ui2.Element { return $vml('event_rows.vml') }

fn empty_menus() []ui2.Menu { return $vml('empty_menus.vml') }

fn test_compound_arguments_read_live_model_after_binding() {
	mut app := CallbackModel{}
	root := callback_tree(mut app)
	app.count = 100
	root.children[0].on_event(callback_event(.tap))
	assert app.calls == 1 && app.received == 101
	root.children[1].on_event(ui2.ElementEvent{ kind: .change, checked: true })
	assert app.checked && app.calls == 2 && app.received == 11
	root.children[14].on_event(ui2.ElementEvent{ kind: .change, text: 'niño' })
	assert app.calls == 3 && app.received_text == 'niño café'
	root.children[15].on_event(callback_event(.tap))
	assert app.choice == .right
}

fn observing_callback(mut app CallbackModel) ui2.ElementCallback {
	return fn [mut app] (payload ui2.ElementEvent) {
		assert payload.kind == .change
		assert payload.text == 'niño café' && payload.value == 73.5 && payload.checked
		match payload.id {
			'text' {
				assert app.message == payload.text
			}
			'value' {
				assert app.level == payload.value
			}
			'checked' {
				assert app.checked == payload.checked
			}
			'active' {
				assert app.active == payload.checked
			}
			else {
				assert false
			}
		}
		app.calls++
	}
}

fn test_named_callbacks_observe_bound_payload_and_original_event_once() {
	mut app := CallbackModel{}
	app.named_callback = observing_callback(mut app)
	root := callback_tree(mut app)
	for index, id in ['text', 'value', 'checked', 'active'] {
		root.children[index + 2].on_event(ui2.ElementEvent{
			kind:    .change
			id:      id
			text:    'niño café'
			value:   73.5
			checked: true
		})
		assert app.calls == index + 1
	}
}

fn gesture_callback(mut app CallbackModel) ui2.ElementCallback {
	return fn [mut app] (payload ui2.ElementEvent) {
		assert payload.kind != .scroll && payload.kind != .submit
		app.calls++
	}
}

fn test_scroll_requires_explicit_handler_and_gesture_dispatch_is_once() {
	mut app := CallbackModel{}
	app.named_callback = gesture_callback(mut app)
	root := callback_tree(mut app)
	root.children[6].on_event(callback_event(.scroll))
	root.children[6].on_event(callback_event(.submit))
	assert app.calls == 0
	gestures := [ui2.ElementEventKind.tap, .pointer_down, .pointer_drag, .pointer_up, .long_press,
		.swipe_left, .link]
	for index, kind in gestures {
		root.children[6].on_event(callback_event(kind))
		assert app.calls == index + 1
	}
	app.calls = 0
	app.count = 50
	root.children[7].on_event(callback_event(.scroll))
	assert app.calls == 1 && app.received == 52
	root.children[7].on_event(callback_event(.tap))
	assert app.calls == 2 && app.received == 1
	root.children[8].on_event(callback_event(.submit))
	assert app.calls == 3 && app.received == 4
	root.children[8].on_event(callback_event(.pointer_down))
	assert app.calls == 4 && app.received == 5
	for kind in [ui2.ElementEventKind.scroll, .pointer_drag, .pointer_up, .long_press, .swipe_left,
		.link] {
		root.children[8].on_event(callback_event(kind))
		root.children[9].on_event(callback_event(kind))
	}
	assert app.calls == 4 && app.count == 50
	root.children[9].on_event(callback_event(.tap))
	assert app.count == 51
}

fn test_binding_only_and_nil_named_callback_keep_payload() {
	mut app := CallbackModel{}
	root := callback_tree(mut app)
	root.children[10].on_event(ui2.ElementEvent{ kind: .change, text: 'mañana' })
	assert app.message == 'mañana'
	root.children[11].on_event(ui2.ElementEvent{ kind: .change, text: 'niño' })
	assert app.message == 'niño'
	root.children[12].on_event(ui2.ElementEvent{ kind: .change, checked: true })
	assert app.checked
	root.children[12].on_event(callback_event(.scroll))
	assert app.checked
	root.children[12].on_event(ui2.ElementEvent{ kind: .pointer_down, checked: false })
	assert !app.checked
	for index in 2 .. 6 {
		root.children[index].on_event(ui2.ElementEvent{
			kind:    .change
			text:    'nil payload'
			value:   42.5
			checked: true
		})
	}
	assert app.message == 'nil payload' && app.level == 42.5 && app.checked && app.active
	root.children[16].on_event(callback_event(.tap))
	assert app.calls == 0
}

fn test_retained_imported_nested_row_callback_keeps_record_and_live_app() {
	mut app := CallbackModel{
		groups: [Group{'first', [Row{1, 'niño'}, Row{2, 'café'}]},
			Group{'second', [Row{1, 'mañana'}]}]
	}
	before := callback_rows(mut app)
	retained := before.children[1].children[1].on_event
	app.groups[0].rows.reverse_in_place()
	app.groups.reverse_in_place()
	app.count = 100
	after := callback_rows(mut app)
	assert before.children[1].id == after.children[1].id
	assert before.children[1].children[1].id == after.children[1].children[1].id
	assert before.children[0].id != before.children[2].id
	retained(callback_event(.tap))
	assert app.calls == 1 && app.received == 102
	app.groups.clear()
	app.count = 200
	retained(callback_event(.tap))
	assert app.calls == 2 && app.received == 202
	assert callback_rows(mut app).children.len == 0
}

fn test_flat_context_menu_and_empty_application_menu_use_public_api() {
	mut app := CallbackModel{}
	root := callback_tree(mut app)
	assert empty_menus().len == 0
	assert root.children[13].menu.len == 1
	assert root.children[13].menu[0].id == 'context'
	app.count = 100
	root.children[13].menu[0].on_select(callback_event(.tap))
	assert app.calls == 1 && app.received == 106
}
