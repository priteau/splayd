--[[
	Splayd
	Copyright 2006 - 2009 Lorenzo Leonini (University of Neuchâtel)
	http://www.splay-project.org
]]

local events = require"splay.events"
local socket = require"splay.socket"
local log = require"splay.log"

local print = print
local type = type
local pairs = pairs

module("splay.net")

_COPYRIGHT   = "Copyright 2006 - 2009 Lorenzo Leonini (University of Neuchâtel)"
_DESCRIPTION = "Network related functions, objects, .."
_VERSION     = 0.6

--[[ DEBUG ]]--
l_o = log.new(3, "[".._NAME.."]")

settings = {
}

local _s_s = {}

-- Additionnal socket functions
function server(port, handler, max, filter, backlog)

	-- compatibility when 2 first parameters where swapped
	if type(port) == "function" then
		local tmp = port
		port = handler
		handler = tmp
	end

	-- compatibility when filter was no_close
	local no_close = false
	if filter and type(filter) ~= "function" then
		no_close = filter
		filter = nil
		l_o:warn("net.server() option 'no_close' is no more supported, check doc")
	end

	if type(port) == "table" then
		port = port.port
	end
	local s, err = socket.bind("*", port, backlog)
	if not s then
		l_o:warn("server bind("..port.."): "..err)
		return nil, err
	end
	if _s_s[port] then
		return nil, "server still not stopped"
	end
	_s_s[port] = {s = s, clients = {}}
	return events.thread(function()
		local s_s
		if max then s_s = events.semaphore(max) end
		while true do
			if s_s then s_s:lock() end
			local sc, err = s:accept()
			if sc then
				local ok = true

				if filter then
					local ip, port = sc:getpeername()
					ok = filter(ip, port)
					if not ok then
						l_o:notice("Refused by filter", ip, port)
					end
				end

				if ok then
					_s_s[port].clients[sc] = true
					events.thread(function()
						handler(sc)
						if _s_s[port] then
							_s_s[port].clients[sc] = nil
						end
						if not no_close then
							sc:close()
						end
						if s_s then s_s:unlock() end
					end)
				else
					sc:close()
					if s_s then s_s:unlock() end
				end
			else
				if s_s then s_s:unlock() end
				if _s_s[port].stop then
					l_o:warn("server on port "..port.." stopped")
					_s_s[port] = nil
					break
				else
					l_o:warn("server accept(): "..err)
				end
				events.yield()
			end
		end
	end)
end

function stop_server(port, kill_clients)
	if type(port) == "table" then
		port = port.port
	end
	if _s_s[port] then
		_s_s[port].s:close()
		if kill_clients then
			for s, _ in pairs(_s_s[port].clients) do
				s:close()
			end
		end
		_s_s[port].stop = true
		-- Avoid a server() just after stop_server()
		-- (let accept() the time to "crash" and to close/clean the port)
		events.sleep(0.1)
	end
end

--[[ Generate a new UDP object:
-- - A server with an handler or generating events
-- - A socket to send datagrams
-- Only use one socket.
--]]
function udp_helper(port, handler)
	if type(port) == "function" then
		local tmp = port
		port = handler
		handler = tmp
	end
	if type(port) == "table" then
		port = port.port
	end
	local u, err, r = {}
	u.s, err = socket.udp()
	if not u.s then return nil, err end
	r, err = u.s:setsockname("*", port)
	if not r then return nil, err end

	u.server = events.thread(function()
		while true do
			local data, ip, port = u.s:receivefrom()
			if data then
				if handler then
					events.thread(function() handler(data, ip, port) end)
				else
					events.fire("udp:"..port, {data, ip, port})
				end
			else
				-- impossible without timeout...
			end
		end
	end)
	
	return u
end


