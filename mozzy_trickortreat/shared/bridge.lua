--[[
    MOZZY TRICK OR TREAT - shared/bridge.lua
    Everything framework / dispatch specific lives here so the main logic stays clean.
    To support another dispatch, add a function to Dispatch.systems (client side).
]]

IS_SERVER = IsDuplicityVersion()

Utils = {}
Bridge = {}

---------------------------------------------------------------------------
-- Utils (shared)
---------------------------------------------------------------------------
function Utils.debug(...)
    if Config.Debug then print(('^5[mozzy_trickortreat]^7 %s'):format(table.concat({ ... }, ' '))) end
end

function Utils.range(t)
    if type(t) == 'number' then return t end
    if not t then return 0 end
    local a, b = t.min or 0, t.max or t.min or 0
    if b < a then a, b = b, a end
    if math.type(a) == 'integer' and math.type(b) == 'integer' then return math.random(a, b) end
    return a + math.random() * (b - a)
end

function Utils.roll(percent)
    percent = tonumber(percent) or 0
    if percent <= 0 then return false end
    if percent >= 100 then return true end
    return math.random() * 100 < percent
end

--- Weighted pick. entries: array of tables with `weight` (or `chance`). weightFn optionally alters weight.
function Utils.weighted(entries, weightFn)
    local total = 0
    for i = 1, #entries do
        local w = entries[i].weight or entries[i].chance or 0
        if weightFn then w = weightFn(entries[i], w) end
        total += math.max(w, 0)
    end
    if total <= 0 then return nil end
    local r = math.random() * total
    for i = 1, #entries do
        local w = entries[i].weight or entries[i].chance or 0
        if weightFn then w = weightFn(entries[i], w) end
        w = math.max(w, 0)
        if r < w then return entries[i] end
        r -= w
    end
    return entries[#entries]
end

function Utils.pick(list) return list[math.random(#list)] end

--- Normalised locations: Locations[id] = { coords = vector3, label = string? }
Locations = {}
for i, entry in ipairs(Config.TrickOrTreatLocations) do
    if type(entry) == 'vector3' then
        Locations[i] = { coords = entry }
    elseif type(entry) == 'table' and entry.coords then
        Locations[i] = { coords = vector3(entry.coords.x, entry.coords.y, entry.coords.z), label = entry.label }
    end
end

function Utils.isSeasonActive()
    local s = Config.Season
    if not s or not s.enabled then return true end
    local now = os.date('*t')
    local cur = now.month * 100 + now.day
    local from = s.startMonth * 100 + s.startDay
    local to = s.endMonth * 100 + s.endDay
    if from <= to then return cur >= from and cur <= to end
    return cur >= from or cur <= to -- wraps over new year
end

---------------------------------------------------------------------------
-- SERVER BRIDGE (Qbox)
---------------------------------------------------------------------------
if IS_SERVER then
    function Bridge.GetPlayer(src) return exports.qbx_core:GetPlayer(src) end

    function Bridge.GetCitizenId(src)
        local p = Bridge.GetPlayer(src)
        return p and p.PlayerData.citizenid
    end

    function Bridge.IsDead(src)
        local p = Bridge.GetPlayer(src)
        if not p then return true end
        local md = p.PlayerData.metadata
        return md.isdead or md.inlaststand or false
    end

    function Bridge.GetMoney(src, moneyType)
        local value = exports.qbx_core:GetMoney(src, moneyType)
        return tonumber(value) or 0
    end
    function Bridge.AddMoney(src, moneyType, amount, reason) return exports.qbx_core:AddMoney(src, moneyType, amount, reason) end
    function Bridge.RemoveMoney(src, moneyType, amount, reason) return exports.qbx_core:RemoveMoney(src, moneyType, amount, reason) end

    -- exports can return *no value* (not nil) for missing metadata, so always capture into a local
    function Bridge.GetMeta(src, key)
        local value = exports.qbx_core:GetMetadata(src, key)
        return value
    end
    function Bridge.SetMeta(src, key, value) return exports.qbx_core:SetMetadata(src, key, value) end

    function Bridge.Notify(src, msg, nType, duration, title)
        TriggerClientEvent('ox_lib:notify', src, {
            title = title or '🎃 Trick or Treat', description = msg, type = nType or 'inform',
            duration = duration or 6000, icon = 'ghost', iconColor = '#ff7a18',
        })
    end

    function Bridge.RegisterUsable(item, cb)
        exports.qbx_core:CreateUseableItem(item, cb)
    end

    --- Players that should receive the 'qbx' fallback alert
    function Bridge.GetPoliceSources()
        local list = {}
        local jobs = {}
        for _, j in ipairs(Config.PoliceAlert.jobs or {}) do jobs[j] = true end
        for src, player in pairs(exports.qbx_core:GetQBPlayers()) do
            local job = player.PlayerData.job
            if job and job.onduty and (jobs[job.name] or job.type == Config.PoliceAlert.jobType) then
                list[#list + 1] = src
            end
        end
        return list
    end

    --- Optional server-side logging hook (swap for your logger / webhook)
    function Bridge.Log(src, message)
        if Config.Security.logExploits then
            print(('^1[mozzy_trickortreat]^7 [%s] %s : %s'):format(src, GetPlayerName(src) or '?', message))
        end
    end

    return
end

---------------------------------------------------------------------------
-- CLIENT BRIDGE
---------------------------------------------------------------------------
function Bridge.Notify(msg, nType, duration, title)
    lib.notify({
        title = title or '🎃 Trick or Treat', description = msg, type = nType or 'inform',
        duration = duration or 6000, icon = 'ghost', iconColor = '#ff7a18',
    })
end

Dispatch = { systems = {} }

-- NOTE: dispatch exports change between versions - verify these against the version you run.
Dispatch.systems['ps-dispatch'] = function(d)
    exports['ps-dispatch']:CustomAlert({
        coords = d.coords, message = d.title, dispatchCode = d.code, code = d.code,
        description = d.description, street = d.street, icon = 'fas fa-mask',
        priority = 2, radius = 0, sprite = d.blip.sprite, color = d.blip.color,
        scale = d.blip.scale, length = 3, jobs = { 'leo' }, alertTime = nil,
    })
end

Dispatch.systems['cd_dispatch'] = function(d)
    TriggerServerEvent('cd_dispatch:AddNotification', {
        job_table = Config.PoliceAlert.jobs, coords = d.coords, title = d.code .. ' - ' .. d.title,
        message = ('%s | %s'):format(d.description, d.street), flash = 0,
        unique_id = tostring(math.random(0000000, 9999999)), sound = 1,
        blip = { sprite = d.blip.sprite, scale = d.blip.scale, colour = d.blip.color, flashes = false, text = d.title, time = 5, radius = 0 },
    })
end

Dispatch.systems['qs-dispatch'] = function(d)
    TriggerServerEvent('qs-dispatch:server:CreateDispatchCall', {
        job = Config.PoliceAlert.jobs, callLocation = d.coords,
        callCode = { code = d.code, snippet = d.title }, message = d.description .. ' | ' .. d.street,
        flashes = false, image = nil,
        blip = { sprite = d.blip.sprite, scale = d.blip.scale, colour = d.blip.color, flashes = true, text = d.title, time = (d.blip.time or 60) * 1000 },
    })
end

Dispatch.systems['core_dispatch'] = function(d)
    for _, job in ipairs(Config.PoliceAlert.jobs) do
        TriggerServerEvent('core_dispatch:addCall', d.code, d.title,
            { { icon = 'fa-road', info = d.street }, { icon = 'fa-mask', info = d.suspects or 'Unknown' } },
            { d.coords.x, d.coords.y, d.coords.z }, job, 5000, d.blip.sprite, d.blip.color)
    end
end

Dispatch.systems['rcore_dispatch'] = function(d)
    TriggerServerEvent('rcore_dispatch:server:sendAlert', {
        code = d.code, default_priority = 'high', coords = d.coords, job = Config.PoliceAlert.jobs,
        text = d.description, type = 'alerts',
        blip_time = d.blip.time or 60,
        blip = { sprite = d.blip.sprite, colour = d.blip.color, scale = d.blip.scale, text = d.title, flashes = false, radius = 0 },
    })
end

-- Fill this in for any other dispatch resource
Dispatch.systems['custom'] = function(d)
    print('[mozzy_trickortreat] custom dispatch not configured', json.encode(d))
end

-- 'qbx' = built-in fallback (server notifies on-duty police + temporary blip)
Dispatch.systems['qbx'] = function(d)
    TriggerServerEvent('mozzy_tot:server:fallbackDispatch', d)
end

local autoOrder = { 'ps-dispatch', 'cd_dispatch', 'qs-dispatch', 'core_dispatch', 'rcore_dispatch' }

function Dispatch.send(d)
    local system = Config.PoliceAlert.system
    if system == 'auto' then
        system = 'qbx'
        for _, res in ipairs(autoOrder) do
            if GetResourceState(res) == 'started' then system = res break end
        end
    end
    local fn = Dispatch.systems[system] or Dispatch.systems.qbx
    local ok, err = pcall(fn, d)
    if not ok then
        Utils.debug('dispatch failed for', system, tostring(err), '- falling back to qbx')
        Dispatch.systems.qbx(d)
    end
end
