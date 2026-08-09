package perception

import "../uia"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:sys/windows"

// The perception module turns a window handle into a rendered, token-cheap
// text tree for an agent. It hides the UIA walking, property reads, and
// rendering behind one small surface. See DESIGN.md and ARCHITECTURE.md
// (Perception).

// Error is this package's error type.
Error :: enum {
	// None reports a successful call.
	None,
	// Create_Failed reports that the perception session could not be created.
	Create_Failed,
	// Element_Unavailable reports that no element could be resolved.
	Element_Unavailable,
	// Text_Unavailable reports that element text content could not be read.
	Text_Unavailable,
	// Walk_Failed reports that the accessibility tree could not be walked.
	Walk_Failed,
	// Index_Out_Of_Range reports that no element exists at the requested index.
	Index_Out_Of_Range,
}

// Limits bounds the cost of a snapshot: node count, tree depth, and per-text
// truncation length.
Limits :: struct {
	max_nodes:  int,
	max_depth:  int,
	text_limit: int,
}

// default_limits returns the limits used unless a caller overrides them.
default_limits :: proc() -> Limits {
	return Limits{max_nodes = 1200, max_depth = 64, text_limit = 500}
}

// Session holds a live UI Automation connection used for perception.
Session :: struct {
	auto: uia.Automation,
}

// open creates a perception session, initializing COM. Call close when done.
open :: proc() -> (Session, Error) {
	windows.CoInitialize(nil)
	auto, err := uia.create()
	if err != .None {
		return {}, .Create_Failed
	}
	return Session{auto = auto}, .None
}

// close releases a perception session and uninitializes COM.
close :: proc(s: ^Session) {
	uia.destroy(&s.auto)
	windows.CoUninitialize()
}

// Node is one element in a rendered tree.
Node :: struct {
	index:   int,
	depth:   int,
	role:    string,
	name:    string,
	value:   string,
	rect:    uia.Rect,
	enabled: bool,
}

// destroy_nodes frees a node list returned by walk, including its strings.
destroy_nodes :: proc(nodes: []Node, allocator := context.allocator) {
	for n in nodes {
		delete(n.name, allocator)
		delete(n.value, allocator)
	}
	delete(nodes, allocator)
}

// walk collects the control-view subtree of root into node records. The
// caller owns the result and frees it with destroy_nodes.
walk :: proc(
	s: ^Session,
	root: ^uia.Element,
	limits: Limits,
	allocator := context.allocator,
) -> (
	result: []Node,
	err: Error,
) {
	built, berr := make([dynamic]Node, 0, 128, allocator)
	if berr != nil {
		return nil, .Walk_Failed
	}
	ctx := walk_context {
		built     = &built,
		count     = 0,
		allocator = allocator,
	}
	traverse(s, root, 0, limits, walk_visit, &ctx)
	result = built[:]
	return result, .None
}

// walk_context carries the state walk needs while traversing the tree. It
// embeds traverse_state so traverse can read the shared node counter.
walk_context :: struct {
	using _:   traverse_state,
	built:     ^[dynamic]Node,
	allocator: mem.Allocator,
}

// walk_visit emits one node record for the element being visited and advances
// the walk's counter.
walk_visit :: proc(el: ^uia.Element, depth: int, data: rawptr) -> bool {
	ctx := (^walk_context)(data)

	name, _ := uia.name(el, ctx.allocator)
	role_id, _ := uia.control_type(el)
	role := uia.control_type_name(role_id)
	rect, _ := uia.bounding_rect(el)
	enabled, _ := uia.is_enabled(el)

	value := ""
	if role == "edit" || role == "combobox" {
		value, _ = uia.value(el, ctx.allocator)
	}

	append(
		ctx.built,
		Node {
			index = ctx.count,
			depth = depth,
			role = role,
			name = name,
			value = value,
			rect = rect,
			enabled = enabled,
		},
	)
	ctx.count += 1
	return true
}

// visit_fn is called for each element in walk order. Return false to stop the
// traversal early. data is the caller-supplied context pointer.
visit_fn :: #type proc(el: ^uia.Element, depth: int, data: rawptr) -> bool

// traverse_state is the shared part of every traversal context: the node
// counter that limits walk and element_at_index to max_nodes.
traverse_state :: struct {
	count: int,
}

// traverse walks the control-view subtree of el in walk order (node, then its
// first child's subtree, then each remaining sibling's subtree), calling visit
// for every element. Shared by walk and element_at_index so both agree on the
// exact ordering of indices. Returns false only when visit stopped it.
traverse :: proc(
	s: ^Session,
	el: ^uia.Element,
	depth: int,
	limits: Limits,
	visit: visit_fn,
	data: rawptr,
) -> bool {
	state := (^traverse_state)(data)
	if state.count >= limits.max_nodes || depth > limits.max_depth {
		return true
	}
	if !visit(el, depth, data) {
		return false
	}

	child, ok := uia.first_child(&s.auto, el)
	if !ok {
		return true
	}
	defer uia.release_element(&child)
	if !traverse(s, &child, depth + 1, limits, visit, data) {
		return false
	}

	// Walk siblings by advancing the reference; each next_sibling returns the
	// sibling of the element passed to it.
	sibling, sok := uia.next_sibling(&s.auto, &child)
	for sok {
		if !traverse(s, &sibling, depth + 1, limits, visit, data) {
			uia.release_element(&sibling)
			return false
		}
		next, nok := uia.next_sibling(&s.auto, &sibling)
		uia.release_element(&sibling)
		sibling, sok = next, nok
	}
	return true
}

// element_at_index returns the element at the given walk index. The returned
// element carries an extra reference; the caller releases it with
// uia.release_element. Errors with .Index_Out_Of_Range when no such index
// exists under the limits.
element_at_index :: proc(
	s: ^Session,
	root: ^uia.Element,
	index: int,
	limits: Limits,
) -> (
	uia.Element,
	Error,
) {
	ctx := find_context {
		target = index,
		count  = 0,
	}
	traverse(s, root, 0, limits, find_visit, &ctx)
	if !ctx.found {
		return {}, .Index_Out_Of_Range
	}
	return ctx.result, .None
}

// find_context carries the search state for element_at_index. It embeds
// traverse_state so traverse can read the shared node counter.
find_context :: struct {
	using _: traverse_state,
	target:  int,
	found:   bool,
	result:  uia.Element,
}

// find_visit returns the element whose walk index matches the target.
find_visit :: proc(el: ^uia.Element, depth: int, data: rawptr) -> bool {
	ctx := (^find_context)(data)
	if ctx.count == ctx.target {
		ctx.result = uia.retain_element(el^)
		ctx.found = true
		return false
	}
	ctx.count += 1
	return true
}

// element_by_name returns the first element whose accessible name contains
// the given substring (case-insensitive, ASCII). The returned element carries
// an extra reference; the caller releases it with uia.release_element. Errors
// with .Element_Unavailable when nothing matches.
element_by_name :: proc(
	s: ^Session,
	root: ^uia.Element,
	substring: string,
	limits: Limits,
	allocator := context.allocator,
) -> (
	uia.Element,
	Error,
) {
	ctx := name_context {
		needle    = substring,
		count     = 0,
		allocator = allocator,
	}
	traverse(s, root, 0, limits, name_visit, &ctx)
	if !ctx.found {
		return {}, .Element_Unavailable
	}
	return ctx.result, .None
}

// name_context carries the search state for element_by_name. It embeds
// traverse_state so traverse can read the shared node counter.
name_context :: struct {
	using _:   traverse_state,
	needle:    string,
	found:     bool,
	result:    uia.Element,
	allocator: mem.Allocator,
}

// name_visit returns the first element whose name contains the needle.
name_visit :: proc(el: ^uia.Element, depth: int, data: rawptr) -> bool {
	ctx := (^name_context)(data)

	name, _ := uia.name(el, ctx.allocator)
	defer delete(name, ctx.allocator)
	if len(name) > 0 && contains_ci(name, ctx.needle) {
		ctx.result = uia.retain_element(el^)
		ctx.found = true
		return false
	}
	ctx.count += 1
	return true
}

// contains_ci reports whether hay contains needle, case-insensitively, for
// ASCII text.
contains_ci :: proc(hay, needle: string) -> bool {
	if len(needle) == 0 {
		return true
	}
	if len(hay) < len(needle) {
		return false
	}
	for i in 0 ..= len(hay) - len(needle) {
		match := true
		for j in 0 ..< len(needle) {
			if ascii_lower(hay[i + j]) != ascii_lower(needle[j]) {
				match = false
				break
			}
		}
		if match {
			return true
		}
	}
	return false
}

// ascii_lower lowercases an ASCII byte.
ascii_lower :: proc(c: byte) -> byte {
	if 'A' <= c && c <= 'Z' {
		return c + ('a' - 'A')
	}
	return c
}

// render converts node records into a compact text tree with indices. When
// match is non-empty, only nodes whose name, role, or value contains it
// (case-insensitively) are emitted; parent lines are shown collapsed so the
// caller still sees the tree shape around a match.
render :: proc(
	nodes: []Node,
	limits: Limits,
	match: string = "",
	allocator := context.allocator,
) -> (
	string,
	Error,
) {
	builder := strings.builder_make(allocator)
	last_shown := -1
	for n in nodes {
		keep :=
			match == "" ||
			contains_ci(n.name, match) ||
			contains_ci(n.role, match) ||
			contains_ci(n.value, match)
		if !keep {
			continue
		}

		if match != "" && n.index - last_shown > 1 {
			strings.write_string(&builder, "...\n")
		}
		for _ in 0 ..< n.depth {
			strings.write_string(&builder, "  ")
		}
		fmt.sbprintf(&builder, "[%d] %s", n.index, n.role)
		if name := truncate(n.name, limits.text_limit); len(name) > 0 {
			fmt.sbprintf(&builder, " %q", name)
		}
		fmt.sbprintf(
			&builder,
			" (%d,%d,%d,%d)",
			n.rect.left,
			n.rect.top,
			n.rect.right,
			n.rect.bottom,
		)
		if !n.enabled {
			strings.write_string(&builder, " (disabled)")
		}
		if value := truncate(n.value, limits.text_limit); len(value) > 0 {
			fmt.sbprintf(&builder, " value=%q", value)
		}
		strings.write_string(&builder, "\n")
		last_shown = n.index
	}
	return strings.to_string(builder), .None
}

// state renders the accessibility tree of the window with the given handle.
// When match is non-empty, only matching nodes are shown. The caller deletes
// the returned string.
state :: proc(
	s: ^Session,
	hwnd: windows.HWND,
	limits: Limits,
	match: string = "",
	allocator := context.allocator,
) -> (
	string,
	Error,
) {
	root, err := uia.element_from_handle(&s.auto, hwnd)
	if err != .None {
		return "", .Element_Unavailable
	}
	defer uia.release_element(&root)

	nodes, werr := walk(s, &root, limits, allocator)
	if werr != .None {
		return "", werr
	}
	defer destroy_nodes(nodes, allocator)

	return render(nodes, limits, match, allocator)
}

// text reads up to max_length characters of text content from the window.
// The caller deletes the returned string.
text :: proc(
	s: ^Session,
	hwnd: windows.HWND,
	max_length: i32 = 4096,
	allocator := context.allocator,
) -> (
	string,
	Error,
) {
	root, err := uia.element_from_handle(&s.auto, hwnd)
	if err != .None {
		return "", .Element_Unavailable
	}
	defer uia.release_element(&root)

	content, terr := uia.text(&root, max_length, allocator)
	if terr != .None {
		return "", .Text_Unavailable
	}
	return content, .None
}

// truncate clips a string to at most limit characters.
truncate :: proc(s: string, limit: int) -> string {
	if limit <= 0 || len(s) <= limit {
		return s
	}
	return s[:limit]
}