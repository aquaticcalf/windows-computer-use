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

Automation :: struct {
	ptr: ^binding.IUIAutomation,
}

Element :: struct {
	ptr: ^binding.IUIAutomationElement,
}

create :: proc() -> (Automation, Error) {
	ptr, hr := binding.create_automation()
	if hr != 0 {
		return {}, .Create_Failed
	}
	return Automation{ptr = ptr}, .None
}

destroy :: proc(a: ^Automation) {
	if a.ptr != nil {
		binding.release_automation(a.ptr)
		a.ptr = nil
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

bstr_length :: proc(b: windows.BSTR) -> int {
	chars := ([^]u16)(b)
	length := 0
	for chars[length] != 0 {
		length += 1
	}
	return length
}
