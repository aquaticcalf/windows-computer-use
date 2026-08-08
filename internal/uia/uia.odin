package uia

import "binding"
import windows "core:sys/windows"

// The public surface of the UI Automation adapter. Callers and tests only
// ever see these types; the raw COM interfaces live in the "binding" leaf.
// See DESIGN.md (deep modules, dependency classes).

// Error is this package's error type. A zero value of None means success;
// callers can compare against the enum cases to branch on the failure mode.
Error :: enum {
	// None reports a successful call.
	None,
	// Create_Failed reports that the automation session could not be created.
	Create_Failed,
	// Element_Unavailable reports that no element could be resolved.
	Element_Unavailable,
	// Name_Unavailable reports that an element name could not be read.
	Name_Unavailable,
	// Pattern_Not_Available reports that an element does not support the
	// requested pattern.
	Pattern_Not_Available,
	// Action_Failed reports that a pattern action returned an error.
	Action_Failed,
	// Text_Unavailable reports that element text content could not be read.
	Text_Unavailable,
}

// Scroll_Amount values passed to scroll.
Scroll_Amount_Large :: binding.Scroll_Amount_Large
Scroll_Amount_Small :: binding.Scroll_Amount_Small
Scroll_Amount_No_Amount :: binding.Scroll_Amount_No_Amount

// Tree_Scope_Element matches only the element itself.
Tree_Scope_Element :: binding.Tree_Scope_Element
// Tree_Scope_Children matches the element's immediate children.
Tree_Scope_Children :: binding.Tree_Scope_Children
// Tree_Scope_Descendants matches the element and all descendants.
Tree_Scope_Descendants :: binding.Tree_Scope_Descendants

// Rect is an axis-aligned rectangle in screen coordinates.
Rect :: struct {
	left, top, right, bottom: i32,
}

// Automation is a live UI Automation session. It owns the COM automation
// object and a control-view tree walker. Create one with create and release
// it with destroy.
Automation :: struct {
	ptr:    ^binding.IUIAutomation,
	walker: ^binding.IUIAutomationTreeWalker,
}

// Element is a handle to a UI element. It is valid only while the session
// that produced it is alive; release it with release_element when done.
Element :: struct {
	ptr: ^binding.IUIAutomationElement,
}

// Element_Array is a collection of elements returned by find_all. Release it
// with release_array when done.
Element_Array :: struct {
	ptr: ^binding.IUIAutomationElementArray,
}

// create builds a UI Automation session together with its control-view tree
// walker. The caller owns the session and must call destroy when done.
create :: proc() -> (Automation, Error) {
	ptr, hr := binding.create_automation()
	if hr != 0 {
		return {}, .Create_Failed
	}
	walker, whr := binding.get_control_view_walker(ptr)
	if whr != 0 {
		binding.release_automation(ptr)
		return {}, .Create_Failed
	}
	return Automation{ptr = ptr, walker = walker}, .None
}

// destroy releases the automation session and its tree walker.
destroy :: proc(a: ^Automation) {
	if a.ptr != nil {
		binding.release_walker(a.walker)
		binding.release_automation(a.ptr)
		a.ptr = nil
		a.walker = nil
	}
}

// element_from_handle resolves the UI element that owns the given window
// handle. The caller releases the element with release_element.
element_from_handle :: proc(a: ^Automation, hwnd: windows.HWND) -> (Element, Error) {
	ptr, hr := binding.element_from_handle(a.ptr, hwnd)
	if hr != 0 {
		return {}, .Element_Unavailable
	}
	return Element{ptr = ptr}, .None
}

// root_element returns the element for the entire desktop.
root_element :: proc(a: ^Automation) -> (Element, Error) {
	ptr, hr := binding.get_root_element(a.ptr)
	if hr != 0 {
		return {}, .Element_Unavailable
	}
	return Element{ptr = ptr}, .None
}

// release_element releases an element returned by this package.
release_element :: proc(el: ^Element) {
	if el.ptr != nil {
		binding.release_element(el.ptr)
		el.ptr = nil
	}
}

// name returns the element's accessible name. The returned string is
// allocated with the supplied allocator; the caller deletes it.
name :: proc(el: ^Element, allocator := context.allocator) -> (string, Error) {
	bstr, hr := binding.element_name(el.ptr)
	if hr != 0 {
		return "", .Name_Unavailable
	}
	defer binding.free_bstr(bstr)

	length := bstr_length(bstr)
	if length == 0 {
		return "", .None
	}

	text, _ := windows.wstring_to_utf8_alloc(windows.wstring(bstr), length, allocator)
	if len(text) == 0 {
		return "", .None
	}
	return text, .None
}

// control_type returns the element's UIA control type id. Map it to a
// readable role with control_type_name.
control_type :: proc(el: ^Element) -> (i32, Error) {
	id, hr := binding.element_control_type(el.ptr)
	if hr != 0 {
		return 0, .Element_Unavailable
	}
	return id, .None
}

// is_enabled reports whether the element currently accepts input.
is_enabled :: proc(el: ^Element) -> (bool, Error) {
	enabled, hr := binding.element_is_enabled(el.ptr)
	if hr != 0 {
		return false, .Element_Unavailable
	}
	return enabled, .None
}

// bounding_rect returns the element's on-screen rectangle.
bounding_rect :: proc(el: ^Element) -> (Rect, Error) {
	r, hr := binding.element_bounding_rect(el.ptr)
	if hr != 0 {
		return {}, .Element_Unavailable
	}
	return Rect{left = r.left, top = r.top, right = r.right, bottom = r.bottom}, .None
}

// control_type_name maps a UIA control type id to a short, human-readable
// role string ("button", "edit", ...), or "unknown".
control_type_name :: proc(id: i32) -> string {
	switch id {
	case binding.Control_Type_Button:
		return "button"
	case binding.Control_Type_CheckBox:
		return "checkbox"
	case binding.Control_Type_ComboBox:
		return "combobox"
	case binding.Control_Type_Edit:
		return "edit"
	case binding.Control_Type_Hyperlink:
		return "hyperlink"
	case binding.Control_Type_Image:
		return "image"
	case binding.Control_Type_ListItem:
		return "listitem"
	case binding.Control_Type_List:
		return "list"
	case binding.Control_Type_Menu:
		return "menu"
	case binding.Control_Type_MenuBar:
		return "menubar"
	case binding.Control_Type_MenuItem:
		return "menuitem"
	case binding.Control_Type_RadioButton:
		return "radiobutton"
	case binding.Control_Type_Tab:
		return "tab"
	case binding.Control_Type_TabItem:
		return "tabitem"
	case binding.Control_Type_Text:
		return "text"
	case binding.Control_Type_ToolBar:
		return "toolbar"
	case binding.Control_Type_Tree:
		return "tree"
	case binding.Control_Type_TreeItem:
		return "treeitem"
	case binding.Control_Type_Group:
		return "group"
	case binding.Control_Type_Document:
		return "document"
	case binding.Control_Type_Window:
		return "window"
	case binding.Control_Type_Pane:
		return "pane"
	}
	return "unknown"
}

// find_all returns every element under el that matches the given tree scope.
// It uses a true condition, so it matches all elements in scope. The caller
// releases the returned array with release_array.
find_all :: proc(a: ^Automation, el: ^Element, scope: i32) -> (Element_Array, Error) {
	condition, chr := binding.create_true_condition(a.ptr)
	if chr != 0 {
		return {}, .Element_Unavailable
	}
	defer binding.release_condition(condition)

	ptr, hr := binding.element_find_all(el.ptr, scope, condition)
	if hr != 0 {
		return {}, .Element_Unavailable
	}
	return Element_Array{ptr = ptr}, .None
}

// element_count returns the number of elements in the array.
element_count :: proc(arr: ^Element_Array) -> (i32, Error) {
	length, hr := binding.array_length(arr.ptr)
	if hr != 0 {
		return 0, .Element_Unavailable
	}
	return length, .None
}

// element_at returns the element at the given index in the array.
element_at :: proc(arr: ^Element_Array, index: i32) -> (Element, Error) {
	ptr, hr := binding.array_element(arr.ptr, index)
	if hr != 0 {
		return {}, .Element_Unavailable
	}
	return Element{ptr = ptr}, .None
}

// release_array releases an element array returned by find_all.
release_array :: proc(arr: ^Element_Array) {
	if arr.ptr != nil {
		binding.release_array(arr.ptr)
		arr.ptr = nil
	}
}

// first_child returns the first child of el in the control view, or ok=false
// when el has no children. The caller releases the child with release_element.
first_child :: proc(a: ^Automation, el: ^Element) -> (Element, bool) {
	child, hr := binding.walker_first_child(a.walker, el.ptr)
	if hr != 0 || child == nil {
		return {}, false
	}
	return Element{ptr = child}, true
}

// next_sibling returns the next sibling of el in the control view, or
// ok=false when el is the last sibling. The caller releases it.
next_sibling :: proc(a: ^Automation, el: ^Element) -> (Element, bool) {
	sibling, hr := binding.walker_next_sibling(a.walker, el.ptr)
	if hr != 0 || sibling == nil {
		return {}, false
	}
	return Element{ptr = sibling}, true
}

// invoke performs the element's default action without moving the cursor.
invoke :: proc(el: ^Element) -> Error {
	pattern, hr := binding.element_get_pattern(el.ptr, binding.Invoke_Pattern_Id)
	if hr != 0 || pattern == nil {
		return .Pattern_Not_Available
	}
	if binding.pattern_invoke(pattern) != 0 {
		return .Action_Failed
	}
	return .None
}

// set_value writes a string value into a value-settable element.
set_value :: proc(el: ^Element, value: string) -> Error {
	pattern, hr := binding.element_get_pattern(el.ptr, binding.Value_Pattern_Id)
	if hr != 0 || pattern == nil {
		return .Pattern_Not_Available
	}

	buf: [4096]u16
	wide := windows.utf8_to_wstring_buf(buf[:], value)
	if binding.pattern_set_value(pattern, wide) != 0 {
		return .Action_Failed
	}
	return .None
}

// scroll scrolls a scrollable element by the given amounts.
scroll :: proc(el: ^Element, horizontal: i32, vertical: i32) -> Error {
	pattern, hr := binding.element_get_pattern(el.ptr, binding.Scroll_Pattern_Id)
	if hr != 0 || pattern == nil {
		return .Pattern_Not_Available
	}
	if binding.pattern_scroll(pattern, horizontal, vertical) != 0 {
		return .Action_Failed
	}
	return .None
}

// select selects an item in a selection container.
select :: proc(el: ^Element) -> Error {
	pattern, hr := binding.element_get_pattern(el.ptr, binding.Selection_Item_Pattern_Id)
	if hr != 0 || pattern == nil {
		return .Pattern_Not_Available
	}
	if binding.pattern_select(pattern) != 0 {
		return .Action_Failed
	}
	return .None
}

// toggle cycles an element's toggle state.
toggle :: proc(el: ^Element) -> Error {
	pattern, hr := binding.element_get_pattern(el.ptr, binding.Toggle_Pattern_Id)
	if hr != 0 || pattern == nil {
		return .Pattern_Not_Available
	}
	if binding.pattern_toggle(pattern) != 0 {
		return .Action_Failed
	}
	return .None
}

// value returns an editable element's current value, or an empty string when
// the element has no value pattern.
value :: proc(el: ^Element, allocator := context.allocator) -> (string, Error) {
	bstr, hr := binding.element_current_value(el.ptr)
	if hr != 0 || bstr == nil {
		return "", .None
	}
	defer binding.free_bstr(bstr)

	length := bstr_length(bstr)
	if length == 0 {
		return "", .None
	}
	text, _ := windows.wstring_to_utf8_alloc(windows.wstring(bstr), length, allocator)
	return text, .None
}

// text reads up to max_length characters of the element's text content via
// the Text pattern. The caller deletes the returned string.
text :: proc(
	el: ^Element,
	max_length: i32 = 4096,
	allocator := context.allocator,
) -> (
	string,
	Error,
) {
	bstr, hr := binding.element_text(el.ptr, max_length)
	if hr != 0 || bstr == nil {
		return "", .Text_Unavailable
	}
	defer binding.free_bstr(bstr)

	length := bstr_length(bstr)
	if length == 0 {
		return "", .None
	}
	text, _ := windows.wstring_to_utf8_alloc(windows.wstring(bstr), length, allocator)
	return text, .None
}

// bstr_length counts the UTF-16 units in a null-terminated BSTR.
bstr_length :: proc(b: windows.BSTR) -> int {
	chars := ([^]u16)(b)
	length := 0
	for chars[length] != 0 {
		length += 1
	}
	return length
}
