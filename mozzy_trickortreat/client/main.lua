--[[
    MOZZY TRICK OR TREAT - client/main.lua
    Presentation only: animations, NPC tasks, screen effects and UI.
    The client never decides or reports a reward.
]]

local busy = false
local localPeds = {}       -- door NPCs (client-only, non-networked)
local houseBlips = {}
local Rob = nil            -- active robbery state
local High = nil           -- active laced candy effect

local _, ROBBER_GROUP = AddRelationshipGroup('MOZZY_TOT_ROBBERS')
local PLAYER_GROUP = `PLAYER`

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function isDead()
    return IsEntityDead(cache.ped) or IsPedDeadOrDying(cache.ped, true)
end

local function isNight()
    local n = Config.NightOnly
    if not n.enabled then return true end
    local h = GetClockHours()
    if n.startHour > n.endHour then return h >= n.startHour or h < n.endHour end
    return h >= n.startHour and h < n.endHour
end

local function canKnock()
    return Config.Enabled and not busy and not Rob and not isDead()
        and not cache.vehicle and not lib.progressActive()
end

local function getControl(ent, timeout)
    if not DoesEntityExist(ent) then return false end
    if NetworkHasControlOfEntity(ent) then return true end
    local limit = GetGameTimer() + (timeout or 1500)
    NetworkRequestControlOfEntity(ent)
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < limit do
        Wait(0)
        NetworkRequestControlOfEntity(ent)
    end
    return NetworkHasControlOfEntity(ent)
end

local function deleteLocalPed(ped)
    if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
    for i = #localPeds, 1, -1 do if localPeds[i] == ped then table.remove(localPeds, i) end end
end

local function playAnim(ped, dict, clip, flag, duration)
    if not dict then return end
    lib.requestAnimDict(dict)
    TaskPlayAnim(ped, dict, clip, 8.0, -8.0, duration or -1, flag or 0, 0, false, false, false)
    RemoveAnimDict(dict)
end

---------------------------------------------------------------------------
-- Target zones (lazy: only created near the player via lib.points grid)
---------------------------------------------------------------------------
local knock -- forward declaration
local makeAttack

local function createZone(point)
    point.zone = exports.ox_target:addSphereZone({
        coords = point.coords,
        radius = Config.Target.zoneRadius,
        debug = Config.Debug,
        options = {
            {
                name = ('mozzy_tot_%s'):format(point.houseId),
                label = Config.Target.label,
                icon = Config.Target.icon,
                iconColor = Config.Target.iconColor,
                distance = Config.Target.interactDistance,
                canInteract = canKnock,
                onSelect = function() knock(point.houseId) end,
            },
        },
    })
end

CreateThread(function()
    for id, house in pairs(Locations) do
        local point = lib.points.new({ coords = house.coords, distance = Config.Target.loadDistance, houseId = id })
        function point:onEnter() if not self.zone then createZone(self) end end
        function point:onExit()
            if self.zone then exports.ox_target:removeZone(self.zone) self.zone = nil end
        end

        if Config.Blips.enabled then
            local b = AddBlipForCoord(house.coords.x, house.coords.y, house.coords.z)
            SetBlipSprite(b, Config.Blips.sprite)
            SetBlipColour(b, Config.Blips.color)
            SetBlipScale(b, Config.Blips.scale)
            SetBlipAsShortRange(b, Config.Blips.shortRange)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(house.label or Config.Blips.label)
            EndTextCommandSetBlipName(b)
            houseBlips[#houseBlips + 1] = b
        end
    end
    Utils.debug(('registered %s trick-or-treat houses'):format(#Locations))
end)

---------------------------------------------------------------------------
-- Door NPC + tricks
---------------------------------------------------------------------------
local function spawnDoorNpc(model)
    local hash = joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    lib.requestModel(hash, 5000)
    local pos = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, Config.DoorNPC.distance, 0.0)
    local found, z = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 1.0, false)
    local ped = CreatePed(4, hash, pos.x, pos.y, found and z or (pos.z - 1.0), GetEntityHeading(cache.ped) + 180.0, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    TaskTurnPedToFaceEntity(ped, cache.ped, 1000)
    localPeds[#localPeds + 1] = ped
    return ped
end

local TrickFx = {}
function TrickFx.scare(npc)
    if npc then playAnim(npc, 'anim@mp_player_intcelebrationmale@jazz_hands', 'jazz_hands', 0, 2000) end
    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.35)
    AnimpostfxPlay('MenuMGSelectionIn', 800, false)
    playAnim(cache.ped, 'reaction@shove', 'shoved_back', 0, 1500)
end
function TrickFx.egg()
    AnimpostfxPlay('Dont_tazeme_bro', 0, true)
    SetTimeout(3500, function() AnimpostfxStop('Dont_tazeme_bro') end)
end
function TrickFx.trip() SetPedToRagdoll(cache.ped, 2500, 2500, 0, false, false, false) end
function TrickFx.shake() ShakeGameplayCam('LARGE_EXPLOSION_SHAKE', 0.2) end
function TrickFx.none() end

---------------------------------------------------------------------------
-- Robbery (client presentation of server-owned NPCs)
---------------------------------------------------------------------------
local isGun = function(weapon) return GetWeapontypeGroup(joaat(weapon)) ~= `GROUP_MELEE` and weapon ~= 'WEAPON_UNARMED' end

local function setRelationship(level)
    SetRelationshipBetweenGroups(level, ROBBER_GROUP, PLAYER_GROUP)
    SetRelationshipBetweenGroups(level, PLAYER_GROUP, ROBBER_GROUP)
end

local function forEachRobber(fn)
    if not Rob then return end
    for i, ped in ipairs(Rob.peds) do
        if ped and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then fn(ped, i) end
    end
end

local function setupRobber(ped, weapon, index, total)
    if not getControl(ped, 2000) then Utils.debug('no control of robber', index) end
    local n = Config.Robbery.npc
    SetEntityAsMissionEntity(ped, true, true)
    SetPedRandomComponentVariation(ped, 0)
    SetEntityMaxHealth(ped, math.max(100, n.health))
    SetEntityHealth(ped, math.max(100, n.health))
    SetPedAccuracy(ped, n.accuracy)
    SetPedCombatAbility(ped, n.combatAbility)
    SetPedCombatMovement(ped, n.combatMovement)
    SetPedCombatRange(ped, n.combatRange)
    SetPedCombatAttributes(ped, 46, true)  -- always fight
    SetPedCombatAttributes(ped, 5, true)   -- fight armed peds when unarmed
    SetPedFleeAttributes(ped, 0, false)
    SetPedRelationshipGroupHash(ped, ROBBER_GROUP)
    SetPedDropsWeaponsWhenDead(ped, false)
    SetPedCanRagdoll(ped, n.canBeKnockedDown)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    if weapon and weapon ~= 'WEAPON_UNARMED' then SetCurrentPedWeapon(ped, joaat(weapon), true) end

    local angle = (index / total) * math.pi * 2.0
    local r = Config.Robbery.surroundRadius
    TaskFollowToOffsetOfEntity(ped, cache.ped, math.cos(angle) * r, math.sin(angle) * r, 0.0, 2.0, -1, 0.8, true)

    local blip = AddBlipForEntity(ped)
    SetBlipSprite(blip, 270)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 0.6)
    Rob.blips[#Rob.blips + 1] = blip
end

makeAttack = function(ped)
    if not getControl(ped, 2500) then return false end
    SetPedRelationshipGroupHash(ped, ROBBER_GROUP)
    SetPedKeepTask(ped, true)
    SetPedCombatAttributes(ped, 46, true)   -- always fight
    SetPedCombatAttributes(ped, 0, true)    -- can use cover
    SetPedCombatAttributes(ped, 2, true)    -- can do drivebys / pursue in vehicles
    SetPedCombatAttributes(ped, 17, false)  -- don't flee from threats
    SetPedFleeAttributes(ped, 0, false)
    SetPedSeeingRange(ped, 150.0)
    SetPedHearingRange(ped, 150.0)
    SetPedAlertness(ped, 3)
    SetPedMoveRateOverride(ped, 1.15)
    ClearPedTasks(ped)
    TaskCombatPed(ped, cache.ped, 0, 16)
    return true
end

local function cleanupRobberyUi()
    if lib.getOpenContextMenu() == 'mozzy_tot_robbery' then lib.hideContext(false) end
    local open, text = lib.isTextUIOpen()
    if open and text and text:find('Cooperate') then lib.hideTextUI() end
end

local function endRobberyClient()
    if not Rob then return end
    for _, b in ipairs(Rob.blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    cleanupRobberyUi()
    setRelationship(3)
    Rob = nil
end

local function choose(choice)
    if not Rob or Rob.stage ~= 'demand' or Rob.choiceSent then return end
    Rob.choiceSent = true
    cleanupRobberyUi()
    lib.callback.await('mozzy_tot:server:robberyChoice', false, choice)
end

local function startDemand(seconds)
    if not Rob or Rob.stage == 'demand' then return end
    Rob.stage = 'demand'
    Rob.choiceSent = false

    forEachRobber(function(ped, i)
        if getControl(ped) then
            if isGun(Rob.weapons[i]) then
                TaskAimGunAtEntity(ped, cache.ped, -1, false)
            else
                TaskTurnPedToFaceEntity(ped, cache.ped, -1)
            end
        end
    end)
    if Rob.peds[1] and DoesEntityExist(Rob.peds[1]) then
        PlayPedAmbientSpeechNative(Rob.peds[1], 'GENERIC_INSULT_HIGH', 'SPEECH_PARAMS_FORCE_SHOUTED')
    end
    Bridge.Notify(Config.Robbery.messages.demand, 'error', 7000, '🔪 Robbery')

    lib.registerContext({
        id = 'mozzy_tot_robbery',
        title = '🔪 You\'re being robbed!',
        canClose = false,
        options = {
            { title = 'Give them money', description = 'Hand over some of your cash.', icon = 'money-bill-wave', iconColor = '#4caf50', onSelect = function() choose('money') end },
            { title = 'Give them candy', description = 'Let them take part of your haul.', icon = 'candy-cane', iconColor = '#ff7a18', onSelect = function() choose('candy') end },
            { title = 'Refuse', description = 'Stand your ground.', icon = 'hand', iconColor = '#e53935', onSelect = function() choose('refuse') end },
            { title = 'Run', description = 'Make a break for it.', icon = 'person-running', iconColor = '#29b6f6', onSelect = function() choose('run') end },
        },
    })
    lib.showContext('mozzy_tot_robbery')

    local startPos = GetEntityCoords(cache.ped)
    CreateThread(function()
        local deadline = GetGameTimer() + seconds * 1000
        while Rob and Rob.stage == 'demand' and not Rob.choiceSent do
            local left = math.ceil((deadline - GetGameTimer()) / 1000)
            if left <= 0 then choose('refuse') break end
            lib.showTextUI(('Cooperate! %ss'):format(left), { position = 'top-center', icon = 'stopwatch' })
            if #(GetEntityCoords(cache.ped) - startPos) > Config.Robbery.run.autoRunDistance then choose('run') break end
            Wait(250)
        end
        local open, text = lib.isTextUIOpen()
        if open and text and text:find('Cooperate') then lib.hideTextUI() end
    end)
end

local stageMessages = {
    refused = 'Wrong answer. They come at you!',
    broke = '"No cash? Big mistake."',
    nocandy = '"No candy?! Get him!"',
    timeout = 'You took too long - they attack!',
}

local function applyStage(stage, extra)
    if not Rob then return end
    extra = extra or {}
    if stage == 'demand' then return startDemand(Config.Robbery.cooperateTime) end
    if Rob.stage == stage then return end
    Rob.stage = stage
    cleanupRobberyUi()

    if stage == 'leaving' then
        if extra.amount then
            Bridge.Notify(extra.amount > 0 and ('They took $%s and walked off.'):format(extra.amount) or 'You were broke - they laughed and walked off.', 'error')
        elseif extra.stolen then
            Bridge.Notify(extra.stolen ~= '' and ('They grabbed: %s'):format(extra.stolen) or 'You had no candy. They shrug and leave.', 'error')
        elseif extra.letGo then
            Bridge.Notify('They laugh and let you run.', 'inform')
        end
        setRelationship(3)
        forEachRobber(function(ped)
            if getControl(ped) then
                ClearPedTasks(ped)
                TaskWanderStandard(ped, 10.0, 10)
            end
        end)
    elseif stage == 'hostile' or stage == 'chase' then
        Bridge.Notify(stage == 'chase' and 'You ran - they\'re coming after you!' or (stageMessages[extra.reason] or 'They attack!'), 'error', 6000, '🔪 Robbery')
        setRelationship(5)
        forEachRobber(function(ped) makeAttack(ped) end)
    elseif stage == 'defeated' then
        for _, b in ipairs(Rob.blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
        Rob.blips = {}
    end
end

local function startRobberyClient(data)
    Rob = { netIds = data.netIds, weapons = data.weapons, peds = {}, blips = {}, stage = 'approach', reported = {} }
    setRelationship(3)

    CreateThread(function()
        for i, netId in ipairs(data.netIds) do
            local limit = GetGameTimer() + 5000
            while not NetworkDoesNetworkIdExist(netId) and GetGameTimer() < limit do Wait(50) end
            local ped = NetworkDoesNetworkIdExist(netId) and NetToPed(netId) or 0
            if ped ~= 0 and DoesEntityExist(ped) and Rob then
                Rob.peds[i] = ped
                setupRobber(ped, data.weapons[i], i, #data.netIds)
            end
        end

        -- approach
        local limit = GetGameTimer() + Config.Robbery.approachTimeout * 1000
        while Rob and Rob.stage == 'approach' and GetGameTimer() < limit do
            local close, alive = 0, 0
            local me = GetEntityCoords(cache.ped)
            forEachRobber(function(ped)
                alive += 1
                if #(GetEntityCoords(ped) - me) <= Config.Robbery.surroundRadius + 2.0 then close += 1 end
            end)
            if alive > 0 and close >= alive then break end
            Wait(250)
        end
        if Rob and Rob.stage == 'approach' then
            local seconds = lib.callback.await('mozzy_tot:server:robberyReady', false)
            if seconds then startDemand(seconds) end
        end
    end)

    -- status monitor (dead reports + escape check)
    CreateThread(function()
        local lastEscapeCheck = 0
        while Rob do
            local me = GetEntityCoords(cache.ped)
            local nearest = math.huge
            for i, ped in ipairs(Rob.peds) do
                if ped and DoesEntityExist(ped) then
                    if IsPedDeadOrDying(ped, true) then
                        if not Rob.reported[i] then
                            Rob.reported[i] = true
                            TriggerServerEvent('mozzy_tot:server:robberDown', Rob.netIds[i])
                        end
                    else
                        nearest = math.min(nearest, #(GetEntityCoords(ped) - me))
                    end
                end
            end
            -- keep them on the player: re-task anyone who dropped out of combat (lost control / task reset)
            if (Rob.stage == 'chase' or Rob.stage == 'hostile') and GetGameTimer() - (Rob.lastRetask or 0) > 2000 then
                Rob.lastRetask = GetGameTimer()
                forEachRobber(function(ped)
                    if not IsPedInCombat(ped, cache.ped) then makeAttack(ped) end
                end)
            end
            if (Rob.stage == 'chase' or Rob.stage == 'hostile') and nearest > Config.Robbery.run.escapeDistance
                and GetGameTimer() - lastEscapeCheck > 3000 then
                lastEscapeCheck = GetGameTimer()
                lib.callback.await('mozzy_tot:server:robberyEscaped', false)
            end
            Wait(500)
        end
    end)
end

lib.callback.register('mozzy_tot:client:getRobberSpawns', function(count)
    local origin = GetEntityCoords(cache.ped)
    local points = {}
    for i = 1, count do
        local point
        for _ = 1, 10 do
            local a = (i / count) * math.pi * 2.0 + (math.random() - 0.5) * 0.9
            local d = Utils.range(Config.Robbery.spawnDistance)
            local x, y = origin.x + math.cos(a) * d, origin.y + math.sin(a) * d
            local found, z = GetGroundZFor_3dCoord(x, y, origin.z + 15.0, false)
            if found and math.abs(z - origin.z) < 8.0 then
                local ok, safe = GetSafeCoordForPed(x, y, z, false, 16)
                point = ok and safe or vector3(x, y, z)
                break
            end
        end
        points[i] = point or vector3(origin.x + math.random(-6, 6), origin.y + math.random(-6, 6), origin.z)
    end
    return points
end)

RegisterNetEvent('mozzy_tot:client:robberyStage', function(stage, extra) applyStage(stage, extra) end)
RegisterNetEvent('mozzy_tot:client:robberyEnd', function() endRobberyClient() end)

---------------------------------------------------------------------------
-- Knock flow
---------------------------------------------------------------------------
knock = function(houseId)
    if not canKnock() then return end
    if not isNight() then return Bridge.Notify('People only hand out candy after dark.', 'error') end
    busy = true

    local res = lib.callback.await('mozzy_tot:server:startKnock', false, houseId)
    if not res or not res.ok then
        if res and res.msg then Bridge.Notify(res.msg, 'error') end
        busy = false
        return
    end

    local house = Locations[houseId]
    TaskTurnPedToFaceCoord(cache.ped, house.coords.x, house.coords.y, house.coords.z, 800)
    Wait(800)

    local a = Utils.pick(Config.Knock.anims)
    local bell = Config.Knock.doorbellSound
    if bell.enabled then PlaySoundFrontend(-1, bell.name, bell.set, true) end
    if Config.Knock.useProgress then
        lib.progressCircle({
            duration = res.knockTime, label = Config.Knock.progressLabel, position = 'bottom',
            canCancel = false, disable = { move = true, car = true, combat = true },
            anim = { dict = a.dict, clip = a.clip, flag = a.flag },
        })
    else
        playAnim(cache.ped, a.dict, a.clip, a.flag, res.knockTime)
        Wait(res.knockTime)
    end
    ClearPedTasks(cache.ped)

    lib.showTextUI(Config.Knock.waitingLabel, { icon = 'door-closed' })
    Wait(res.delay)
    lib.hideTextUI()

    local npc = res.answer and res.npcModel and spawnDoorNpc(res.npcModel) or nil
    if npc then Wait(700) end

    local result = lib.callback.await('mozzy_tot:server:finishKnock', false, res.token)
    if not result or not result.ok then
        if result and result.msg then Bridge.Notify(result.msg, 'error') end
        if npc then deleteLocalPed(npc) end
        busy = false
        return
    end

    local o = result.outcome
    if o == 'robbery' then
        Bridge.Notify(result.msg, 'error', 7000, '🔪 Something\'s wrong...')
        startRobberyClient(result.robbery)
    elseif o == 'trick' then
        local fx = TrickFx[result.trick and result.trick.effect or 'none'] or TrickFx.none
        fx(npc)
        Bridge.Notify(result.msg, 'warning', 7000, '😈 Trick!')
    elseif o == 'nobody' then
        Bridge.Notify(result.msg, 'inform', 5000, '👻 Nobody Home')
    else
        local h = Config.Knock.handoverAnim
        if npc and h then
            playAnim(npc, h.dict, h.npc, 0, 2000)
            playAnim(cache.ped, h.dict, h.player, 0, 2000)
        end
        local title = ({ jackpot = '🍬 JACKPOT!', cash = '💰 Cash', candybag = '🎁 Candy Bag', laced = '🍬 Treat' })[o] or '🎃 Treat'
        local text = result.msg
        if result.given and result.given ~= '' then text = ('%s\n**Received:** %s'):format(text, result.given) end
        Bridge.Notify(text, 'success', 8000, title)
    end

    if npc then
        SetTimeout(Config.DoorNPC.stayTime, function()
            if DoesEntityExist(npc) then
                local back = GetOffsetFromEntityInWorldCoords(npc, 0.0, -2.0, 0.0)
                TaskGoStraightToCoord(npc, back.x, back.y, back.z, 1.0, 2000, 0.0, 0.5)
                Wait(1500)
                deleteLocalPed(npc)
            end
        end)
    end
    busy = false
end

---------------------------------------------------------------------------
-- Item progress (server asks, client animates, server re-validates timing)
---------------------------------------------------------------------------
lib.callback.register('mozzy_tot:client:itemProgress', function(kind, name)
    if lib.progressActive() or busy or isDead() then return false end
    local def = kind == 'bag' and Config.CandyBag.progress or Config.Consumables[name]
    if not def then return false end
    return lib.progressBar({
        duration = def.duration, label = def.label, useWhileDead = false, canCancel = true,
        disable = { car = false, move = false, combat = true },
        anim = def.anim and { dict = def.anim.dict, clip = def.anim.clip, flag = 49 } or nil,
        prop = def.prop and { model = def.prop.model, bone = def.prop.bone, pos = def.prop.pos, rot = def.prop.rot } or nil,
    })
end)

RegisterNetEvent('mozzy_tot:client:sour', function()
    ShakeGameplayCam('HAND_SHAKE', 1.5)
    SetTimeout(2000, function() StopGameplayCamShaking(false) end)
    Bridge.Notify('SO SOUR! Your face scrunches up.', 'inform', 3000, '🍬')
end)

---------------------------------------------------------------------------
-- 😵 Laced candy effects
---------------------------------------------------------------------------
local function stopHighVisuals()
    ClearTimecycleModifier()
    AnimpostfxStopAll()
    StopGameplayCamShaking(true)
    SetPedMotionBlur(cache.ped, false)
    ResetPedMovementClipset(cache.ped, 0.5)
    SetPedMoveRateOverride(cache.ped, 1.0)
    SetEntityInvincible(cache.ped, false)
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(1000) end
end

local function passOut(seconds)
    local L = Config.LacedCandy
    High.unconscious = true
    Bridge.Notify(L.passOutMessage, 'error', 5000, '😵')
    -- stumble...
    SetTimecycleModifierStrength(1.0)
    SetPedToRagdoll(cache.ped, 1200, 1200, 0, false, false, false)
    Wait(2000)
    -- ...collapse and fade
    SetPedToRagdoll(cache.ped, 5000, 5000, 0, false, false, false)
    if L.godmodeWhileUnconscious then SetEntityInvincible(cache.ped, true) end
    DoScreenFadeOut(2500)
    local t = GetGameTimer() + 4000
    while not IsScreenFadedOut() and GetGameTimer() < t do Wait(50) end

    local wake = GetGameTimer() + seconds * 1000
    while GetGameTimer() < wake and High and not isDead() do
        SetPedToRagdoll(cache.ped, 1500, 1500, 0, false, false, false)
        Wait(1000)
    end
    if not High then return end

    DoScreenFadeIn(4000)
    Wait(2500)
    playAnim(cache.ped, 'get_up@directional@movement@from_knees@action', 'getup_r_0', 0, 2500)
    SetEntityInvincible(cache.ped, false)
    Bridge.Notify(L.wakeMessage, 'inform', 5000)
    High.unconscious = false
    -- remaining effects gradually disappear
    High.endsAt = math.min(High.endsAt, GetGameTimer() + L.fadeOutTime * 1000)
end

local function runHigh(data)
    local L, fx = Config.LacedCandy, Config.LacedCandy.effects
    local now = GetGameTimer()
    High.startedAt = now
    High.endsAt = now + data.duration * 1000
    High.passOutAt = data.passOut and (now + data.duration * 1000 * L.passOutAt) or nil
    High.moveRate = 1.0

    Bridge.Notify(L.onsetMessage, 'inform', 5000, '🍬')
    if fx.timecycle.enabled then
        SetTimecycleModifier(Utils.pick(fx.timecycle.modifiers))
        SetTimecycleModifierStrength(0.0)
    end
    if fx.postFx.enabled then AnimpostfxPlay(Utils.pick(fx.postFx.names), 0, true) end
    if fx.cameraShake.enabled then ShakeGameplayCam(fx.cameraShake.name, 0.0) end
    if fx.motionBlur.enabled then SetPedMotionBlur(cache.ped, true) end
    if fx.walkStyle.enabled then
        lib.requestAnimSet(fx.walkStyle.clipset)
        SetPedMovementClipset(cache.ped, fx.walkStyle.clipset, 1.0)
    end

    -- per-frame controls (only while high)
    CreateThread(function()
        while High do
            if High.unconscious then
                DisableAllControlActions(0)
                EnableControlAction(0, 245, true) -- chat
            elseif fx.noSprint.enabled then
                DisableControlAction(0, 21, true)
            end
            if fx.movementSpeed.enabled then SetPedMoveRateOverride(cache.ped, High.moveRate) end
            Wait(0)
        end
    end)

    local nextDrift, nextRagdoll, nextAnim = 0, now + fx.randomRagdoll.interval * 1000, now + fx.randomAnims.interval * 1000
    while High and GetGameTimer() < High.endsAt do
        local t = GetGameTimer()
        if isDead() then break end

        local total = High.endsAt - High.startedAt
        local elapsed = t - High.startedAt
        local remaining = High.endsAt - t
        local ramp = math.min(1.0, elapsed / math.max(1, total * 0.25))
        local fade = math.min(1.0, remaining / (L.fadeOutTime * 1000))
        local intensity = math.min(ramp, fade)
        High.intensity = intensity

        if fx.timecycle.enabled then SetTimecycleModifierStrength(intensity * fx.timecycle.maxStrength) end
        if fx.cameraShake.enabled then SetGameplayCamShakeAmplitude(intensity * fx.cameraShake.intensity) end

        if not High.unconscious then
            if fx.movementSpeed.enabled and t > nextDrift then
                nextDrift = t + 3000
                High.moveRate = 1.0 + (Utils.range({ min = fx.movementSpeed.min, max = fx.movementSpeed.max }) - 1.0) * intensity
            end
            if fx.randomRagdoll.enabled and t > nextRagdoll then
                nextRagdoll = t + fx.randomRagdoll.interval * 1000
                if Utils.roll(fx.randomRagdoll.chance * intensity) and not cache.vehicle then
                    SetPedToRagdoll(cache.ped, 1500, 1500, 0, false, false, false)
                end
            end
            if fx.randomAnims.enabled and t > nextAnim then
                nextAnim = t + fx.randomAnims.interval * 1000
                if Utils.roll(fx.randomAnims.chance * intensity) and not cache.vehicle then
                    local an = Utils.pick(fx.randomAnims.list)
                    playAnim(cache.ped, an.dict, an.clip, 48, 3000)
                end
            end
            if High.passOutAt and t >= High.passOutAt then
                High.passOutAt = nil
                if not cache.vehicle then passOut(data.unconscious) end
            end
        end
        Wait(100)
    end

    High = nil
    stopHighVisuals()
    if not isDead() then Bridge.Notify(L.endMessage, 'success', 5000) end
end

RegisterNetEvent('mozzy_tot:client:laced', function(data)
    if type(data) ~= 'table' then return end
    if High then
        -- already high: stack the duration instead of restarting visuals
        if High.endsAt then High.endsAt += data.duration * 1000 end
        if data.passOut and not High.passOutAt and not High.unconscious then
            High.passOutAt = GetGameTimer() + data.delay * 1000
        end
        return
    end
    High = { pending = true }
    CreateThread(function()
        Wait(data.delay * 1000)
        if not High then return end
        High.pending = nil
        runHigh(data)
    end)
end)

---------------------------------------------------------------------------
-- 🚓 Police
---------------------------------------------------------------------------
RegisterNetEvent('mozzy_tot:client:sendPoliceAlert', function(data)
    local P = Config.PoliceAlert
    local coords = GetEntityCoords(cache.ped)
    local s1, s2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(s1)
    if s2 and s2 ~= 0 then street = street .. ' / ' .. GetStreetNameFromHashKey(s2) end
    local area = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    if area and area ~= 'NULL' then street = ('%s, %s'):format(street, area) end
    local description = P.description
    if data and data.suspects then description = ('%s %s.'):format(description, data.suspects) end

    Dispatch.send({
        coords = coords, street = street, title = P.title, code = P.code,
        description = description, suspects = data and data.suspects, blip = P.blip,
    })
    TriggerServerEvent('mozzy_tot:server:alertSent')
end)

-- 'qbx' fallback alert received by on-duty police
RegisterNetEvent('mozzy_tot:client:policeBlip', function(d)
    lib.notify({
        title = ('%s | %s'):format(d.code, d.title),
        description = ('%s\n📍 %s%s'):format(d.description, d.street, d.suspects and ('\n👤 ' .. d.suspects) or ''),
        type = 'error', duration = 12000, icon = 'mask',
    })
    PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', false)
    local b = d.blip
    local radius = AddBlipForRadius(d.coords.x, d.coords.y, d.coords.z, b.radius)
    SetBlipColour(radius, b.color)
    SetBlipAlpha(radius, 90)
    local blip = AddBlipForCoord(d.coords.x, d.coords.y, d.coords.z)
    SetBlipSprite(blip, b.sprite)
    SetBlipColour(blip, b.color)
    SetBlipScale(blip, b.scale)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(d.code .. ' - ' .. d.title)
    EndTextCommandSetBlipName(blip)
    SetTimeout((b.time or 60) * 1000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        if DoesBlipExist(radius) then RemoveBlip(radius) end
    end)
end)

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for i = #localPeds, 1, -1 do if DoesEntityExist(localPeds[i]) then DeleteEntity(localPeds[i]) end end
    for _, b in ipairs(houseBlips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    if Rob then endRobberyClient() end
    if High then High = nil stopHighVisuals() end
    lib.hideTextUI()
end)
