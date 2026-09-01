-- Character-cell block fonts: renders text onto a pane at two sizes.
--   big: one screen cell per glyph pixel (6 cols x 9 rows per character).
--   med: glyph pixels packed 2x3 through the sextant table (3x3 per character).
-- Glyph data is precomputed at build time by tools/gen_fonts.lua into
-- big_font.lua/med_font.lua -- this file is pure lookup + draw, no parsing
-- at load or draw time. To add/fix a glyph, edit tools/gen_fonts.lua and
-- re-run it, don't edit the generated font files.

local BIG_ROWS = require("big_font")
local MED_ROWS = require("med_font")

local GLYPH_W, GLYPH_H = 6, 9
local MACRO_W, MACRO_H = 3, 3

local function render_rows_big(ch) return BIG_ROWS[ch] or BIG_ROWS[" "] end
local function render_rows_med(ch) return MED_ROWS[ch] or MED_ROWS[" "] end

-- draws `text` starting at pane.x/pane.y, one glyph per character, clipped
-- to pane.w/pane.h (glyphs past the right edge are skipped, a partially
-- visible glyph is truncated column-wise, rows past the bottom edge are
-- truncated too). Rows are stored as arrays of one-pixel-per-column strings
-- rather than pre-joined strings: each pixel character is UTF-8 multi-byte
-- (a full block is 3 bytes, sextant glyphs up to 4), so clipping by byte
-- count would cut a character in half -- concat only the surviving columns.
local function draw(pane, text, glyph_w, glyph_h, render_rows, fg, bg) -- >{
	if not pane or pane.w <= 0 or pane.h <= 0 then return end
	local pane_right = pane.x + pane.w
	local max_rows = math.min(glyph_h, pane.h)
	for i = 1, #text do
		local col_x = pane.x + (i - 1) * glyph_w
		if col_x >= pane_right then break end
		local avail_w = math.min(glyph_w, pane_right - col_x)
		local rows = render_rows(text:sub(i, i))
		for row = 1, max_rows do
			local row_str = table.concat(rows[row], "", 1, avail_w)
			WriteAt(col_x, pane.y + row - 1, row_str, fg, bg)
		end
	end
end -- >}

return { -- >{
	big = function(pane, text, fg, bg) draw(pane, text, GLYPH_W, GLYPH_H, render_rows_big, fg, bg) end,
	med = function(pane, text, fg, bg) draw(pane, text, MACRO_W, MACRO_H, render_rows_med, fg, bg) end,
	width_big = function(text) return #text * GLYPH_W end,
	width_med = function(text) return #text * MACRO_W end,
	height_big = GLYPH_H,
	height_med = MACRO_H,
} -- >}

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
