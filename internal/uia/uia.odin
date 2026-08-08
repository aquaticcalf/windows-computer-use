package uia

import windows "core:sys/windows"

// Hand-written UI Automation COM bindings. See issue #8 and ARCHITECTURE.md
// (Perception). The vtables must match the exact method order from
// uiautomationclient.h; extend in order as more of the API is used.

IUnknownVtbl :: struct {
	QueryInterface: proc "system" (
		This: rawptr,
		riid: windows.REFIID,
		ppv: ^rawptr,
	) -> windows.HRESULT,
	AddRef:         proc "system" (This: rawptr) -> windows.ULONG,
	Release:        proc "system" (This: rawptr) -> windows.ULONG,
}

IUIAutomationElement :: struct {
	using _: ^IUnknownVtbl,
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

IUIAutomationVtbl :: struct {
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
IUIAutomation :: struct {
	using _: ^IUIAutomationVtbl,
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
IID_IUIAutomationElement := windows.IID {
	0xD22108AA,
	0x8AC5,
	0x49A5,
	{0x83, 0x7B, 0x37, 0xBB, 0xBB, 0x3D, 0x75, 0x91},
}

Automation :: struct {
	ptr: ^IUIAutomation,
}

create :: proc() -> (Automation, windows.HRESULT) {
	ppv: windows.LPVOID
	hr := windows.CoCreateInstance(
		&CLSID_CUIAutomation,
		nil,
		windows.CLSCTX_INPROC_SERVER,
		&IID_IUIAutomation,
		&ppv,
	)
	if hr != 0 {
		return Automation{}, hr
	}
	return Automation{ptr = (^IUIAutomation)(ppv)}, 0
}

destroy :: proc(a: ^Automation) {
	if a.ptr != nil {
		a.ptr->Release()
		a.ptr = nil
	}
}

element_from_handle :: proc(
	a: ^Automation,
	hwnd: windows.HWND,
) -> (
	^IUIAutomationElement,
	windows.HRESULT,
) {
	el: ^IUIAutomationElement
	hr := a.ptr->ElementFromHandle(hwnd, &el)
	return el, hr
}

root_element :: proc(a: ^Automation) -> (^IUIAutomationElement, windows.HRESULT) {
	root: ^IUIAutomationElement
	hr := a.ptr->GetRootElement(&root)
	return root, hr
}
