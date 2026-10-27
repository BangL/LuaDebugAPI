-- Live debug API (file IPC).
-- Client writes io/cmd.lua (atomically via rename), mod executes it, writes io/res.txt.
-- Chunk env: _G; extra locals: out(...) appends to the result. A chunk starting
-- with an expression is tried as "return <code>" first.

if LuaDebugAPI and LuaDebugAPI.loaded then
	return
end
LuaDebugAPI = LuaDebugAPI or {}
local L = LuaDebugAPI
L.loaded = true

L.dir = ModPath .. "io/"
L.cmd = L.dir .. "cmd.lua"
L.res = L.dir .. "res.txt"
L.interval = 0.1
L.max_depth = 3
L.max_items = 200
L.max_len = 200000
L.hb_file = L.dir .. "hb.txt"
L.hb_interval = 2
L.err_file = L.dir .. "errors.txt"
L.err_max = 200000
L.last_cmd = L.dir .. "last_cmd.txt"
L.running = L.dir .. "running"
L.session = os.time()

local t_acc = 0
local hb_acc = 0
local hb_frames, hb_sum, hb_max = 0, 0, 0
local hb_total = 0

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
	-- journal: if the command kills the game, we know which one it was
	L.put(L.last_cmd, os.date("%H:%M:%S") .. "\n" .. code)
	L.put(L.running, "1")
	local ok, r = (blt and blt.pcall or pcall)(L.run, code)
	os.remove(L.running)
	L.write(ok and r or "ERR internal: " .. tostring(r))
end

function L.put(path, text)
	local f = io.open(path, "wb")
	if f then
		f:write(text)
		f:close()
	end
end

-- heartbeat: key=value lines, replaced atomically
function L.heartbeat()
	local function try(fn)
		local ok, v = (blt and blt.pcall or pcall)(fn)
		return ok and v ~= nil and tostring(v) or "?"
	end
	local lines = {
		"t=" .. os.time(),
		"session=" .. L.session,
		"clock=" .. string.format("%.2f", os.clock()),
		"frames=" .. hb_total,
		"fps_dt_avg=" .. string.format("%.4f", hb_frames > 0 and hb_sum / hb_frames or 0),
		"dt_max=" .. string.format("%.4f", hb_max),
		"state=" .. try(function() return game_state_machine:current_state_name() end),
		"level=" .. try(function() return Global.level_data and Global.level_data.level_id end),
		"job=" .. try(function() return managers.raid_job:current_job_id() end),
		"pos=" .. try(function() return managers.player:player_unit():position() end),
	}
	hb_frames, hb_sum, hb_max = 0, 0, 0
	local tmp = L.hb_file .. ".tmp"
	L.put(tmp, table.concat(lines, "\n") .. "\n")
	os.remove(L.hb_file)
	os.rename(tmp, L.hb_file)
end

-- error ring: log() lines that look like errors, appended to io/errors.txt
function L.log_error(text)
	local f = io.open(L.err_file, "ab")
	if not f then
		return
	end
	f:write(os.date("%H:%M:%S ") .. text .. "\n")
	if f:seek("end") > L.err_max then
		f:close()
		L.put(L.err_file, "<truncated>\n")
		return
	end
	f:close()
end

function L.install_log_hook()
	local orig = _G.log
	if not orig or L.log_orig == orig then
		return
	end
	L.log_orig = orig
	_G.log = function(...)
		local msg = ...
		if type(msg) == "string" and (msg:find("rror", 1, true) or msg:find("stack traceback", 1, true)) then
			L.log_error(msg)
		end
		return orig(...)
	end
end

local function tick(self, t, dt)
	dt = dt or 0
	hb_total = hb_total + 1
	hb_frames = hb_frames + 1
	hb_sum = hb_sum + dt
	if dt > hb_max then
		hb_max = dt
	end
	hb_acc = hb_acc + dt
	if hb_acc >= L.hb_interval then
		hb_acc = 0
		L.heartbeat()
	end
	t_acc = t_acc + dt
	if t_acc < L.interval then
		return
	end
	t_acc = 0
	L.poll()
end

Hooks:PostHook(Setup, "update", "LuaDebugAPI_update", tick)
-- the paused game (e.g. the pause menu in singleplayer) only runs paused_update
if Setup.paused_update then
	Hooks:PostHook(Setup, "paused_update", "LuaDebugAPI_paused_update", tick)
end

L.install_log_hook()
L.log_error("---- session " .. L.session)

-- a command that reloaded Lua (or crashed the game) never got an answer: tell the client
local f = io.open(L.running, "rb")
if f then
	f:close()
	os.remove(L.running)
	L.write("OK RELOADED (new Lua state; or the game crashed during the command, see last_cmd.txt)")
end

log("[LuaDebugAPI] ready: " .. L.dir)
