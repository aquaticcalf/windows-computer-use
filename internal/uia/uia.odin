package uia

import "binding"
import windows "core:sys/windows"

// The public surface of the UI Automation adapter. Callers and tests only
// ever see these types; the raw COM interfaces live in the "binding" leaf.
// See DESIGN.md (deep modules, dependency classes).

Error :: enum {
	None,
	Create_Failed,
	Element_Unavailable,
	Name_Unavailable,
}

Tree_Scope_Element :: binding.Tree_Scope_Element
Tree_Scope_Children :: binding.Tree_Scope_Children
Tree_Scope_Descendants :: binding.Tree_Scope_Descendants

Rect :: struct {
	left, top, right, bottom: i32,
}

Automation :: struct {
	ptr:    ^binding.IUIAutomation,
	walker: ^binding.IUIAutomationTreeWalker,
}

Element :: struct {
	ptr: ^binding.IUIAutomationElement,
}

Element_Array :: struct {
	ptr: ^binding.IUIAutomationElementArray,
}

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

destroy :: proc(a: ^Automation) {
	if a.ptr != nil {
		binding.release_walker(a.walker)
		binding.release_automation(a.ptr)
		a.ptr = nil
		a.walker = nil
	}
}

element_from_handle :: proc(a: ^Automation, hwnd: windows.HWND) -> (Element, Error) {
	ptr, hr := binding.element_from_handle(a.ptr, hwnd)
	if hr != 0 {
		return {}, .Element_Unavailable
	}
	return Element{ptr = ptr}, .None
}

root_element :: proc(a: ^Automation) -> (Element, Error) {
	ptr, hr := binding.get_root_element(a.ptr)
	if hr != 0 {
		return {}, .Element_Unavailable
	}
	return Element{ptr = ptr}, .None
}

release_element :: proc(el: ^Element) {
	if el.ptr != nil {
		binding.release_element(el.ptr)
		el.ptr = nil
	}
}

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

control_type :: proc(el: ^Element) -> (i32, Error) {
	id, hr := binding.element_control_type(el.ptr)
	if hr != 0 {
		return 0, .Element_Unavailable
	}
	return id, .None
}

is_enabled :: proc(el: ^Element) -> (bool, Error) {
	enabled, hr := binding.element_is_enabled(el.ptr)
	if hr != 0 {
		return false, .Element_Unavailable
	}
	return enabled, .None
}

bounding_rect :: proc(el: ^Element) -> (Rect, Error) {
	r, hr := binding.element_bounding_rect(el.ptr)
	if hr != 0 {
		return {}, .Element_Unavailable
	}
	return Rect{left = r.left, top = r.top, right = r.right, bottom = r.bottom}, .None
}

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

element_count :: proc(arr: ^Element_Array) -> (i32, Error) {
	length, hr := binding.array_length(arr.ptr)
	if hr != 0 {
		return 0, .Element_Unavailable
	}
	return length, .None
}

element_at :: proc(arr: ^Element_Array, index: i32) -> (Element, Error) {
	ptr, hr := binding.array_element(arr.ptr, index)
	if hr != 0 {
		return {}, .Element_Unavailable
	}
	return Element{ptr = ptr}, .None
}

release_array :: proc(arr: ^Element_Array) {
	if arr.ptr != nil {
		binding.release_array(arr.ptr)
		arr.ptr = nil
	}
}

first_child :: proc(a: ^Automation, el: ^Element) -> (Element, bool) {
	child, hr := binding.walker_first_child(a.walker, el.ptr)
	if hr != 0 || child == nil {
		return {}, false
	}
	return Element{ptr = child}, true
}

next_sibling :: proc(a: ^Automation, el: ^Element) -> (Element, bool) {
	sibling, hr := binding.walker_next_sibling(a.walker, el.ptr)
	if hr != 0 || sibling == nil {
		return {}, false
	}
	return Element{ptr = sibling}, true
}

bstr_length :: proc(b: windows.BSTR) -> int {
	chars := ([^]u16)(b)
	length := 0
	for chars[length] != 0 {
		length += 1
	}
	return length
}
