package capture

import "core:c"
import "core:hash"
import "core:sys/windows"
import stbi "vendor:stb/image"

foreign import user32 "system:User32.lib"

@(default_calling_convention = "system")
foreign user32 {
	// PrintWindow asks the target window to render into the supplied DC.
	PrintWindow :: proc(hwnd: windows.HWND, dc: windows.HDC, flags: windows.UINT) -> windows.BOOL ---
}

PW_RENDERFULLCONTENT :: 0x00000002

// capture_pixels captures a window's rectangle into top-down RGBA bytes.
// The caller owns the slice and deletes it. See ARCHITECTURE.md (screenshots).
capture_pixels :: proc(
	hwnd: windows.HWND,
	allocator := context.allocator,
) -> (
	rgba: []u8,
	width, height: int,
	ok: bool,
) {
	rect: windows.RECT
	if !windows.GetWindowRect(hwnd, &rect) {
		return nil, 0, 0, false
	}
	width = int(rect.right - rect.left)
	height = int(rect.bottom - rect.top)
	if width <= 0 || height <= 0 {
		return nil, 0, 0, false
	}

	dc := windows.GetDC(hwnd)
	if dc == nil {
		return nil, 0, 0, false
	}
	defer windows.ReleaseDC(hwnd, dc)

	mem_dc := windows.CreateCompatibleDC(dc)
	if mem_dc == nil {
		return nil, 0, 0, false
	}
	defer windows.DeleteDC(mem_dc)

	bmi := windows.BITMAPINFO{}
	bmi.bmiHeader.biSize = size_of(windows.BITMAPINFOHEADER)
	bmi.bmiHeader.biWidth = i32(width)
	bmi.bmiHeader.biHeight = -i32(height)
	bmi.bmiHeader.biPlanes = 1
	bmi.bmiHeader.biBitCount = 32
	bmi.bmiHeader.biCompression = windows.BI_RGB

	bits: windows.PVOID
	section := windows.CreateDIBSection(dc, &bmi, 0, &bits, nil, 0)
	if section == nil {
		return nil, 0, 0, false
	}
	defer windows.DeleteObject(windows.HGDIOBJ(section))

	previous := windows.SelectObject(mem_dc, windows.HGDIOBJ(section))
	defer windows.SelectObject(mem_dc, previous)

	// GDI BitBlt returns empty pixels for many GPU-composited windows. Ask the
	// target to render itself first, then retain BitBlt as a legacy fallback.
	rendered := PrintWindow(hwnd, mem_dc, PW_RENDERFULLCONTENT)
	if !rendered &&
	   !windows.BitBlt(mem_dc, 0, 0, i32(width), i32(height), dc, 0, 0, windows.SRCCOPY) {
		return nil, 0, 0, false
	}

	// bits points at top-down BGRA pixels.
	raw := ([^]u32)(bits)
	pixels, rerr := make([]u8, int(width) * int(height) * 4, allocator)
	if rerr != nil {
		return nil, 0, 0, false
	}
	rgba = pixels
	for i in 0 ..< width * height {
		bgra := raw[i]
		rgba[i * 4 + 0] = u8(bgra)
		rgba[i * 4 + 1] = u8(bgra >> 8)
		rgba[i * 4 + 2] = u8(bgra >> 16)
		rgba[i * 4 + 3] = u8(bgra >> 24)
	}
	return rgba, width, height, true
}

// capture_window captures a window as a PNG byte slice. The caller deletes
// the result.
capture_window :: proc(
	hwnd: windows.HWND,
	allocator := context.allocator,
) -> (
	result: []byte,
	ok: bool,
) {
	rgba, width, height, pok := capture_pixels(hwnd, allocator)
	if !pok {
		return nil, false
	}
	defer delete(rgba, allocator)
	return encode_png(rgba, width, height, allocator)
}

// capture_window_jpeg captures a window as a JPEG byte slice at the given
// quality (0..100). The caller deletes the result.
capture_window_jpeg :: proc(
	hwnd: windows.HWND,
	quality: int,
	allocator := context.allocator,
) -> (
	result: []byte,
	ok: bool,
) {
	rgba, width, height, pok := capture_pixels(hwnd, allocator)
	if !pok {
		return nil, false
	}
	defer delete(rgba, allocator)
	return encode_jpeg(rgba, width, height, quality, allocator)
}

// encode_jpeg converts RGBA pixels to a JPEG byte slice via stb_image_write.
encode_jpeg :: proc(
	rgba: []u8,
	width, height, quality: int,
	allocator := context.allocator,
) -> (
	result: []byte,
	ok: bool,
) {
	rgb, rerr := make([]u8, width * height * 3, allocator)
	if rerr != nil {
		return nil, false
	}
	defer delete(rgb, allocator)
	for i in 0 ..< width * height {
		rgb[i * 3 + 0] = rgba[i * 4 + 0]
		rgb[i * 3 + 1] = rgba[i * 4 + 1]
		rgb[i * 3 + 2] = rgba[i * 4 + 2]
	}

	// The output buffer is preallocated to one byte per pixel, far beyond
	// what a screenshot JPEG needs at any quality; the callback writes into
	// it at a running offset without allocating.
	out, oerr := make([]u8, width * height, allocator)
	if oerr != nil {
		return nil, false
	}
	offset := 0
	ctx := Jpeg_Ctx {
		buf      = raw_data(out),
		offset   = &offset,
		capacity = len(out),
	}
	res := stbi.write_jpg_to_func(
		jpeg_write_cb,
		&ctx,
		c.int(width),
		c.int(height),
		3,
		raw_data(rgb),
		c.int(quality),
	)
	if res == 0 || offset == 0 {
		delete(out, allocator)
		return nil, false
	}
	result = out[:offset]
	return result, true
}

// Jpeg_Ctx carries the preallocated output buffer for the stb callback.
Jpeg_Ctx :: struct {
	buf:      [^]u8,
	offset:   ^int,
	capacity: int,
}

// jpeg_write_cb appends encoded bytes into the preallocated buffer. It is a
// contextless C callback, so it must not allocate.
jpeg_write_cb :: proc "c" (ctx: rawptr, data: rawptr, size: c.int) {
	c := (^Jpeg_Ctx)(ctx)
	src := ([^]u8)(data)
	for i in 0 ..< int(size) {
		if c.offset^ < c.capacity {
			c.buf[c.offset^] = src[i]
			c.offset^ += 1
		}
	}
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
