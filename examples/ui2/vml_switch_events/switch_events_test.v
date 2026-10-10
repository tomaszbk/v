// vtest build: ui2_tests? // Requires the ui2 module; opt in with -d ui2_tests.
module main

import ui2

@[heap]
pub struct SwitchEventApp {
pub mut:
	checked        bool
	expects_active bool
	active_calls   int
	change_calls   int
	order          []string
	payloads       []ui2.ElementEvent
	active_handler ui2.ElementCallback = unsafe { nil }
	change_handler ui2.ElementCallback = unsafe { nil }
}

fn switch_event_app(expects_active bool) &SwitchEventApp {
	mut app := &SwitchEventApp{ expects_active: expects_active }
	app.active_handler = fn [mut app] (event ui2.ElementEvent) {
		assert app.checked == event.checked
		app.active_calls++
		app.order << 'active'
		app.payloads << event
		// A second binding write before on_change would erase this mutation.
		app.checked = !event.checked
	}
	app.change_handler = fn [mut app] (event ui2.ElementEvent) {
		assert app.checked == if app.expects_active { !event.checked } else { event.checked }
		app.change_calls++
		app.order << 'change'
		app.payloads << event
	}
	return app
}

fn switch_event_tree(mut app SwitchEventApp) ui2.Element {
	return $vml('switch_events.vml', ui2.rect(0, 0, 300, 90))
}

fn test_switch_calls_both_typed_handlers_in_order_and_binds_once() ! {
	mut app := switch_event_app(true)
	initial := switch_event_tree(mut app)
	mut root := initial.compiled_node
	control := root.element().children[0].children[0]
	for checked in [true, false] {
		event := ui2.ElementEvent{
			kind:    .change
			id:      'original switch'
			checked: checked
			text:    'niño café'
			value:   7.5
		}
		control.on_event(event)
		assert app.active_calls == app.change_calls
		assert app.order == ['active', 'change'].repeat(app.active_calls)
		assert app.payloads[app.payloads.len - 2..] == [event, event]
		assert app.checked == !checked
	}
	assert app.active_calls == 2 && app.change_calls == 2
	for kind in [ui2.ElementEventKind.click, .submit, .scroll] {
		control.on_event(ui2.ElementEvent{ kind: kind, checked: true })
	}
	assert app.active_calls == 2 && app.change_calls == 2
	assert app.order == ['active', 'change', 'active', 'change']
	root.dispose_document()!
}

fn test_switch_active_handler_alone_receives_one_change_and_binding() ! {
	mut app := switch_event_app(true)
	initial := switch_event_tree(mut app)
	mut root := initial.compiled_node
	control := root.element().children[0].children[1]
	event := ui2.ElementEvent{ kind: .change, id: 'active only', checked: true }
	control.on_event(event)
	assert app.active_calls == 1 && app.change_calls == 0
	assert app.order == ['active'] && app.payloads == [event]
	assert !app.checked
	control.on_event(ui2.ElementEvent{ kind: .click, checked: true })
	assert app.active_calls == 1 && app.change_calls == 0 && !app.checked
	root.dispose_document()!
}

fn test_switch_change_handler_alone_receives_one_change_and_binding() ! {
	mut app := switch_event_app(false)
	initial := switch_event_tree(mut app)
	mut root := initial.compiled_node
	control := root.element().children[0].children[2]
	event := ui2.ElementEvent{ kind: .change, id: 'change only', checked: true }
	control.on_event(event)
	assert app.active_calls == 0 && app.change_calls == 1
	assert app.order == ['change'] && app.payloads == [event]
	assert app.checked
	control.on_event(ui2.ElementEvent{ kind: .click, checked: false })
	assert app.active_calls == 0 && app.change_calls == 1 && app.checked
	root.dispose_document()!
}
