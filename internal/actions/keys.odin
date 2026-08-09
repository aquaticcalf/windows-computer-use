package actions

import "core:strconv"
import "core:strings"
import "core:sys/windows"

// xdotool-style key syntax parser. It maps names like "ctrl+s", "super+e",
// and "Return" to virtual-key codes with modifiers. Pure computation, no
// side effects, so it is fully unit-testable. See ARCHITECTURE.md (Actions).

// Key is one physical key identified by its virtual-key code. The extended
// flag marks navigation-cluster keys so the injected scan code is correct.
Key :: struct {
	vk:       u16,
	extended: bool,
}

// Modifier selects a key held while a chord's keys are pressed.
Modifier :: enum {
	Ctrl,
	Shift,
	Alt,
	Super,
}

// Key_Combo is one chord: a set of held modifiers plus the keys to tap.
Key_Combo :: struct {
	modifiers: bit_set[Modifier],
	keys:      [dynamic]Key,
}

// destroy_key_combos frees the chord list returned by parse_keys.
destroy_key_combos :: proc(combos: []Key_Combo) {
	for combo in combos {
		delete(combo.keys)
	}
	delete(combos)
}

// parse_keys parses xdotool-style syntax into a list of chords. Space
// separates chords; "+" separates keys within a chord. On error, err names
// the unknown key token and combos is nil.
parse_keys :: proc(
	spec: string,
	allocator := context.allocator,
) -> (
	combos: []Key_Combo,
	err: string,
) {
	fields := strings.fields(spec, allocator)
	defer delete(fields)
	built, berr := make([dynamic]Key_Combo, 0, len(fields), allocator)
	if berr != nil {
		return nil, "out of memory"
	}

	for field in fields {
		combo, perr := parse_combo(field, allocator)
		if perr != "" {
			destroy_key_combos(built[:])
			return nil, perr
		}
		append(&built, combo)
	}

	return built[:], ""
}

// parse_combo parses one chord like "ctrl+shift+t" into a Key_Combo.
parse_combo :: proc(spec: string, allocator := context.allocator) -> (Key_Combo, string) {
	parts := strings.split(spec, "+", allocator)

	combo: Key_Combo
	keys, kerr := make([dynamic]Key, 0, 2, allocator)
	if kerr != nil {
		delete(parts)
		return {}, "out of memory"
	}
	for part in parts {
		token := strings.trim_space(part)
		if len(token) == 0 {
			delete(parts)
			delete(keys)
			return {}, "empty key"
		}
		if modifier, ok := modifier_of(token); ok {
			combo.modifiers += {modifier}
			continue
		}
		key, perr := key_of(token, allocator)
		if perr != "" {
			delete(parts)
			delete(keys)
			return {}, perr
		}
		append(&keys, key)
	}
	delete(parts)

	if len(keys) == 0 {
		delete(keys)
		return {}, "no key in chord"
	}
	combo.keys = keys
	return combo, ""
}

// modifier_of maps a modifier token to its enum value.
modifier_of :: proc(name: string) -> (Modifier, bool) {
	switch {
	case ci_eq(name, "ctrl"), ci_eq(name, "control"):
		return .Ctrl, true
	case ci_eq(name, "shift"):
		return .Shift, true
	case ci_eq(name, "alt"):
		return .Alt, true
	case ci_eq(name, "super"), ci_eq(name, "meta"), ci_eq(name, "win"), ci_eq(name, "windows"):
		return .Super, true
	}
	return .Ctrl, false
}

// key_of maps one key token to a virtual key. Letters, digits, f-keys, and a
// set of named keys are recognized. err names an unknown token.
key_of :: proc(name: string, allocator := context.allocator) -> (Key, string) {
	if len(name) == 1 {
		if c := name[0]; 'a' <= c && c <= 'z' {
			return Key{vk = windows.VK_A + u16(c - 'a')}, ""
		}
		if c := name[0]; 'A' <= c && c <= 'Z' {
			return Key{vk = windows.VK_A + u16(c - 'A')}, ""
		}
		if c := name[0]; '0' <= c && c <= '9' {
			return Key{vk = windows.VK_0 + u16(c - '0')}, ""
		}
	}

	if len(name) >= 2 && (name[0] == 'f' || name[0] == 'F') {
		if num, ok := strconv.parse_int(name[1:], 10); ok && 1 <= num && num <= 24 {
			return Key{vk = windows.VK_F1 + u16(num - 1)}, ""
		}
	}

	switch {
	case ci_eq(name, "return"), ci_eq(name, "enter"):
		return Key{vk = windows.VK_RETURN}, ""
	case ci_eq(name, "space"):
		return Key{vk = windows.VK_SPACE}, ""
	case ci_eq(name, "tab"):
		return Key{vk = windows.VK_TAB}, ""
	case ci_eq(name, "escape"), ci_eq(name, "esc"):
		return Key{vk = windows.VK_ESCAPE}, ""
	case ci_eq(name, "backspace"):
		return Key{vk = windows.VK_BACK}, ""
	case ci_eq(name, "delete"), ci_eq(name, "del"):
		return Key{vk = windows.VK_DELETE, extended = true}, ""
	case ci_eq(name, "insert"), ci_eq(name, "ins"):
		return Key{vk = windows.VK_INSERT, extended = true}, ""
	case ci_eq(name, "home"):
		return Key{vk = windows.VK_HOME, extended = true}, ""
	case ci_eq(name, "end"):
		return Key{vk = windows.VK_END, extended = true}, ""
	case ci_eq(name, "pageup"), ci_eq(name, "pgup"):
		return Key{vk = windows.VK_PRIOR, extended = true}, ""
	case ci_eq(name, "pagedown"), ci_eq(name, "pgdn"):
		return Key{vk = windows.VK_NEXT, extended = true}, ""
	case ci_eq(name, "up"):
		return Key{vk = windows.VK_UP, extended = true}, ""
	case ci_eq(name, "down"):
		return Key{vk = windows.VK_DOWN, extended = true}, ""
	case ci_eq(name, "left"):
		return Key{vk = windows.VK_LEFT, extended = true}, ""
	case ci_eq(name, "right"):
		return Key{vk = windows.VK_RIGHT, extended = true}, ""
	case ci_eq(name, "print"), ci_eq(name, "printscreen"):
		return Key{vk = windows.VK_SNAPSHOT}, ""
	case ci_eq(name, "capslock"):
		return Key{vk = windows.VK_CAPITAL}, ""
	case ci_eq(name, "pause"), ci_eq(name, "break"):
		return Key{vk = windows.VK_PAUSE}, ""
	case ci_eq(name, "comma"):
		return Key{vk = windows.VK_OEM_COMMA}, ""
	case ci_eq(name, "period"):
		return Key{vk = windows.VK_OEM_PERIOD}, ""
	case ci_eq(name, "slash"):
		return Key{vk = windows.VK_OEM_2}, ""
	case ci_eq(name, "semicolon"):
		return Key{vk = windows.VK_OEM_1}, ""
	case ci_eq(name, "minus"):
		return Key{vk = windows.VK_OEM_MINUS}, ""
	case ci_eq(name, "equal"):
		return Key{vk = windows.VK_OEM_PLUS}, ""
	case:
		return {}, name
	}
}

// ci_eq compares two short ASCII strings case-insensitively without
// allocating.
ci_eq :: proc(a, b: string) -> bool {
	if len(a) != len(b) {
		return false
	}
	for i in 0 ..< len(a) {
		if ascii_lower(a[i]) != ascii_lower(b[i]) {
			return false
		}
	}
	return true
}

// ascii_lower lowercases an ASCII byte.
ascii_lower :: proc(c: byte) -> byte {
	if 'A' <= c && c <= 'Z' {
		return c + ('a' - 'A')
	}
	return c
}

// modifier_keys returns the virtual keys for a modifier set, in a fixed order.
modifier_keys :: proc(modifiers: bit_set[Modifier]) -> [4]Key {
	result: [4]Key
	index := 0
	if .Ctrl in modifiers {
		result[index] = Key {
			vk = windows.VK_CONTROL,
		}
		index += 1
	}
	if .Shift in modifiers {
		result[index] = Key {
			vk = windows.VK_SHIFT,
		}
		index += 1
	}
	if .Alt in modifiers {
		result[index] = Key {
			vk = windows.VK_MENU,
		}
		index += 1
	}
	if .Super in modifiers {
		result[index] = Key {
			vk       = windows.VK_LWIN,
			extended = true,
		}
		index += 1
	}
	return result
}
