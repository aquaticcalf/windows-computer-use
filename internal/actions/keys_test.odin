package actions

import "core:sys/windows"
import "core:testing"

// Pure parser tests: no COM, no input injection. See DESIGN.md.

@(test)
test_parse_single_key :: proc(t: ^testing.T) {
	combos, err := parse_keys("Return")
	testing.expect(t, err == "")
	testing.expect(t, len(combos) == 1)
	if len(combos) == 1 {
		testing.expect(t, len(combos[0].keys) == 1)
		testing.expect(t, combos[0].keys[0].vk == windows.VK_RETURN)
	}
	destroy_key_combos(combos)
}

@(test)
test_parse_chord_with_modifier :: proc(t: ^testing.T) {
	combos, err := parse_keys("ctrl+s")
	testing.expect(t, err == "")
	testing.expect(t, len(combos) == 1)
	if len(combos) == 1 {
		combo := combos[0]
		testing.expect(t, .Ctrl in combo.modifiers)
		testing.expect(t, len(combo.keys) == 1)
		testing.expect(t, combo.keys[0].vk == windows.VK_S)
	}
	destroy_key_combos(combos)
}

@(test)
test_parse_multiple_modifiers :: proc(t: ^testing.T) {
	combos, err := parse_keys("ctrl+shift+t")
	testing.expect(t, err == "")
	if len(combos) == 1 {
		combo := combos[0]
		testing.expect(t, .Ctrl in combo.modifiers)
		testing.expect(t, .Shift in combo.modifiers)
		testing.expect(t, combo.keys[0].vk == windows.VK_T)
	}
	destroy_key_combos(combos)
}

@(test)
test_parse_super_key :: proc(t: ^testing.T) {
	combos, err := parse_keys("super+e")
	testing.expect(t, err == "")
	if len(combos) == 1 {
		combo := combos[0]
		testing.expect(t, .Super in combo.modifiers)
		testing.expect(t, combo.keys[0].vk == windows.VK_E)
		found_super := false
		for m in modifier_keys(combo.modifiers) {
			if m.vk == windows.VK_LWIN {
				found_super = true
				testing.expect(t, m.extended)
			}
		}
		testing.expect(t, found_super)
	}
	destroy_key_combos(combos)
}

@(test)
test_parse_space_separated_chords :: proc(t: ^testing.T) {
	combos, err := parse_keys("ctrl+s Return")
	testing.expect(t, err == "")
	testing.expect(t, len(combos) == 2)
	destroy_key_combos(combos)
}

@(test)
test_parse_named_key :: proc(t: ^testing.T) {
	combos, err := parse_keys("PageDown")
	testing.expect(t, err == "")
	if len(combos) == 1 {
		key := combos[0].keys[0]
		testing.expect(t, key.vk == windows.VK_NEXT)
		testing.expect(t, key.extended)
	}
	destroy_key_combos(combos)
}

@(test)
test_parse_function_key :: proc(t: ^testing.T) {
	combos, err := parse_keys("F5")
	testing.expect(t, err == "")
	if len(combos) == 1 {
		testing.expect(t, combos[0].keys[0].vk == windows.VK_F5)
	}
	destroy_key_combos(combos)
}

@(test)
test_parse_unknown_key_fails :: proc(t: ^testing.T) {
	combos, err := parse_keys("frobnicate")
	testing.expect(t, err != "")
	testing.expect(t, combos == nil)
}

@(test)
test_parse_case_insensitive :: proc(t: ^testing.T) {
	combos, err := parse_keys("CTRL+A")
	testing.expect(t, err == "")
	if len(combos) == 1 {
		combo := combos[0]
		testing.expect(t, .Ctrl in combo.modifiers)
		testing.expect(t, combo.keys[0].vk == windows.VK_A)
	}
	destroy_key_combos(combos)
}

@(test)
test_modifier_keys_order :: proc(t: ^testing.T) {
	keys := modifier_keys({.Ctrl, .Shift, .Alt, .Super})
	testing.expect(t, keys[0].vk == windows.VK_CONTROL)
	testing.expect(t, keys[1].vk == windows.VK_SHIFT)
	testing.expect(t, keys[2].vk == windows.VK_MENU)
	testing.expect(t, keys[3].vk == windows.VK_LWIN)
	testing.expect(t, keys[3].extended)
}

@(test)
test_modifier_keys_single :: proc(t: ^testing.T) {
	keys := modifier_keys({.Super})
	testing.expect(t, keys[0].vk == windows.VK_LWIN)
	testing.expect(t, keys[0].extended)
}
