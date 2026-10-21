-- Live debug API (file IPC).
-- Client writes io/cmd.lua (atomically via rename), mod executes it, writes io/res.txt.
-- Chunk env: _G; extra locals: out(...) appends to the result. A chunk starting
-- with an expression is tried as "return <code>" first.

LuaDebugAPI = LuaDebugAPI or {}
local L = LuaDebugAPI

L.dir = ModPath .. "io/"
L.cmd = L.dir .. "cmd.lua"
L.res = L.dir .. "res.txt"
L.interval = 0.05
L.max_depth = 3
L.max_items = 200
L.max_len = 200000

local t_acc = 0

function L.serialize(v, depth, seen)
	local tv = type(v)
	if tv == "string" then
		return string.format("%q", v)
	elseif tv ~= "table" then
		-- userdata (Vector3, Unit, Idstring, ...) -> tostring
		return tostring(v)
	end
	seen = seen or {}
	if seen[v] then
		return "<cycle>"
	end
	depth = depth or 0
	if depth >= L.max_depth then
		return "{...}"
	end
	seen[v] = true
	local parts, n = {}, 0
	for k, val in pairs(v) do
		n = n + 1
		if n > L.max_items then
			parts[#parts + 1] = "..."
			break
		end
		local ks = type(k) == "string" and k or "[" .. tostring(k) .. "]"
		parts[#parts + 1] = ks .. " = " .. L.serialize(val, depth + 1, seen)
	end
	seen[v] = nil
	return "{" .. table.concat(parts, ", ") .. "}"
end

function L.write(text)
	if #text > L.max_len then
		text = text:sub(1, L.max_len) .. "\n<truncated>"
	end
	local tmp = L.res .. ".tmp"
	local f = io.open(tmp, "wb")
	if not f then
		return
	end
	f:write(text)
	f:close()
	os.remove(L.res)
	os.rename(tmp, L.res)
end

function L.run(code)
	local lines = {}
	local function out(...)
		local t = {}
		for i = 1, select("#", ...) do
			t[i] = tostring((select(i, ...)))
		end
		lines[#lines + 1] = table.concat(t, "\t")
	end

	local fn = loadstring("return " .. code, "=ldb")
	if not fn then
		local err
		fn, err = loadstring(code, "=ldb")
		if not fn then
			return "ERR syntax: " .. tostring(err)
		end
	end
	local env = setmetatable({ out = out }, { __index = _G, __newindex = _G })
	setfenv(fn, env)

	-- capture log() while running
	local orig_log = _G.log
	_G.log = function(...)
		out("[log]", ...)
		return orig_log(...)
	end
	local tb = debug and debug.traceback or tostring
	local function pack(...)
		return select("#", ...), { ... }
	end
	local n, res = pack((blt and blt.xpcall or xpcall)(fn, tb))
	_G.log = orig_log

	if not res[1] then
		lines[#lines + 1] = "ERR " .. tostring(res[2])
		return table.concat(lines, "\n")
	end
	local rets = {}
	for i = 2, n do
		rets[#rets + 1] = L.serialize(res[i])
	end
	lines[#lines + 1] = "OK " .. table.concat(rets, ", ")
	return table.concat(lines, "\n")
end

function L.poll()
	local f = io.open(L.cmd, "rb")
	if not f then
		return
	end
	local code = f:read("*a")
	f:close()
	os.remove(L.cmd)
	local ok, r = (blt and blt.pcall or pcall)(L.run, code)
	L.write(ok and r or "ERR internal: " .. tostring(r))
end

Hooks:PostHook(Setup, "update", "LuaDebugAPI_update", function(self, t, dt)
	t_acc = t_acc + (dt or 0)
	if t_acc < L.interval then
		return
	end
	t_acc = 0
	L.poll()
end)

log("[LuaDebugAPI] ready: " .. L.dir)
