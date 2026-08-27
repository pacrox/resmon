-- Sextant block table, indexed by a 6-bit mask.
-- Bit layout within one terminal cell (2 columns x 3 rows):
--   bit0=top-left   bit1=top-right
--   bit2=mid-left   bit3=mid-right
--   bit4=bottom-left bit5=bottom-right

local sChar = { -- >{
	[0]  = "\u{0020}", -- empty space
	[1]  = "\u{1FB00}", -- Sextant-1
	[2]  = "\u{1FB01}", -- Sextant-2
	[3]  = "\u{1FB02}", -- Sextant-12
	[4]  = "\u{1FB03}", -- Sextant-3
	[5]  = "\u{1FB04}", -- Sextant-13
	[6]  = "\u{1FB05}", -- Sextant-23
	[7]  = "\u{1FB06}", -- Sextant-123
	[8]  = "\u{1FB07}", -- Sextant-4
	[9]  = "\u{1FB08}", -- Sextant-14
	[10] = "\u{1FB09}", -- Sextant-24
	[11] = "\u{1FB0A}", -- Sextant-124
	[12] = "\u{1FB0B}", -- Sextant-34
	[13] = "\u{1FB0C}", -- Sextant-134
	[14] = "\u{1FB0D}", -- Sextant-234
	[15] = "\u{1FB0E}", -- Sextant-1234
	[16] = "\u{1FB0F}", -- Sextant-5
	[17] = "\u{1FB10}", -- Sextant-15
	[18] = "\u{1FB11}", -- Sextant-25
	[19] = "\u{1FB12}", -- Sextant-125
	[20] = "\u{1FB13}", -- Sextant-35
	[21] = "\u{258C}",  -- Sextant-135 -> Left Half Block
	[22] = "\u{1FB14}", -- Sextant-235
	[23] = "\u{1FB15}", -- Sextant-1235
	[24] = "\u{1FB16}", -- Sextant-45
	[25] = "\u{1FB17}", -- Sextant-145
	[26] = "\u{1FB18}", -- Sextant-245
	[27] = "\u{1FB19}", -- Sextant-1245
	[28] = "\u{1FB1A}", -- Sextant-345
	[29] = "\u{1FB1B}", -- Sextant-1345
	[30] = "\u{1FB1C}", -- Sextant-2345
	[31] = "\u{1FB1D}", -- Sextant-12345
	[32] = "\u{1FB1E}", -- Sextant-6
	[33] = "\u{1FB1F}", -- Sextant-16
	[34] = "\u{1FB20}", -- Sextant-26
	[35] = "\u{1FB21}", -- Sextant-126
	[36] = "\u{1FB22}", -- Sextant-36
	[37] = "\u{1FB23}", -- Sextant-136
	[38] = "\u{1FB24}", -- Sextant-236
	[39] = "\u{1FB25}", -- Sextant-1236
	[40] = "\u{1FB26}", -- Sextant-46
	[41] = "\u{1FB27}", -- Sextant-146
	[42] = "\u{2590}",  -- Sextant-246 -> Right Half Block
	[43] = "\u{1FB28}", -- Sextant-1246
	[44] = "\u{1FB29}", -- Sextant-346
	[45] = "\u{1FB2A}", -- Sextant-1346
	[46] = "\u{1FB2B}", -- Sextant-2346
	[47] = "\u{1FB2C}", -- Sextant-12346
	[48] = "\u{1FB2D}", -- Sextant-56
	[49] = "\u{1FB2E}", -- Sextant-156
	[50] = "\u{1FB2F}", -- Sextant-256
	[51] = "\u{1FB30}", -- Sextant-1256
	[52] = "\u{1FB31}", -- Sextant-356
	[53] = "\u{1FB32}", -- Sextant-1356
	[54] = "\u{1FB33}", -- Sextant-2356
	[55] = "\u{1FB34}", -- Sextant-12356
	[56] = "\u{1FB35}", -- Sextant-456
	[57] = "\u{1FB36}", -- Sextant-1456
	[58] = "\u{1FB37}", -- Sextant-2456
	[59] = "\u{1FB38}", -- Sextant-12456
	[60] = "\u{1FB39}", -- Sextant-3456
	[61] = "\u{1FB3A}", -- Sextant-13456
	[62] = "\u{1FB3B}", -- Sextant-23456
	[63] = "\u{2588}",  -- All filled -> Full Block
} -- >}

return sChar

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
