package actions

import "../input"
import "../perception"
import "../uia"
import "../window"
import "core:sys/windows"

// The actions module turns an app query plus a rendered-tree index into a
// real input action. It prefers UIA patterns (no cursor, no focus) and falls
// back to SendInput only when a target cannot be driven through accessibility.
// See ARCHITECTURE.md (Actions) and DESIGN.md.

// Error is this package's error type.
Error :: enum {
	// None reports a successful action.
	None,
	// Create_Failed reports that the action session could not be created.
	Create_Failed,
	// Index_Out_Of_Range reports that no element exists at the requested index.
	Index_Out_Of_Range,
	// Element_Not_Found reports that no element matched the requested name.
	Element_Not_Found,
	// Pattern_Not_Available reports that the element does not support the needed pattern.
	Pattern_Not_Available,
	// Action_Failed reports that the underlying action returned an error.
	Action_Failed,
	// Focus_Failed reports that the target window could not be foregrounded.
	Focus_Failed,
	// Key_Parse_Failed reports that a key spec could not be parsed.
	Key_Parse_Failed,
}

// Method selects how a click is delivered.
Method :: enum {
	// Auto prefers Invoke and falls back to a SendInput click at the element
	// rect center when the element has no Invoke pattern.
	Auto,
	// Uia only ever uses the Invoke pattern.
	Uia,
	// SendInput always clicks the element rect center (or given coordinates).
	SendInput,
}

// Direction names a scroll direction.
Direction :: enum {
	Up,
	Down,
	Left,
	Right,
}

// Session holds a live UI Automation connection used for actions.
Session :: struct {
	perception: perception.Session,
}

// open creates an action session, initializing COM. Call close when done.
open :: proc() -> (Session, Error) {
	p, err := perception.open()
	if err != .None {
		return {}, .Create_Failed
	}
	return Session{perception = p}, .None
}

// close releases an action session and uninitializes COM.
close :: proc(s: ^Session) {
	perception.close(&s.perception)
}

// element_at_index resolves the element at the given walk index for a window
// handle. The caller releases the returned element with uia.release_element.
element_at_index :: proc(
	s: ^Session,
	hwnd: windows.HWND,
	index: int,
	limits: perception.Limits,
) -> (
	uia.Element,
	Error,
) {
	root, err := uia.element_from_handle(&s.perception.auto, hwnd)
	if err != .None {
		return {}, .Index_Out_Of_Range
	}
	defer uia.release_element(&root)

	el, perr := perception.element_at_index(&s.perception, &root, index, limits)
	if perr != .None {
		return {}, .Index_Out_Of_Range
	}
	return el, .None
}

// click_name clicks the first element whose accessible name contains the
// given substring. The method selects whether to use Invoke, a SendInput
// rect-center click, or both.
click_name :: proc(
	s: ^Session,
	hwnd: windows.HWND,
	name: string,
	method: Method,
	limits: perception.Limits,
) -> Error {
	root, err := uia.element_from_handle(&s.perception.auto, hwnd)
	if err != .None {
		return .Index_Out_Of_Range
	}
	defer uia.release_element(&root)

	el, perr := perception.element_by_name(&s.perception, &root, name, limits)
	if perr != .None {
		return .Element_Not_Found
	}
	defer uia.release_element(&el)

	switch method {
	case .Uia:
		return map_uia_error(uia.invoke(&el))
	case .SendInput:
		return click_rect_center(hwnd, &el)
	case .Auto:
		if e := uia.invoke(&el); e == .None {
			return .None
		} else if e != .Pattern_Not_Available {
			return map_uia_error(e)
		}
		return click_rect_center(hwnd, &el)
	}
	return .None
}

// click_index clicks the element at the given index. The method selects
// whether to use Invoke, a SendInput rect-center click, or both.
click_index :: proc(
	s: ^Session,
	hwnd: windows.HWND,
	index: int,
	method: Method,
	limits: perception.Limits,
) -> Error {
	el, err := element_at_index(s, hwnd, index, limits)
	if err != .None {
		return err
	}
	defer uia.release_element(&el)

	switch method {
	case .Uia:
		return map_uia_error(uia.invoke(&el))
	case .SendInput:
		return click_rect_center(hwnd, &el)
	case .Auto:
		if e := uia.invoke(&el); e == .None {
			return .None
		} else if e != .Pattern_Not_Available {
			return map_uia_error(e)
		}
		return click_rect_center(hwnd, &el)
	}
	return .None
}

// click_rect_center clicks the middle of an element's bounding rect via
// SendInput. It is the fallback when an element cannot be invoked.
click_rect_center :: proc(hwnd: windows.HWND, el: ^uia.Element) -> Error {
	rect, err := uia.bounding_rect(el)
	if err != .None || rect.right <= rect.left || rect.bottom <= rect.top {
		return .Action_Failed
	}
	x := (rect.left + rect.right) / 2
	y := (rect.top + rect.bottom) / 2
	return click_xy(hwnd, x, y)
}

// click_xy clicks at absolute screen coordinates via SendInput.
click_xy :: proc(hwnd: windows.HWND, x, y: i32) -> Error {
	if !window.force_foreground(hwnd) {
		return .Focus_Failed
	}
	input.click(x, y)
	return .None
}

// type_text focuses the target window, then sends the text as Unicode
// keyboard events.
type_text :: proc(hwnd: windows.HWND, text: string) -> Error {
	if !window.force_foreground(hwnd) {
		return .Focus_Failed
	}
	input.type_text(text)
	return .None
}

// press_key parses an xdotool-style key spec and presses the chord(s) into
// the focused target window.
press_key :: proc(hwnd: windows.HWND, spec: string) -> Error {
	combos, perr := parse_keys(spec)
	if perr != "" {
		return .Key_Parse_Failed
	}
	defer destroy_key_combos(combos)

	if !window.force_foreground(hwnd) {
		return .Focus_Failed
	}
	for combo in combos {
		press_combo(combo)
	}
	return .None
}

// press_combo holds the combo's modifiers while tapping its keys.
press_combo :: proc(combo: Key_Combo) {
	mods := modifier_keys(combo.modifiers)
	for m in mods {
		if m.vk != 0 {
			input.key_down(m.vk, m.extended)
		}
	}
	for key in combo.keys {
		input.press_key(key.vk, key.extended)
	}
	for m in mods {
		if m.vk != 0 {
			input.key_up(m.vk, m.extended)
		}
	}
}

// scroll_index scrolls the element at the given index. It prefers the UIA
// Scroll pattern and falls back to wheel events over the element's center.
scroll_index :: proc(
	s: ^Session,
	hwnd: windows.HWND,
	index: int,
	dir: Direction,
	pages: int,
	limits: perception.Limits,
) -> Error {
	el, err := element_at_index(s, hwnd, index, limits)
	if err != .None {
		return err
	}
	defer uia.release_element(&el)

	horizontal, vertical := scroll_amounts(dir)
	scroll_err := uia.scroll(&el, horizontal, vertical)
	if scroll_err == .None {
		for _ in 1 ..< pages {
			if e := uia.scroll(&el, horizontal, vertical); e != .None {
				return map_uia_error(e)
			}
		}
		return .None
	}
	if scroll_err != .Pattern_Not_Available {
		return map_uia_error(scroll_err)
	}

	rect, rerr := uia.bounding_rect(&el)
	if rerr != .None || rect.right <= rect.left || rect.bottom <= rect.top {
		return .Action_Failed
	}
	if !window.force_foreground(hwnd) {
		return .Focus_Failed
	}
	x := (rect.left + rect.right) / 2
	y := (rect.top + rect.bottom) / 2
	windows.SetCursorPos(x, y)

	delta := i32(120) * i32(pages)
	horizontal_wheel := dir == .Left || dir == .Right
	#partial switch dir {
	case .Down, .Right:
		delta = -delta
	case:
	// Up and Left keep the default positive delta.
	}
	input.scroll_wheel(delta, horizontal_wheel)
	return .None
}

// scroll_amounts maps a direction to UIA ScrollAmount axis values. The other
// axis is left at No_Amount so it is untouched.
scroll_amounts :: proc(dir: Direction) -> (horizontal, vertical: i32) {
	switch dir {
	case .Up:
		return uia.Scroll_Amount_No_Amount, uia.Scroll_Amount_Large_Decrement
	case .Down:
		return uia.Scroll_Amount_No_Amount, uia.Scroll_Amount_Large_Increment
	case .Left:
		return uia.Scroll_Amount_Large_Decrement, uia.Scroll_Amount_No_Amount
	case .Right:
		return uia.Scroll_Amount_Large_Increment, uia.Scroll_Amount_No_Amount
	}
	return
}

// set_value_index writes a value into the element at the given index via the
// Value pattern.
set_value_index :: proc(
	s: ^Session,
	hwnd: windows.HWND,
	index: int,
	value: string,
	limits: perception.Limits,
) -> Error {
	el, err := element_at_index(s, hwnd, index, limits)
	if err != .None {
		return err
	}
	defer uia.release_element(&el)
	return map_uia_error(uia.set_value(&el, value))
}

// focus brings a window to the foreground and verifies it is active.
focus :: proc(hwnd: windows.HWND) -> Error {
	if window.force_foreground(hwnd) {
		return .None
	}
	return .Focus_Failed
}

// wake sends WM_GETOBJECT to a window and all of its children so Chromium
// apps materialize their accessibility tree.
wake :: proc(hwnd: windows.HWND) -> Error {
	if window.wake(hwnd) > 0 {
		return .None
	}
	return .Action_Failed
}

// map_uia_error translates a uia.Error into an actions.Error.
map_uia_error :: proc(e: uia.Error) -> Error {
	switch e {
	case .None:
		return .None
	case .Pattern_Not_Available:
		return .Pattern_Not_Available
	case .Create_Failed,
	     .Element_Unavailable,
	     .Name_Unavailable,
	     .Action_Failed,
	     .Text_Unavailable:
		return .Action_Failed
	}
	return .Action_Failed
}