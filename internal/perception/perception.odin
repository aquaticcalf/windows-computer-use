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
	count := 0
	walk_node(s, root, 0, limits, &built, &count, allocator)
	result = built[:]
	return result, .None
}

// walk_node emits one node then recurses into its children and siblings.
walk_node :: proc(
	s: ^Session,
	el: ^uia.Element,
	depth: int,
	limits: Limits,
	built: ^[dynamic]Node,
	count: ^int,
	allocator: mem.Allocator,
) {
	if count^ >= limits.max_nodes || depth > limits.max_depth {
		return
	}

	name, _ := uia.name(el, allocator)
	role_id, _ := uia.control_type(el)
	role := uia.control_type_name(role_id)
	rect, _ := uia.bounding_rect(el)
	enabled, _ := uia.is_enabled(el)

	value := ""
	if role == "edit" || role == "combobox" {
		value, _ = uia.value(el, allocator)
	}

	append(
		built,
		Node {
			index = count^,
			depth = depth,
			role = role,
			name = name,
			value = value,
			rect = rect,
			enabled = enabled,
		},
	)
	count^ += 1

	child, ok := uia.first_child(&s.auto, el)
	if !ok {
		return
	}
	defer uia.release_element(&child)
	walk_node(s, &child, depth + 1, limits, built, count, allocator)

	sibling, sok := uia.next_sibling(&s.auto, &child)
	for sok {
		walk_node(s, &sibling, depth + 1, limits, built, count, allocator)
		uia.release_element(&sibling)
		sibling, sok = uia.next_sibling(&s.auto, &child)
	}
}

// render converts node records into a compact text tree with indices.
render :: proc(nodes: []Node, limits: Limits, allocator := context.allocator) -> (string, Error) {
	builder := strings.builder_make(allocator)
	for n in nodes {
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
	}
	return strings.to_string(builder), .None
}

// state renders the accessibility tree of the window with the given handle.
// The caller deletes the returned string.
state :: proc(
	s: ^Session,
	hwnd: windows.HWND,
	limits: Limits,
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

	return render(nodes, limits, allocator)
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
