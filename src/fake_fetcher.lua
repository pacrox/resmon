-- Shared fake-data generator for the standalone `-s`/`-d` sample/demo CLI
-- mode. Given a module's `sample` template (declared alongside its
-- `info`/`opts` in the module's own file), produces data matching the real
-- fetcher cache shape it describes -- no addon calculates its own fake
-- data, it only declares the shape/range it expects.
--
-- Template grammar (a node is exactly one of):
--   { min, max }                    -- scalar leaf: continuous 1D noise in [min,max]
--   { {min,max}, count = N }        -- N independently-noised scalar leaves, as a 1..N array
--   { record = {...}, count = N }   -- N independently-generated copies of a record template
--   { template = "...", args = {node, ...} } -- each arg built independently, then
--                                    -- string.format(template, unpack(built_args))
--                                    -- (e.g. noised numbers embedded in a JSON string)
--   { v1, v2, ... }                 -- (length ~= 2, or non-numeric) pick leaf: cycles v1..vN by row index
--   "literal" / 42                  -- static leaf, used as-is
--   { key = node, ... }             -- named sub-table, recursed key by key
--
-- Every scalar/repeated-numeric leaf gets its own independently-seeded 1D
-- noise generator (one per template path), so values drift smoothly across
-- calls instead of jumping randomly tick to tick.

-- 1D value noise: a random value is pinned at every integer point on a time
-- lattice (lazily, as `t` reaches it), and consecutive points are
-- smoothstep-interpolated for the fractional part -- cheap, deterministic
-- given a seed, good enough to look like organic drift for demo data.
local LCG_A, LCG_C, LCG_M = 1103515245, 12345, 2147483648

local function new_generator(seed) -- >{
	local points = {}
	local state = seed % LCG_M

	local function point_at(i)
		local p = points[i]
		if p then return p end
		state = (state * LCG_A + LCG_C) % LCG_M
		p = state / LCG_M
		points[i] = p
		-- bound memory: a long-running demo shouldn't accumulate lattice
		-- points forever
		points[i - 256] = nil
		return p
	end

	local function smoothstep(x) return x * x * (3 - 2 * x) end

	return function(t)
		local i = math.floor(t)
		local frac = t - i
		local a, b = point_at(i), point_at(i + 1)
		return a + (b - a) * smoothstep(frac)
	end
end -- >}

-- one lattice step every NOISE_PERIOD seconds of wall-clock time; larger =
-- slower, smoother drift
local NOISE_PERIOD = 3.0

local M = {}

function M.new() -- >{
	local generators = {}
	local origin = MonotonicNow()
	local next_seed = os.time()

	local function noise_value(path, lo, hi)
		local gen = generators[path]
		if not gen then
			next_seed = next_seed + 1
			gen = new_generator(next_seed)
			generators[path] = gen
		end
		local t = (MonotonicNow() - origin) / NOISE_PERIOD
		return lo + gen(t) * (hi - lo)
	end

	-- idx: 1-based row index when `node` sits inside a repeated group (used
	-- by the "pick" leaf to cycle through its literal values); 1 at the top.
	local function build(node, path, idx)
		local nt = type(node)
		if nt == "string" or nt == "number" then return node end
		if nt ~= "table" then return node end

		if node.record ~= nil and type(node.count) == "number" then
			local out = {}
			for i = 1, node.count do
				out[i] = build(node.record, path .. "[" .. i .. "]", i)
			end
			return out
		end

		if type(node.template) == "string" and type(node.args) == "table" then
			local built = {}
			for i, arg in ipairs(node.args) do
				built[i] = build(arg, path .. ".args[" .. i .. "]", idx)
			end
			return string.format(node.template, unpack(built))
		end

		if type(node[1]) == "table" and #node[1] == 2 and type(node.count) == "number" then
			local lo, hi = node[1][1], node[1][2]
			local out = {}
			for i = 1, node.count do
				out[i] = noise_value(path .. "[" .. i .. "]", lo, hi)
			end
			return out
		end

		if #node == 2 and type(node[1]) == "number" and type(node[2]) == "number" then
			return noise_value(path, node[1], node[2])
		end

		if node[1] ~= nil then
			local n = #node
			return node[((idx - 1) % n) + 1]
		end

		local out = {}
		for k, v in pairs(node) do
			out[k] = build(v, path .. "." .. tostring(k), idx)
		end
		return out
	end

	return {
		-- generates one data table per sample_template slot (mirroring
		-- entry.fetcher's cache-array shape); call once per tick to get
		-- continuously-drifting values, or once for a static -s sample
		generate = function(sample_template)
			local out = {}
			for i, shape in ipairs(sample_template) do
				out[i] = build(shape, "s" .. i, 1)
			end
			return out
		end,
	}
end -- >}

return M

-- vim: filetype=lua foldmethod=marker foldmarker=>{,>}
