local Skynet = require "skynet"
local Conf = require "conf"
local Util = require "util"
require "bash"

local nodename = require "publish.nodename"

local function publish(pconf, confname)
    if Conf.remote_host then
        Skynet.error("请在开发模式下发布!")
        return
    end
    Skynet.error("正在发布"..confname)
    Skynet.error("创建临时目录")
    bash "rm -rf ../tmp"

    local tmp = "../tmp/"..confname
    local bewater = "../bewater"
    local projname = string.match(bash("cd %s && pwd", Conf.workspace), "(%w+)\n")
    local proj = tmp.."/proj/"..projname
    bash("mkdir -p %s", tmp)
    bash("cd %s && mkdir -p skynet bewater proj/%s", tmp, projname)
    bash("cp -r skynet luaclib lualib service cservice %s/skynet", tmp)
    bash("cp -r %s/lualib %s/luaclib %s/service %s/bewater", bewater, bewater, bewater, tmp)
    bash("cp -r %s/etc %s/script %s/service %s/shell %s",
        Conf.workspace, Conf.workspace, Conf.workspace, Conf.workspace, proj)

    -- 配置文件
    pconf.workspace = string.format("%s/proj/%s/", pconf.remote_path, projname)
    local str = "return ".. Util.dump(pconf)
    local file = io.open(proj.."/script/conf.lua", "w+")
    file:write(str)
    file:close()

    file = io.open(proj.."/etc/"..pconf.etcname..".cfg", "r")
    str = file:read("*a")
    file:close()
    str = string.gsub(str, "workspace = [^\n]+", string.format('workspace = "../proj/%s/"', projname))
    str = string.gsub(str, "clustername = [^\n]+", string.format('clustername = "%s"', pconf.clustername))
    file = io.open(proj.."/etc/"..pconf.etcname..".cfg", "w")
    file:write(str)
    file:close()

    -- 启动脚本
    str = string.format("sh %s/proj/%s/shell/run.sh %s", pconf.remote_path, projname, pconf.etcname)
    bash("echo %s > %s/run.sh", str, tmp)
    bash("chmod 775 %s/run.sh", tmp)

    -- 停机脚本
    str = string.format("sh %s/proj/%s/shell/kill.sh %s", pconf.remote_path, projname, pconf.etcname)
    bash("echo %s > %s/kill.sh", str, tmp)
    bash("chmod 775 %s/kill.sh", tmp)

    -- 日志脚本
    str = string.format("sh %s/proj/%s/shell/log.sh %s", pconf.remote_path, projname, pconf.clustername)
    bash("echo %s > %s/log.sh", str, tmp)
    bash("chmod 775 %s/log.sh", tmp)

    if string.match(pconf.remote_host, "localhost") then
        -- 发布到本地
        Skynet.error("正在关闭远程服务器")
        bash("sh %s/kill.sh", pconf.remote_path)
        Skynet.sleep(200)
        bash("mkdir -p %s", pconf.remote_path)
        Skynet.error("正在推送到远程服务器")
        bash("cp -r %s/* %s ", tmp, pconf.remote_path)
        Skynet.error("正在重新启动远程服务器")
        bash("sh %s/run.sh", pconf.remote_path)
    else
        -- 发布到远程
        Skynet.error("正在关闭远程服务器")
        bash("ssh -p %s %s sh %s/kill.sh", pconf.remote_port, pconf.remote_host, pconf.remote_path)
        Skynet.sleep(200)
        bash("ssh -p %s %s mkdir -p %s", pconf.remote_port, pconf.remote_host, pconf.remote_path)
        Skynet.error("正在推送到远程服务器")
        bash("scp -rpB -P %s %s/* %s:%s ", pconf.remote_port, tmp, pconf.remote_host, pconf.remote_path)
        Skynet.error("正在重新启动远程服务器")
        bash("ssh -p %s %s sh %s/run.sh", pconf.remote_port, pconf.remote_host, pconf.remote_path)
    end

    -- 删除临时目录
    bash "rm -rf ../tmp"
    Skynet.error("发布完成")
end

Skynet.start(function()
    if nodename == "all" then
        local ret = bash("cd %s/script/publish/conf && ls", Conf.workspace)
        for filename in string.gmatch(ret, "([^\n]+).lua") do
            local pconf = require("publish.conf."..filename)
            publish(pconf, filename)
        end
    else
        local pconf = require("publish.conf."..nodename)
        publish(pconf, nodename)
    end
end)
