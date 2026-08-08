package binding

import "core:sys/windows"

// Raw UI Automation COM bindings. This is a leaf: it exists only to keep the
// COM surface here and out of the rest of the codebase. See DESIGN.md
// (dependency classes: true external, keep behind an adapter) and
// ARCHITECTURE.md (Perception). Vtables must match the exact method order
// from uiautomationclient.h.

foreign import oleaut32 "system:OleAut32.lib"

@(default_calling_convention = "system")
foreign oleaut32 {
	SysFreeString :: proc(bstr: windows.BSTR) ---
}

IUnknownVtbl :: struct {
	QueryInterface: proc "system" (
		This: rawptr,
		riid: windows.REFIID,
		ppv: ^rawptr,
	) -> windows.HRESULT,
	AddRef:         proc "system" (This: rawptr) -> windows.ULONG,
	Release:        proc "system" (This: rawptr) -> windows.ULONG,
}

IUIAutomationCondition :: struct {
	using _: ^IUnknownVtbl,
}
IUIAutomationTreeWalker :: struct {
	using _: ^IUnknownVtbl,
}
IUIAutomationElementArray :: struct {
	using _: ^IUnknownVtbl,
}

IUIAutomationElement :: struct {
	using _: ^IUIAutomationElement_Vtbl,
}

IUIAutomationElement_Vtbl :: struct {
	using _:                        IUnknownVtbl,
	SetFocus:                       proc "system" (This: rawptr) -> windows.HRESULT,
	GetRuntimeId:                   proc "system" (
		This: rawptr,
		runtime_id: ^rawptr,
	) -> windows.HRESULT,
	FindFirst:                      proc "system" (
		This: rawptr,
		scope: i32,
		condition: ^IUIAutomationCondition,
		found: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	FindAll:                        proc "system" (
		This: rawptr,
		scope: i32,
		condition: ^IUIAutomationCondition,
		found: ^^IUIAutomationElementArray,
	) -> windows.HRESULT,
	FindFirstBuildCache:            proc "system" (
		This: rawptr,
		scope: i32,
		condition: ^IUIAutomationCondition,
		cache: rawptr,
		found: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	FindAllBuildCache:              proc "system" (
		This: rawptr,
		scope: i32,
		condition: ^IUIAutomationCondition,
		cache: rawptr,
		found: ^^IUIAutomationElementArray,
	) -> windows.HRESULT,
	BuildUpdatedCache:              proc "system" (
		This: rawptr,
		cache: rawptr,
		updated: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	GetCurrentPropertyValue:        proc "system" (
		This: rawptr,
		prop: i32,
		value: rawptr,
	) -> windows.HRESULT,
	GetCurrentPropertyValueEx:      proc "system" (
		This: rawptr,
		prop: i32,
		ignore: windows.BOOL,
		value: rawptr,
	) -> windows.HRESULT,
	GetCachedPropertyValue:         proc "system" (
		This: rawptr,
		prop: i32,
		value: rawptr,
	) -> windows.HRESULT,
	GetCachedPropertyValueEx:       proc "system" (
		This: rawptr,
		prop: i32,
		ignore: windows.BOOL,
		value: rawptr,
	) -> windows.HRESULT,
	GetCurrentPatternAs:            proc "system" (
		This: rawptr,
		pattern: i32,
		riid: windows.REFIID,
		object: ^rawptr,
	) -> windows.HRESULT,
	GetCachedPatternAs:             proc "system" (
		This: rawptr,
		pattern: i32,
		riid: windows.REFIID,
		object: ^rawptr,
	) -> windows.HRESULT,
	GetCurrentPattern:              proc "system" (
		This: rawptr,
		pattern: i32,
		object: ^rawptr,
	) -> windows.HRESULT,
	GetCachedPattern:               proc "system" (
		This: rawptr,
		pattern: i32,
		object: ^rawptr,
	) -> windows.HRESULT,
	GetCachedParent:                proc "system" (
		This: rawptr,
		parent: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	GetCachedChildren:              proc "system" (
		This: rawptr,
		children: ^^IUIAutomationElementArray,
	) -> windows.HRESULT,
	GetCurrentProcessId:            proc "system" (This: rawptr, pid: ^i32) -> windows.HRESULT,
	GetCurrentControlType:          proc "system" (
		This: rawptr,
		control_type: ^i32,
	) -> windows.HRESULT,
	GetCurrentLocalizedControlType: proc "system" (
		This: rawptr,
		name: ^windows.BSTR,
	) -> windows.HRESULT,
	GetCurrentName:                 proc "system" (
		This: rawptr,
		name: ^windows.BSTR,
	) -> windows.HRESULT,
}

IUIAutomation :: struct {
	using _: ^IUIAutomation_Vtbl,
}

IUIAutomation_Vtbl :: struct {
	using _:                     IUnknownVtbl,
	CompareElements:             proc "system" (
		This: rawptr,
		e1: ^IUIAutomationElement,
		e2: ^IUIAutomationElement,
		same: ^windows.BOOL,
	) -> windows.HRESULT,
	CompareRuntimeIds:           proc "system" (
		This: rawptr,
		r1: rawptr,
		r2: rawptr,
		same: ^windows.BOOL,
	) -> windows.HRESULT,
	GetRootElement:              proc "system" (
		This: rawptr,
		root: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	ElementFromHandle:           proc "system" (
		This: rawptr,
		hwnd: windows.HWND,
		el: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	ElementFromPoint:            proc "system" (
		This: rawptr,
		pt: windows.POINT,
		el: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	GetFocusedElement:           proc "system" (
		This: rawptr,
		el: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	GetRootElementBuildCache:    proc "system" (
		This: rawptr,
		cache: rawptr,
		root: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	ElementFromHandleBuildCache: proc "system" (
		This: rawptr,
		hwnd: windows.HWND,
		cache: rawptr,
		el: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	ElementFromPointBuildCache:  proc "system" (
		This: rawptr,
		pt: windows.POINT,
		cache: rawptr,
		el: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	GetFocusedElementBuildCache: proc "system" (
		This: rawptr,
		cache: rawptr,
		el: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	CreateTreeWalker:            proc "system" (
		This: rawptr,
		condition: ^IUIAutomationCondition,
		walker: ^^IUIAutomationTreeWalker,
	) -> windows.HRESULT,
	GetControlViewWalker:        proc "system" (
		This: rawptr,
		walker: ^^IUIAutomationTreeWalker,
	) -> windows.HRESULT,
	GetContentViewWalker:        proc "system" (
		This: rawptr,
		walker: ^^IUIAutomationTreeWalker,
	) -> windows.HRESULT,
	GetRawViewWalker:            proc "system" (
		This: rawptr,
		walker: ^^IUIAutomationTreeWalker,
	) -> windows.HRESULT,
}

CLSID_CUIAutomation := windows.CLSID {
	0xFF48DBA4,
	0x60EF,
	0x4201,
	{0xAA, 0x87, 0x54, 0x10, 0x3E, 0xEF, 0x59, 0x4E},
}
IID_IUIAutomation := windows.IID {
	0x30CBE57D,
	0xD9D0,
	0x452A,
	{0xAB, 0x13, 0x7A, 0xC5, 0xAC, 0x48, 0x25, 0xEE},
}

create_automation :: proc() -> (^IUIAutomation, i32) {
	ppv: windows.LPVOID
	hr := windows.CoCreateInstance(
		&CLSID_CUIAutomation,
		nil,
		windows.CLSCTX_INPROC_SERVER,
		&IID_IUIAutomation,
		&ppv,
	)
	if hr != 0 {
		return nil, i32(hr)
	}
	return (^IUIAutomation)(ppv), 0
}

release_automation :: proc(a: ^IUIAutomation) {
	a->Release()
}

get_root_element :: proc(a: ^IUIAutomation) -> (^IUIAutomationElement, i32) {
	root: ^IUIAutomationElement
	hr := a->GetRootElement(&root)
	return root, i32(hr)
}

element_from_handle :: proc(
	a: ^IUIAutomation,
	hwnd: windows.HWND,
) -> (
	^IUIAutomationElement,
	i32,
) {
	el: ^IUIAutomationElement
	hr := a->ElementFromHandle(hwnd, &el)
	return el, i32(hr)
}

release_element :: proc(el: ^IUIAutomationElement) {
	el->Release()
}

element_name :: proc(el: ^IUIAutomationElement) -> (windows.BSTR, i32) {
	name: windows.BSTR
	hr := el->GetCurrentName(&name)
	return name, i32(hr)
}

free_bstr :: proc(bstr: windows.BSTR) {
	SysFreeString(bstr)
}
