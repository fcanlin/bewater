local Skynet    = require "skynet"
local Packet    = require "sock.packet"
local Util      = require "util"
local Protobuf  = require "protobuf"
local Errcode   = require "def.errcode"

local player_path = ...
local player_t = require(player_path)

local WATCHDOG
local GATE
local MAX_COUNT

local CMD = {}
local fd2player = {}
local uid2player = {}
local count = 0

Skynet.register_protocol {
	name = "client",
	id = Skynet.PTYPE_CLIENT,
	unpack = function (buff, sz)
		return Packet.unpack(buff, sz)
	end,
	dispatch = function (fd, _, ...)
		Skynet.ignoreret()	-- session is fd, don't call Skynet.ret
        local player = assert(fd2player[fd], "player not exist, fd:"..fd)
        player.net:recv(...)
	end
}

function CMD.init(gate, watchdog, max_count, proto)
    GATE = assert(gate)
    WATCHDOG = assert(watchdog)
    MAX_COUNT = max_count or 100
    Protobuf.register_file(proto)
end

function CMD.stop()
    for _, player in pairs(uid2player) do
        Util.try(function()
            player:offline()
        end)
    end
    Skynet.call(WATCHDOG, "lua", "free_agent", Skynet.self())
end

-- from watchdog
function CMD.new_player(fd, ip)
    local player = player_t.new()
    player.net:init(WATCHDOG, GATE, Skynet.self(), fd, ip)
    fd2player[fd] = player
	Skynet.call(GATE, "lua", "forward", fd)
    count = count + 1
    return count >= MAX_COUNT
end

-- from watchdog
function CMD.socket_close(uid, fd)
    local player = assert(fd2player[fd], fd)
    Skynet.error("&&&&&&&& socket_close", player, player.net:get_fd(), fd)    
    if player.net:get_fd() == fd then
        player:offline()
    end
    fd2player[fd] = nil
end

-- from player
function CMD.player_online(uid, fd)
    local player = assert(fd2player[fd])
    Skynet.error("&&&&&& agent player_online", player, uid, fd)
    uid2player[uid] = player
end

-- from player
function CMD.free_player(uid)
    Skynet.error("&&&&& agent free player", uid2player[uid])
    uid2player[uid] = nil
    if count == MAX_COUNT then
        Skynet.call(WATCHDOG, "lua", "set_free", Skynet.self())
    end
    count = count - 1
end

function CMD.reconnect(fd, uid, csn, ssn)
    local player = uid2player[uid]
    if not player then
        return
    end
    local old_fd = player.net:get_fd()
    if player.net:reconnect(fd, csn, ssn) then
        --fd2player[old_fd] = nil
        fd2player[fd] = player
	    Skynet.call(GATE, "lua", "forward", fd)
        return player:base_data()
    end
end

function CMD.kick(uid)
    local player = uid2player[uid]
    if player then
        player:kickout()
        uid2player[uid] = nil
    end
end

local function check_timeout()
    for _, player in pairs(uid2player) do
        if player.check_timeout then
            Util.try(function()
                player:check_timeout()
            end)
        end
    end
end

Skynet.start(function()
    Skynet.dispatch("lua", function(_, _, arg1, arg2, arg3, ...)
        local f = CMD[arg1]
        if f then
            Util.ret(f(arg2, arg3, ...))
        else
            --local player = assert(uid2player[arg1], string.format("%s %s %s", arg1, arg2, arg3))
            local player = uid2player[arg1]
            if not player then
                -- todo fix this bug
                return Util.ret()
            end
            local module = assert(player[arg2], arg2)
            if type(module) == "function" then
                Util.ret(module(player, arg3, ...))
            else
                Util.ret(module[arg3](module, ...))
            end
        end
    end)

    -- 定时检查超时，一秒误差，如需要精准的触发，使用日程表schedule
    Skynet.fork(function()
        while true do
            check_timeout()
            Skynet.sleep(100)
        end
    end)
end)
