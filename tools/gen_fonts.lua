-- Dev tool, not shipped in the binary: converts the pixel-art glyph
-- definitions below into src/big_font.lua and src/med_font.lua, the two
-- precomputed font tables block_fonts.lua requires() at runtime.
--
-- Run after editing/adding a glyph: luajit tools/gen_fonts.lua
--
-- Each generated file returns a table keyed by ASCII character, glyph =
-- array of rows, row = array of one-pixel-per-column strings (kept as
-- columns, not pre-joined, so runtime clipping can slice by column count
-- without cutting a multi-byte UTF-8 glyph character in half).

package.path = "src/?.lua;" .. package.path
local sChar = require("sextant_chars")

local GLYPH_W, GLYPH_H = 6, 9
local MACRO_W, MACRO_H = 3, 3
local FULL_BLOCK = "\u{2588}"

-- Each entry is a 6x9 pixel block, one row per line, 'X'/'x' = lit pixel.
-- Reference: https://www.kreativekorp.com/software/fonts/fairfax/
local GLYPHS = { -- >{
[" "] = [[
......
......
......
......
......
......
......
......
......]],

["!"] = [[
......
..X...
..X...
..X...
..X...
..X...
......
..X...
......]],

["\""] = [[
......
.X.X..
.X.X..
......
......
......
......
......
......]],

["#"] = [[
......
......
.X.X..
XXXXX.
.X.X..
XXXXX.
.X.X..
......
......]],

["$"] = [[
..X...
.XXX..
X.X.X.
X.X...
.XXX..
..X.X.
X.X.X.
.XXX..
..X...]],

["%"] = [[
......
.X....
X.X.X.
.X.X..
..X...
.X.X..
X.X.X.
...X..
......]],

["&"] = [[
......
.X....
X.X...
X.X...
.X....
X.X.X.
X..X..
.XX.X.
......]],

["'"] = [[
......
..X...
..X...
......
......
......
......
......
......]],

-- these two are curved (parenthesis) glyphs, not square brackets, despite
-- how they were originally named in the PoC this file was ported from
["("] = [[
...X..
..X...
..X...
.X....
.X....
.X....
..X...
..X...
...X..]],

[")"] = [[
..X...
...X..
...X..
....X.
....X.
....X.
...X..
...X..
..X...]],

["*"] = [[
......
......
..X...
X.X.X.
.XXX..
X.X.X.
..X...
......
......]],

["+"] = [[
......
......
..X...
..X...
XXXXX.
..X...
..X...
......
......]],

[","] = [[
......
......
......
......
......
..XX..
..XX..
...X..
..X...]],

["-"] = [[
......
......
......
......
XXXXX.
......
......
......
......]],

["."] = [[
......
......
......
......
......
......
..XX..
..XX..
......]],

["/"] = [[
....X.
....X.
...X..
...X..
..X...
.X....
.X....
X.....
X.....]],

[":"] = [[
......
......
..XX..
..XX..
......
..XX..
..XX..
......
......]],

[";"] = [[
......
......
..XX..
..XX..
......
..XX..
..XX..
...X..
..X...]],

["A"] = [[
......
.XXX..
X...X.
X...X.
XXXXX.
X...X.
X...X.
X...X.
......]],

["B"] = [[
......
XXXX..
X...X.
X...X.
XXXX..
X...X.
X...X.
XXXX..
......]],

["C"] = [[
......
.XXX..
X...X.
X.....
X.....
X.....
X...X.
.XXX..
......]],

["D"] = [[
......
XXXX..
X...X.
X...X.
X...X.
X...X.
X...X.
XXXX..
......]],

["E"] = [[
......
XXXXX.
X.....
X.....
XXXX..
X.....
X.....
XXXXX.
......]],

["F"] = [[
......
XXXXX.
X.....
X.....
XXXX..
X.....
X.....
X.....
......]],

["G"] = [[
......
.XXX..
X...X.
X.....
X..XX.
X...X.
X...X.
.XXX..
......]],

["H"] = [[
......
X...X.
X...X.
X...X.
XXXXX.
X...X.
X...X.
X...X.
......]],

["I"] = [[
......
.XXX..
..X...
..X...
..X...
..X...
..X...
.XXX..
......]],

["J"] = [[
......
..XXX.
...X..
...X..
...X..
...X..
X..X..
.XX...
......]],

["K"] = [[
......
X...X.
X..X..
X.X...
XX....
X.X...
X..X..
X...X.
......]],

["L"] = [[
......
X.....
X.....
X.....
X.....
X.....
X.....
XXXXX.
......]],

["M"] = [[
......
X...X.
XX.XX.
X.X.X.
X.X.X.
X...X.
X...X.
X...X.
......]],

["N"] = [[
......
X...X.
X...X.
XX..X.
X.X.X.
X..XX.
X...X.
X...X.
......]],

["O"] = [[
......
.XXX..
X...X.
X...X.
X...X.
X...X.
X...X.
.XXX..
......]],

["P"] = [[
......
XXXX..
X...X.
X...X.
XXXX..
X.....
X.....
X.....
......]],

["Q"] = [[
......
.XXX..
X...X.
X...X.
X...X.
X.X.X.
X..X..
.XX.X.
......]],

["R"] = [[
......
XXXX..
X...X.
X...X.
XXXX..
X.X...
X..X..
X...X.
......]],

["S"] = [[
......
.XXX..
X...X.
X.....
.XXX..
....X.
X...X.
.XXX..
......]],

["T"] = [[
......
XXXXX.
..X...
..X...
..X...
..X...
..X...
..X...
......]],

["U"] = [[
......
X...X.
X...X.
X...X.
X...X.
X...X.
X...X.
.XXX..
......]],

["V"] = [[
......
X...X.
X...X.
.X.X..
.X.X..
.X.X..
..X...
..X...
......]],

["W"] = [[
......
X...X.
X...X.
X...X.
X...X.
X.X.X.
X.X.X.
.X.X..
......]],

["X"] = [[
......
X...X.
X...X.
.X.X..
..X...
.X.X..
X...X.
X...X.
......]],

["Y"] = [[
......
X...X.
X...X.
.X.X..
..X...
..X...
..X...
..X...
......]],

["Z"] = [[
......
XXXXX.
....X.
...X..
..X...
.X....
X.....
XXXXX.
......]],

["a"] = [[
......
......
......
.XXX..
....X.
.XXXX.
X...X.
.XXXX.
......]],

["b"] = [[
......
X.....
X.....
X.XX..
XX..X.
X...X.
X...X.
XXXX..
......]],

["c"] = [[
......
......
......
.XXX..
X...X.
X.....
X.....
.XXXX.
......]],

["d"] = [[
......
....X.
....X.
.XX.X.
X..XX.
X...X.
X...X.
.XXXX.
......]],

["e"] = [[
......
......
......
.XXX..
X...X.
XXXXX.
X.....
.XXX..
......]],

["f"] = [[
......
...XX.
..X...
.XXX..
..X...
..X...
..X...
..X...
......]],

["g"] = [[
......
......
......
.XXXX.
X...X.
X..XX.
.XX.X.
....X.
.XXX..]],

["h"] = [[
......
X.....
X.....
X.XX..
XX..X.
X...X.
X...X.
X...X.
......]],

["i"] = [[
......
..X...
......
.XX...
..X...
..X...
..X...
.XXX..
......]],

["j"] = [[
......
...X..
......
..XX..
...X..
...X..
...X..
...X..
.XX...]],

["k"] = [[
......
X.....
X.....
X..X..
X.X...
XXX...
X..X..
X...X.
......]],

["l"] = [[
......
.XX...
..X...
..X...
..X...
..X...
..X...
.XXX..
......]],

["m"] = [[
......
......
......
XX.X..
X.X.X.
X.X.X.
X.X.X.
X.X.X.
......]],

["n"] = [[
......
......
......
X.XX..
XX..X.
X...X.
X...X.
X...X.
......]],

["o"] = [[
......
......
......
.XXX..
X...X.
X...X.
X...X.
.XXX..
......]],

["p"] = [[
......
......
......
X.XX..
XX..X.
X...X.
XXXX..
X.....
X.....]],

["q"] = [[
......
......
......
.XXXX.
X...X.
X..XX.
.XX.X.
....X.
....X.]],

["r"] = [[
......
......
......
X.XX..
XX..X.
X.....
X.....
X.....
......]],

["s"] = [[
......
......
......
.XXXX.
X.....
.XXX..
....X.
XXXX..
......]],

["t"] = [[
......
..X...
..X...
.XXX..
..X...
..X...
..X...
...XX.
......]],

["u"] = [[
......
......
......
X...X.
X...X.
X...X.
X..XX.
.XX.X.
......]],

["v"] = [[
......
......
......
X...X.
X...X.
.X.X..
.X.X..
..X...
......]],

["w"] = [[
......
......
......
X...X.
X.X.X.
X.X.X.
X.X.X.
.X.X..
......]],

["x"] = [[
......
......
......
X...X.
.X.X..
..X...
.X.X..
X...X.
......]],

["y"] = [[
......
......
......
X...X.
X...X.
X..XX.
.XX.X.
....X.
.XXX..]],

["z"] = [[
......
......
......
XXXXX.
...X..
..X...
.X....
XXXXX.
......]],

["0"] = [[
......
.XXX..
X...X.
X..XX.
X.X.X.
XX..X.
X...X.
.XXX..
......]],

["1"] = [[
......
..X...
XXX...
..X...
..X...
..X...
..X...
XXXXX.
......]],

["2"] = [[
......
.XXX..
X...X.
....X.
...X..
..X...
.X....
XXXXX.
......]],

["3"] = [[
......
.XXX..
X...X.
....X.
..XX..
....X.
X...X.
.XXX..
......]],

["4"] = [[
......
...X..
..XX..
.X.X..
X..X..
XXXXX.
...X..
...X..
......]],

["5"] = [[
......
XXXXX.
X.....
XXXX..
....X.
....X.
X...X.
.XXX..
......]],

["6"] = [[
......
.XXX..
X.....
XXXX..
X...X.
X...X.
X...X.
.XXX..
......]],

["7"] = [[
......
XXXXX.
....X.
...X..
...X..
..X...
..X...
..X...
......]],

["8"] = [[
......
.XXX..
X...X.
X...X.
.XXX..
X...X.
X...X.
.XXX..
......]],

["9"] = [[
......
.XXX..
X...X.
X...X.
X...X.
.XXXX.
....X.
.XXX..
......]],
} -- >}

local function pixel_rows(pixel_block)
	local rows = {}
	for line in pixel_block:gmatch("[^\r\n]+") do
		rows[#rows + 1] = line
	end
	return rows
end

local function to_big_rows(pixel_block)
	local rows = pixel_rows(pixel_block)
	local out = {}
	for r = 1, GLYPH_H do
		local line = {}
		for c = 1, GLYPH_W do
			local px = rows[r]:sub(c, c)
			line[c] = (px == "X" or px == "x") and FULL_BLOCK or " "
		end
		out[r] = line
	end
	return out
end

local function to_med_rows(pixel_block)
	local rows = pixel_rows(pixel_block)
	local grid = {}
	for r = 1, GLYPH_H do
		grid[r] = {}
		for c = 1, GLYPH_W do
			local px = rows[r]:sub(c, c)
			grid[r][c] = (px == "X" or px == "x") and 1 or 0
		end
	end
	local out = {}
	for macro_r = 0, MACRO_H - 1 do
		local line = {}
		for macro_c = 0, MACRO_W - 1 do
			local r1 = macro_r * 3 + 1
			local c1 = macro_c * 2 + 1
			local mask = grid[r1][c1] * 1 + grid[r1][c1 + 1] * 2
				+ grid[r1 + 1][c1] * 4 + grid[r1 + 1][c1 + 1] * 8
				+ grid[r1 + 2][c1] * 16 + grid[r1 + 2][c1 + 1] * 32
			line[#line + 1] = sChar[mask]
		end
		out[macro_r + 1] = line
	end
	return out
end

local function quote(s)
	return string.format("%q", s)
end

local function write_font_file(path, rows_by_char, glyph_h, glyph_w)
	local f = assert(io.open(path, "w"))
	f:write("-- Generated by tools/gen_fonts.lua from the glyph source in that file.\n")
	f:write("-- DO NOT EDIT BY HAND -- edit tools/gen_fonts.lua and re-run it instead.\n\n")
	f:write("return {\n")
	-- sorted iteration: stable, diffable output across regenerations
	local chars = {}
	for ch in pairs(rows_by_char) do chars[#chars + 1] = ch end
	table.sort(chars)
	for _, ch in ipairs(chars) do
		f:write("\t[" .. quote(ch) .. "] = {\n")
		for r = 1, glyph_h do
			local cols = {}
			for c = 1, glyph_w do cols[c] = quote(rows_by_char[ch][r][c]) end
			f:write("\t\t{ " .. table.concat(cols, ", ") .. " },\n")
		end
		f:write("\t},\n")
	end
	f:write("}\n")
	f:close()
end

local BIG_ROWS, MED_ROWS = {}, {}
local glyph_count = 0
for ch, pixel_block in pairs(GLYPHS) do
	BIG_ROWS[ch] = to_big_rows(pixel_block)
	MED_ROWS[ch] = to_med_rows(pixel_block)
	glyph_count = glyph_count + 1
end

write_font_file("src/big_font.lua", BIG_ROWS, GLYPH_H, GLYPH_W)
write_font_file("src/med_font.lua", MED_ROWS, MACRO_H, MACRO_W)

print("wrote src/big_font.lua and src/med_font.lua (" .. glyph_count .. " glyphs)")

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
