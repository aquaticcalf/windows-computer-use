package capture

import "core:hash"
import "core:sys/windows"

// capture_window captures a window's rectangle and returns the pixels as a
// PNG byte slice. The PNG encoder is local and writes stored (uncompressed)
// deflate blocks, so there is no zlib dependency. The caller deletes the
// result. See ARCHITECTURE.md (optional screenshots).
capture_window :: proc(
	hwnd: windows.HWND,
	allocator := context.allocator,
) -> (
	result: []byte,
	ok: bool,
) {
	rect: windows.RECT
	if !windows.GetWindowRect(hwnd, &rect) {
		return nil, false
	}
	width := rect.right - rect.left
	height := rect.bottom - rect.top
	if width <= 0 || height <= 0 {
		return nil, false
	}

	dc := windows.GetDC(hwnd)
	if dc == nil {
		return nil, false
	}
	defer windows.ReleaseDC(hwnd, dc)

	mem_dc := windows.CreateCompatibleDC(dc)
	if mem_dc == nil {
		return nil, false
	}
	defer windows.DeleteDC(mem_dc)

	bmi := windows.BITMAPINFO{}
	bmi.bmiHeader.biSize = size_of(windows.BITMAPINFOHEADER)
	bmi.bmiHeader.biWidth = width
	bmi.bmiHeader.biHeight = -height
	bmi.bmiHeader.biPlanes = 1
	bmi.bmiHeader.biBitCount = 32
	bmi.bmiHeader.biCompression = windows.BI_RGB

	bits: windows.PVOID
	section := windows.CreateDIBSection(dc, &bmi, 0, &bits, nil, 0)
	if section == nil {
		return nil, false
	}
	defer windows.DeleteObject(windows.HGDIOBJ(section))

	previous := windows.SelectObject(mem_dc, windows.HGDIOBJ(section))
	defer windows.SelectObject(mem_dc, previous)

	if !windows.BitBlt(mem_dc, 0, 0, width, height, dc, 0, 0, windows.SRCCOPY) {
		return nil, false
	}

	// bits points at top-down BGRA pixels.
	raw := ([^]u32)(bits)
	rgba, rerr := make([]u8, int(width) * int(height) * 4, allocator)
	if rerr != nil {
		return nil, false
	}
	defer delete(rgba, allocator)
	for i in 0 ..< width * height {
		bgra := raw[i]
		rgba[i * 4 + 0] = u8(bgra)
		rgba[i * 4 + 1] = u8(bgra >> 8)
		rgba[i * 4 + 2] = u8(bgra >> 16)
		rgba[i * 4 + 3] = u8(bgra >> 24)
	}

	return encode_png(rgba, int(width), int(height), allocator)
}

// encode_png wraps RGBA pixel rows in a valid PNG file.
encode_png :: proc(
	rgba: []u8,
	width, height: int,
	allocator := context.allocator,
) -> (
	result: []byte,
	ok: bool,
) {
	filtered, ferr := make([]u8, height * (1 + width * 4), allocator)
	if ferr != nil {
		return nil, false
	}
	defer delete(filtered, allocator)

	row_bytes := width * 4
	for y in 0 ..< height {
		filtered[y * (row_bytes + 1)] = 0
		dst := filtered[y * (row_bytes + 1) + 1:]
		src := rgba[y * row_bytes:(y + 1) * row_bytes]
		copy(dst, src)
	}

	stream, serr := stored_zlib(filtered, allocator)
	if !serr {
		return nil, false
	}
	defer delete(stream, allocator)

	png, perr := make([dynamic]u8, 0, len(stream) + 64, allocator)
	if perr != nil {
		return nil, false
	}

	append(&png, 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)

	ihdr, ierr := make([]u8, 13, allocator)
	if ierr != nil {
		return nil, false
	}
	w := be32(width)
	h := be32(height)
	ihdr[0], ihdr[1], ihdr[2], ihdr[3] = w[0], w[1], w[2], w[3]
	ihdr[4], ihdr[5], ihdr[6], ihdr[7] = h[0], h[1], h[2], h[3]
	ihdr[8] = 8 // bit depth
	ihdr[9] = 6 // color type RGBA
	append_chunk(&png, "IHDR", ihdr)
	delete(ihdr, allocator)

	append_chunk(&png, "IDAT", stream)
	append_chunk(&png, "IEND", nil)

	result = png[:]
	return result, true
}

// stored_zlib builds a zlib stream from raw deflate stored blocks plus an
// Adler-32 checksum. It needs no compressor.
stored_zlib :: proc(data: []u8, allocator := context.allocator) -> (result: []byte, ok: bool) {
	stream, serr := make([dynamic]u8, 0, len(data) + len(data) / 65535 * 5 + 16, allocator)
	if serr != nil {
		return nil, false
	}
	append(&stream, 0x78, 0x01)

	offset := 0
	for offset < len(data) {
		chunk := min(len(data) - offset, 65535)
		block_header := u8(0)
		if offset + chunk == len(data) {
			block_header = 0x80
		}
		append(&stream, block_header)
		append(&stream, u8(chunk & 0xFF), u8((chunk >> 8) & 0xFF))
		neg := ~u16(chunk)
		append(&stream, u8(neg & 0xFF), u8((neg >> 8) & 0xFF))
		append(&stream, ..data[offset:offset + chunk])
		offset += chunk
	}

	a, b := adler32(data)
	append(&stream, u8((b >> 8) & 0xFF), u8(b & 0xFF), u8((a >> 8) & 0xFF), u8(a & 0xFF))
	result = stream[:]
	return result, true
}

// adler32 computes the two halves of the Adler-32 checksum.
adler32 :: proc(data: []u8) -> (a, b: u32) {
	MOD :: 65521
	a = 1
	for x in data {
		a = (a + u32(x)) % MOD
		b = (b + a) % MOD
	}
	return a, b
}

// append_chunk writes a PNG chunk: length, type, data, and crc of type+data.
append_chunk :: proc(png: ^[dynamic]u8, chunk_type: string, data: []u8) {
	length := len(data)
	append(png, u8(length >> 24), u8(length >> 16), u8(length >> 8), u8(length))
	append(png, chunk_type[0], chunk_type[1], chunk_type[2], chunk_type[3])
	start := len(png)
	append(png, ..data)
	crc := hash.crc32(png[start - 4:])
	append(png, u8(crc >> 24), u8(crc >> 16), u8(crc >> 8), u8(crc))
}

// be32 encodes an int as a big-endian 4-byte array.
be32 :: proc(value: int) -> [4]u8 {
	return [4]u8{u8(value >> 24), u8(value >> 16), u8(value >> 8), u8(value)}
}
