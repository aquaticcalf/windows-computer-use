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
	// SysFreeString releases a BSTR allocated by COM.
	SysFreeString :: proc(bstr: windows.BSTR) ---
}

// Property and control type ids used by conditions and property reads.
Name_Property_Id :: 30005
Control_Type_Property_Id :: 30003
Automation_Id_Property_Id :: 30011

// TreeScope values.
Tree_Scope_Element :: 0x1
Tree_Scope_Children :: 0x2
Tree_Scope_Descendants :: 0x4

// Common UIA ControlType ids (for surfacing a human-readable role).
Control_Type_Button :: 50000
Control_Type_CheckBox :: 50002
Control_Type_ComboBox :: 50003
Control_Type_Edit :: 50004
Control_Type_Hyperlink :: 50005
Control_Type_Image :: 50006
Control_Type_ListItem :: 50007
Control_Type_List :: 50008
Control_Type_Menu :: 50009
Control_Type_MenuBar :: 50010
Control_Type_MenuItem :: 50011
Control_Type_RadioButton :: 50013
Control_Type_ScrollBar :: 50014
Control_Type_Tab :: 50018
Control_Type_TabItem :: 50019
Control_Type_Text :: 50020
Control_Type_ToolBar :: 50021
Control_Type_Tree :: 50023
Control_Type_TreeItem :: 50024
Control_Type_Group :: 50026
Control_Type_Document :: 50030
Control_Type_Window :: 50032
Control_Type_Pane :: 50033

// Placeholder for the 16-byte VARIANT passed to property conditions. We only
// need the slot size to keep the vtable aligned; we do not build variants yet.
Variant :: struct {
	data: [16]u8,
}

// IUnknownVtbl is the base COM vtable: QueryInterface, AddRef, Release.
IUnknownVtbl :: struct {
	QueryInterface: proc "system" (
		This: rawptr,
		riid: windows.REFIID,
		ppv: ^rawptr,
	) -> windows.HRESULT,
	AddRef:         proc "system" (This: rawptr) -> windows.ULONG,
	Release:        proc "system" (This: rawptr) -> windows.ULONG,
}

// IUIAutomationCondition is an opaque condition object used in queries.
IUIAutomationCondition :: struct {
	using _: ^IUnknownVtbl,
}
// IUIAutomationCacheRequest is an opaque cache request object.
IUIAutomationCacheRequest :: struct {
	using _: ^IUnknownVtbl,
}

// IUIAutomationElement is a handle to a UI element.
IUIAutomationElement :: struct {
	using _: ^IUIAutomationElement_Vtbl,
}

// IUIAutomationElement_Vtbl matches the IUIAutomationElement vtable from
// uiautomationclient.h. Keep the method order exact.
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
	GetCurrentAcceleratorKey:       proc "system" (
		This: rawptr,
		value: ^windows.BSTR,
	) -> windows.HRESULT,
	GetCurrentAccessKey:            proc "system" (
		This: rawptr,
		value: ^windows.BSTR,
	) -> windows.HRESULT,
	GetCurrentHasKeyboardFocus:     proc "system" (
		This: rawptr,
		value: ^windows.BOOL,
	) -> windows.HRESULT,
	GetCurrentIsKeyboardFocusable:  proc "system" (
		This: rawptr,
		value: ^windows.BOOL,
	) -> windows.HRESULT,
	GetCurrentIsEnabled:            proc "system" (
		This: rawptr,
		value: ^windows.BOOL,
	) -> windows.HRESULT,
	GetCurrentAutomationId:         proc "system" (
		This: rawptr,
		value: ^windows.BSTR,
	) -> windows.HRESULT,
	GetCurrentClassName:            proc "system" (
		This: rawptr,
		value: ^windows.BSTR,
	) -> windows.HRESULT,
	GetCurrentHelpText:             proc "system" (
		This: rawptr,
		value: ^windows.BSTR,
	) -> windows.HRESULT,
	GetCurrentCulture:              proc "system" (This: rawptr, value: ^i32) -> windows.HRESULT,
	GetCurrentIsControlElement:     proc "system" (
		This: rawptr,
		value: ^windows.BOOL,
	) -> windows.HRESULT,
	GetCurrentIsContentElement:     proc "system" (
		This: rawptr,
		value: ^windows.BOOL,
	) -> windows.HRESULT,
	GetCurrentIsPassword:           proc "system" (
		This: rawptr,
		value: ^windows.BOOL,
	) -> windows.HRESULT,
	GetCurrentNativeWindowHandle:   proc "system" (
		This: rawptr,
		value: ^rawptr,
	) -> windows.HRESULT,
	GetCurrentItemType:             proc "system" (
		This: rawptr,
		value: ^windows.BSTR,
	) -> windows.HRESULT,
	GetCurrentIsOffscreen:          proc "system" (
		This: rawptr,
		value: ^windows.BOOL,
	) -> windows.HRESULT,
	GetCurrentOrientation:          proc "system" (This: rawptr, value: ^i32) -> windows.HRESULT,
	GetCurrentFrameworkId:          proc "system" (
		This: rawptr,
		value: ^windows.BSTR,
	) -> windows.HRESULT,
	GetCurrentIsRequiredForForm:    proc "system" (
		This: rawptr,
		value: ^windows.BOOL,
	) -> windows.HRESULT,
	GetCurrentItemStatus:           proc "system" (
		This: rawptr,
		value: ^windows.BSTR,
	) -> windows.HRESULT,
	GetCurrentBoundingRectangle:    proc "system" (
		This: rawptr,
		rect: ^windows.RECT,
	) -> windows.HRESULT,
}

// IUIAutomationElementArray is a collection of elements returned by FindAll.
IUIAutomationElementArray :: struct {
	using _: ^IUIAutomationElementArray_Vtbl,
}

// IUIAutomationElementArray_Vtbl matches the element array vtable.
IUIAutomationElementArray_Vtbl :: struct {
	using _:    IUnknownVtbl,
	Length:     proc "system" (This: rawptr, length: ^i32) -> windows.HRESULT,
	GetElement: proc "system" (
		This: rawptr,
		index: i32,
		element: ^^IUIAutomationElement,
	) -> windows.HRESULT,
}

// IUIAutomationTreeWalker walks the accessibility tree in a given view.
IUIAutomationTreeWalker :: struct {
	using _: ^IUIAutomationTreeWalker_Vtbl,
}

// IUIAutomationTreeWalker_Vtbl matches the tree walker vtable.
IUIAutomationTreeWalker_Vtbl :: struct {
	using _:                   IUnknownVtbl,
	GetParentElement:          proc "system" (
		This: rawptr,
		element: ^IUIAutomationElement,
		parent: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	GetFirstChildElement:      proc "system" (
		This: rawptr,
		element: ^IUIAutomationElement,
		child: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	GetLastChildElement:       proc "system" (
		This: rawptr,
		element: ^IUIAutomationElement,
		child: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	GetNextSiblingElement:     proc "system" (
		This: rawptr,
		element: ^IUIAutomationElement,
		sibling: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	GetPreviousSiblingElement: proc "system" (
		This: rawptr,
		element: ^IUIAutomationElement,
		sibling: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	NormalizeElement:          proc "system" (
		This: rawptr,
		element: ^IUIAutomationElement,
		normalized: ^^IUIAutomationElement,
	) -> windows.HRESULT,
}

// IUIAutomation is the root automation object.
IUIAutomation :: struct {
	using _: ^IUIAutomation_Vtbl,
}

// IUIAutomation_Vtbl matches the IUIAutomation vtable from uiautomationclient.h.
IUIAutomation_Vtbl :: struct {
	using _:                           IUnknownVtbl,
	CompareElements:                   proc "system" (
		This: rawptr,
		e1: ^IUIAutomationElement,
		e2: ^IUIAutomationElement,
		same: ^windows.BOOL,
	) -> windows.HRESULT,
	CompareRuntimeIds:                 proc "system" (
		This: rawptr,
		r1: rawptr,
		r2: rawptr,
		same: ^windows.BOOL,
	) -> windows.HRESULT,
	GetRootElement:                    proc "system" (
		This: rawptr,
		root: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	ElementFromHandle:                 proc "system" (
		This: rawptr,
		hwnd: windows.HWND,
		el: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	ElementFromPoint:                  proc "system" (
		This: rawptr,
		pt: windows.POINT,
		el: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	GetFocusedElement:                 proc "system" (
		This: rawptr,
		el: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	GetRootElementBuildCache:          proc "system" (
		This: rawptr,
		cache: rawptr,
		root: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	ElementFromHandleBuildCache:       proc "system" (
		This: rawptr,
		hwnd: windows.HWND,
		cache: rawptr,
		el: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	ElementFromPointBuildCache:        proc "system" (
		This: rawptr,
		pt: windows.POINT,
		cache: rawptr,
		el: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	GetFocusedElementBuildCache:       proc "system" (
		This: rawptr,
		cache: rawptr,
		el: ^^IUIAutomationElement,
	) -> windows.HRESULT,
	CreateTreeWalker:                  proc "system" (
		This: rawptr,
		condition: ^IUIAutomationCondition,
		walker: ^^IUIAutomationTreeWalker,
	) -> windows.HRESULT,
	GetControlViewWalker:              proc "system" (
		This: rawptr,
		walker: ^^IUIAutomationTreeWalker,
	) -> windows.HRESULT,
	GetContentViewWalker:              proc "system" (
		This: rawptr,
		walker: ^^IUIAutomationTreeWalker,
	) -> windows.HRESULT,
	GetRawViewWalker:                  proc "system" (
		This: rawptr,
		walker: ^^IUIAutomationTreeWalker,
	) -> windows.HRESULT,
	GetRawViewCondition:               proc "system" (
		This: rawptr,
		condition: ^^IUIAutomationCondition,
	) -> windows.HRESULT,
	GetControlViewCondition:           proc "system" (
		This: rawptr,
		condition: ^^IUIAutomationCondition,
	) -> windows.HRESULT,
	GetContentViewCondition:           proc "system" (
		This: rawptr,
		condition: ^^IUIAutomationCondition,
	) -> windows.HRESULT,
	CreateCacheRequest:                proc "system" (
		This: rawptr,
		request: ^^IUIAutomationCacheRequest,
	) -> windows.HRESULT,
	CreateTrueCondition:               proc "system" (
		This: rawptr,
		condition: ^^IUIAutomationCondition,
	) -> windows.HRESULT,
	CreateFalseCondition:              proc "system" (
		This: rawptr,
		condition: ^^IUIAutomationCondition,
	) -> windows.HRESULT,
	CreatePropertyCondition:           proc "system" (
		This: rawptr,
		prop: i32,
		value: Variant,
		condition: ^^IUIAutomationCondition,
	) -> windows.HRESULT,
	CreatePropertyConditionEx:         proc "system" (
		This: rawptr,
		prop: i32,
		value: Variant,
		flags: i32,
		condition: ^^IUIAutomationCondition,
	) -> windows.HRESULT,
	CreateAndCondition:                proc "system" (
		This: rawptr,
		c1: ^IUIAutomationCondition,
		c2: ^IUIAutomationCondition,
		condition: ^^IUIAutomationCondition,
	) -> windows.HRESULT,
	CreateAndConditionFromArray:       proc "system" (
		This: rawptr,
		conditions: rawptr,
		condition: ^^IUIAutomationCondition,
	) -> windows.HRESULT,
	CreateAndConditionFromNativeArray: proc "system" (
		This: rawptr,
		conditions: [^]^IUIAutomationCondition,
		count: i32,
		condition: ^^IUIAutomationCondition,
	) -> windows.HRESULT,
	CreateOrCondition:                 proc "system" (
		This: rawptr,
		c1: ^IUIAutomationCondition,
		c2: ^IUIAutomationCondition,
		condition: ^^IUIAutomationCondition,
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

// create_automation creates the CUIAutomation COM object.
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

// release_automation releases an automation object.
release_automation :: proc(a: ^IUIAutomation) {
	a->Release()
}

// get_root_element returns the element for the entire desktop.
get_root_element :: proc(a: ^IUIAutomation) -> (^IUIAutomationElement, i32) {
	root: ^IUIAutomationElement
	hr := a->GetRootElement(&root)
	return root, i32(hr)
}

// element_from_handle resolves the element that owns a window handle.
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

// release_element releases an element.
release_element :: proc(el: ^IUIAutomationElement) {
	el->Release()
}

// element_find_all collects every element matching the condition in scope.
element_find_all :: proc(
	el: ^IUIAutomationElement,
	scope: i32,
	condition: ^IUIAutomationCondition,
) -> (
	^IUIAutomationElementArray,
	i32,
) {
	arr: ^IUIAutomationElementArray
	hr := el->FindAll(scope, condition, &arr)
	return arr, i32(hr)
}

// element_name reads the element's current name as a BSTR.
element_name :: proc(el: ^IUIAutomationElement) -> (windows.BSTR, i32) {
	name: windows.BSTR
	hr := el->GetCurrentName(&name)
	return name, i32(hr)
}

// element_control_type reads the element's UIA control type id.
element_control_type :: proc(el: ^IUIAutomationElement) -> (i32, i32) {
	control_type: i32
	hr := el->GetCurrentControlType(&control_type)
	return control_type, i32(hr)
}

// element_is_enabled reports whether the element accepts input.
element_is_enabled :: proc(el: ^IUIAutomationElement) -> (bool, i32) {
	enabled: windows.BOOL
	hr := el->GetCurrentIsEnabled(&enabled)
	return bool(enabled), i32(hr)
}

// element_bounding_rect reads the element's on-screen rectangle.
element_bounding_rect :: proc(el: ^IUIAutomationElement) -> (windows.RECT, i32) {
	rect: windows.RECT
	hr := el->GetCurrentBoundingRectangle(&rect)
	return rect, i32(hr)
}

// free_bstr releases a BSTR returned by this package.
free_bstr :: proc(bstr: windows.BSTR) {
	SysFreeString(bstr)
}

// array_length returns the number of elements in an array.
array_length :: proc(arr: ^IUIAutomationElementArray) -> (i32, i32) {
	length: i32
	hr := arr->Length(&length)
	return length, i32(hr)
}

// array_element returns the element at the given index in an array.
array_element :: proc(
	arr: ^IUIAutomationElementArray,
	index: i32,
) -> (
	^IUIAutomationElement,
	i32,
) {
	el: ^IUIAutomationElement
	hr := arr->GetElement(index, &el)
	return el, i32(hr)
}

// release_array releases an element array.
release_array :: proc(arr: ^IUIAutomationElementArray) {
	arr->Release()
}

// get_control_view_walker returns the control-view tree walker.
get_control_view_walker :: proc(a: ^IUIAutomation) -> (^IUIAutomationTreeWalker, i32) {
	walker: ^IUIAutomationTreeWalker
	hr := a->GetControlViewWalker(&walker)
	return walker, i32(hr)
}

// release_walker releases a tree walker.
release_walker :: proc(walker: ^IUIAutomationTreeWalker) {
	walker->Release()
}

// walker_first_child returns the first child of an element.
walker_first_child :: proc(
	walker: ^IUIAutomationTreeWalker,
	el: ^IUIAutomationElement,
) -> (
	^IUIAutomationElement,
	i32,
) {
	child: ^IUIAutomationElement
	hr := walker->GetFirstChildElement(el, &child)
	return child, i32(hr)
}

// walker_next_sibling returns the next sibling of an element.
walker_next_sibling :: proc(
	walker: ^IUIAutomationTreeWalker,
	el: ^IUIAutomationElement,
) -> (
	^IUIAutomationElement,
	i32,
) {
	sibling: ^IUIAutomationElement
	hr := walker->GetNextSiblingElement(el, &sibling)
	return sibling, i32(hr)
}

// create_true_condition builds a condition that matches every element.
create_true_condition :: proc(a: ^IUIAutomation) -> (^IUIAutomationCondition, i32) {
	condition: ^IUIAutomationCondition
	hr := a->CreateTrueCondition(&condition)
	return condition, i32(hr)
}

// release_condition releases a condition object.
release_condition :: proc(condition: ^IUIAutomationCondition) {
	condition->Release()
}
