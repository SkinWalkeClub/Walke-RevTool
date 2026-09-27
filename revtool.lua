-- revtool: reverse a roblox game fast. spy on remotes and export the calls as
-- runnable lua, query the datamodel, snapshot and diff what changed. mit.

local R = {}
R._VERSION = "0.1.0"

local env = (getgenv and getgenv()) or _G
local function res(p)
	for _, r in ipairs({ env, _G }) do
		local c = r
		for s in p:gmatch("[^.]+") do if type(c) ~= "table" then c = nil break end c = c[s] end
		if c ~= nil then return c end
	end
end
local function first(...)
	for _, n in ipairs({ ... }) do local f = res(n) if type(f) == "function" then return f end end
end

local tof = typeof or function(v) return type(v) end
local fmt = string.format
local ins, cat = table.insert, table.concat
local unpk = table.unpack or unpack

-- value -> runnable lua source
local function q(s) return fmt("%q", s) end

local function pathOf(o)
	local ok, full = pcall(function() return o:GetFullName() end)
	if not ok or type(full) ~= "string" then return "nil --[[instance]]" end
	local segs = {}
	for s in full:gmatch("[^.]+") do segs[#segs + 1] = s end
	if #segs == 0 then return "game" end
	local e = fmt('game:GetService(%s)', q(segs[1]))
	for i = 2, #segs do e = e .. fmt(':FindFirstChild(%s)', q(segs[i])) end
	return e
end

local function dump(v, seen, d)
	seen = seen or {}
	d = d or 0
	local t = tof(v)
	if t == "string" then return q(v) end
	if t == "number" then
		if v ~= v then return "0/0" end
		if v == math.huge then return "math.huge" end
		if v == -math.huge then return "-math.huge" end
		return fmt("%.14g", v)
	end
	if t == "boolean" then return tostring(v) end
	if t == "nil" then return "nil" end
	if t == "Vector3" then return fmt("Vector3.new(%.14g, %.14g, %.14g)", v.X, v.Y, v.Z) end
	if t == "Vector2" then return fmt("Vector2.new(%.14g, %.14g)", v.X, v.Y) end
	if t == "Color3" then return fmt("Color3.new(%.14g, %.14g, %.14g)", v.R, v.G, v.B) end
	if t == "UDim" then return fmt("UDim.new(%.14g, %d)", v.Scale, v.Offset) end
	if t == "UDim2" then return fmt("UDim2.new(%.14g, %d, %.14g, %d)", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset) end
	if t == "NumberRange" then return fmt("NumberRange.new(%.14g, %.14g)", v.Min, v.Max) end
	if t == "BrickColor" then return fmt("BrickColor.new(%s)", q(tostring(v.Name or v))) end
	if t == "EnumItem" then return tostring(v) end
	if t == "CFrame" then
		local c = { v:GetComponents() }
		local o = {}
		for i = 1, #c do o[i] = fmt("%.14g", c[i]) end
		return "CFrame.new(" .. cat(o, ", ") .. ")"
	end
	if t == "Instance" then return pathOf(v) end
	if t == "table" then
		if seen[v] or d > 6 then return "{--[[...]]}" end
		seen[v] = true
		local arr, out, n = true, {}, 0
		for k in pairs(v) do n = n + 1 if type(k) ~= "number" then arr = false end end
		if arr and n == #v then
			for i = 1, #v do out[#out + 1] = dump(v[i], seen, d + 1) end
		else
			for k, val in pairs(v) do
				local key = type(k) == "string" and (k:match("^[%a_][%w_]*$") and k or "[" .. q(k) .. "]") or "[" .. dump(k, seen, d + 1) .. "]"
				out[#out + 1] = key .. " = " .. dump(val, seen, d + 1)
			end
		end
		seen[v] = nil
		return "{" .. cat(out, ", ") .. "}"
	end
	return "nil --[[" .. t .. "]]"
end
R.dump = dump

-- remote spy
local spy = { log = {}, ignore = {}, max = 500, onCall = nil, hooked = false }
R.spy = spy

function spy._record(remote, method, args)
	local nm = "?"
	pcall(function() nm = remote.Name end)
	if spy.ignore[nm] then return end
	local e = { remote = remote, method = method, args = args, name = nm, t = os.clock and os.clock() or 0 }
	pcall(function() e.path = remote:GetFullName() end)
	ins(spy.log, e)
	if #spy.log > spy.max then table.remove(spy.log, 1) end
	if spy.onCall then pcall(spy.onCall, e) end
	return e
end

function spy.export(e)
	local a = {}
	for i = 1, #e.args do a[i] = dump(e.args[i]) end
	return pathOf(e.remote) .. ":" .. e.method .. "(" .. cat(a, ", ") .. ")"
end

function spy.dumpAll()
	local o = {}
	for _, e in ipairs(spy.log) do o[#o + 1] = spy.export(e) end
	return cat(o, "\n")
end

function spy.refire(e)
	return select(2, pcall(function() return e.remote[e.method](e.remote, unpk(e.args)) end))
end

function spy.clear() spy.log = {} end

function spy.start()
	if spy.hooked then return true end
	local hookmm = first("hookmetamethod")
	local getnc = first("getnamecallmethod")
	if not (hookmm and getnc) then
		local grm = first("getrawmetatable")
		local sro = first("setreadonly")
		local ncc = first("newcclosure") or function(f) return f end
		if not (grm and sro) then return false, "needs hookmetamethod or getrawmetatable+setreadonly" end
		local mt = grm(game)
		local old = mt.__namecall
		sro(mt, false)
		mt.__namecall = ncc(function(self, ...)
			local m = getnc and getnc() or ""
			if (m == "FireServer" or m == "InvokeServer") and tof(self) == "Instance" then
				local ok = pcall(function() return self:IsA("RemoteEvent") or self:IsA("RemoteFunction") end)
				if ok then spy._record(self, m, { ... }) end
			end
			return old(self, ...)
		end)
		sro(mt, true)
		spy._old = old
		spy.hooked = true
		return true
	end
	local old
	old = hookmm(game, "__namecall", function(self, ...)
		local m = getnc()
		if (m == "FireServer" or m == "InvokeServer") and tof(self) == "Instance" then
			local ok = pcall(function() return self:IsA("RemoteEvent") or self:IsA("RemoteFunction") end)
			if ok then spy._record(self, m, { ... }) end
		end
		return old(self, ...)
	end)
	spy._old = old
	spy.hooked = true
	return true
end

-- datamodel query
local function match(o, f)
	if f.class and not o:IsA(f.class) then return false end
	if f.name and o.Name ~= f.name then return false end
	if f.tag then local ok, has = pcall(function() return o:HasTag(f.tag) end) if not (ok and has) then return false end end
	if f.attr then for k, v in pairs(f.attr) do if o:GetAttribute(k) ~= v then return false end end end
	if f.predicate and not f.predicate(o) then return false end
	return true
end

local function query(root, f)
	f = f or {}
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do if match(d, f) then out[#out + 1] = d end end
	return out
end
R.query = query
R.q = query

function R.qfirst(root, f)
	for _, d in ipairs(root:GetDescendants()) do if match(d, f) then return d end end
end
function R.byClass(root, c) return query(root, { class = c }) end
function R.byName(root, n) return query(root, { name = n }) end
function R.byTag(root, t) return query(root, { tag = t }) end
function R.byAttr(root, k, v) return query(root, { attr = { [k] = v } }) end

-- snapshot + diff
local SNAPPROPS = {
	"Name", "Anchored", "CanCollide", "Transparency", "Reflectance", "Material",
	"Color", "Size", "Position", "CFrame", "Orientation", "Value", "Text",
	"Visible", "Enabled", "BackgroundColor3", "Health", "MaxHealth", "WalkSpeed",
}

local function veq(a, b)
	if a == b then return true end
	local ok, r = pcall(function() return a == b end)
	return ok and r
end

function R.snapshot(root, props)
	props = props or SNAPPROPS
	local snap = {}
	for _, d in ipairs(root:GetDescendants()) do
		local key
		pcall(function() key = d:GetFullName() end)
		if key then
			local rec = { class = d.ClassName, p = {} }
			for _, pn in ipairs(props) do
				local ok, v = pcall(function() return d[pn] end)
				if ok and v ~= nil and type(v) ~= "function" then rec.p[pn] = v end
			end
			snap[key] = rec
		end
	end
	return snap
end

function R.diff(a, b)
	local added, removed, changed = {}, {}, {}
	for k, rb in pairs(b) do
		local ra = a[k]
		if not ra then
			added[#added + 1] = { path = k, class = rb.class }
		else
			for pn, vb in pairs(rb.p) do
				if not veq(ra.p[pn], vb) then
					changed[#changed + 1] = { path = k, prop = pn, from = ra.p[pn], to = vb }
				end
			end
		end
	end
	for k, ra in pairs(a) do
		if not b[k] then removed[#removed + 1] = { path = k, class = ra.class } end
	end
	return { added = added, removed = removed, changed = changed }
end

function R.printDiff(d)
	print("[revtool] +" .. #d.added .. " -" .. #d.removed .. " ~" .. #d.changed)
	for _, x in ipairs(d.added) do print("  + " .. x.path .. " (" .. x.class .. ")") end
	for _, x in ipairs(d.removed) do print("  - " .. x.path .. " (" .. x.class .. ")") end
	for _, x in ipairs(d.changed) do
		print("  ~ " .. x.path .. "." .. x.prop .. ": " .. dump(x.from) .. " -> " .. dump(x.to))
	end
end

return R
