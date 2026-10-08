--[[
    MOZZY TRICK OR TREAT - server/main.lua
    Everything that matters (outcomes, rewards, theft, cooldowns, rep) is decided here.
    The client only ever sends: "I want to knock on door #id", "my token", "my robbery choice".
]]

local ox = exports.ox_inventory

local Active = {}          -- [src] = pending knock { token, houseId, minFinish, expires, outcome, data }
local Busy = {}            -- [src] = GetGameTimer() while an item is being used
local Robberies = {}       -- [src] = robbery state
local PendingAlert = {}    -- [src] = true while the client is allowed to send a fallback dispatch
local Forced = {}          -- [src] = outcome (debug)
local LastCall = {}        -- [src] = GetGameTimer() (rate limit)

local HouseCD = {}         -- [houseId] = os.time() when available again
local PlayerLast = {}      -- [cid] = os.time() of last knock
local PlayerHouseCD = {}   -- [cid] = { [houseId] = os.time() when available again }
local PlayerWindow = {}    -- [cid] = { timestamps }

local ITEM_LABELS = {}
local function itemLabel(name)
    if ITEM_LABELS[name] then return ITEM_LABELS[name] end
    local data = ox:Items(name)
    ITEM_LABELS[name] = data and data.label or name
    return ITEM_LABELS[name]
end

---------------------------------------------------------------------------
-- Security helpers
---------------------------------------------------------------------------
local function flag(src, reason)
    Bridge.Log(src, reason)
    if Config.Security.dropOnExploit then DropPlayer(src, 'mozzy_trickortreat: invalid request') end
end

local function rateLimited(src)
    local now = GetGameTimer()
    if LastCall[src] and now - LastCall[src] < Config.Security.rateLimit then return true end
    LastCall[src] = now
    return false
end

local function isBusy(src)
    return Busy[src] and (GetGameTimer() - Busy[src] < 30000)
end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function newToken()
    return ('%x%x'):format(math.random(0, 0x7fffffff), GetGameTimer())
end

---------------------------------------------------------------------------
-- Reputation
---------------------------------------------------------------------------
local Rep = {}

function Rep.get(src)
    if not Config.Reputation.enabled then return 0 end
    local rep = Bridge.GetMeta(src, Config.Reputation.metadataKey)
    return tonumber(rep) or 0
end

function Rep.tier(rep)
    local tiers, current, nextTier = Config.Reputation.tiers, nil, nil
    for i = 1, #tiers do
        if rep >= tiers[i].rep then current = tiers[i] else nextTier = tiers[i] break end
    end
    return current or tiers[1], nextTier
end

function Rep.tierFor(src)
    if not Config.Reputation.enabled then return { quantityBonus = 0, rareMultiplier = 1.0 } end
    return (Rep.tier(Rep.get(src)))
end

function Rep.add(src, amount)
    if not Config.Reputation.enabled or not amount or amount <= 0 then return end
    local before = Rep.get(src)
    local after = before + amount
    Bridge.SetMeta(src, Config.Reputation.metadataKey, after)
    local oldTier, newTier = Rep.tier(before), Rep.tier(after)
    if newTier.rep > oldTier.rep then
        Bridge.Notify(src, ('New Halloween rank: **%s**!'):format(newTier.label), 'success', 8000, '🏆 Rank Up')
    end
end

---------------------------------------------------------------------------
-- Inventory helpers (server-side only, never trusts the client)
---------------------------------------------------------------------------
local function itemWeight(name)
    local d = ox:Items(name)
    return d and d.weight or 0
end

--- Gives a list of { item, count }. Returns array of given { label, count }.
local function giveItems(src, list)
    local given = {}
    -- merge duplicates
    local merged, order = {}, {}
    for _, e in ipairs(list) do
        if e.count and e.count > 0 then
            if not merged[e.item] then merged[e.item] = 0 order[#order + 1] = e.item end
            merged[e.item] += e.count
        end
    end
    for _, name in ipairs(order) do
        local count = merged[name]
        if ox:CanCarryItem(src, name, count) then
            local ok = ox:AddItem(src, name, count)
            if ok then given[#given + 1] = { label = itemLabel(name), count = count, item = name } end
        else
            Bridge.Notify(src, ('You can\'t carry %sx %s.'):format(count, itemLabel(name)), 'error')
        end
    end
    return given
end

local function formatGiven(given)
    local parts = {}
    for _, g in ipairs(given) do parts[#parts + 1] = ('%sx %s'):format(g.count, g.label) end
    return table.concat(parts, ', ')
end

--- Rolls `rolls` entries from a weighted reward table, applying rep bonus and laced swaps.
local function rollRewards(src, rewardTable, rolls, qtyMultiplier, allowLacedSwap)
    local tier = Rep.tierFor(src)
    local out = {}
    for _ = 1, rolls do
        local entry = Utils.weighted(rewardTable, function(e, w)
            if e.item == Config.Items.candyBag or e.item == Config.Items.caramelApple or e.item == Config.Items.mysteryCandy then
                return w * (tier.rareMultiplier or 1.0)
            end
            if e.item == Config.Items.lacedCandy and not Config.LacedCandy.enabled then return 0 end
            return w
        end)
        if entry then
            local count = math.floor(Utils.range({ min = entry.min or 1, max = entry.max or entry.min or 1 }) * (qtyMultiplier or 1))
            count += (tier.quantityBonus or 0)
            local item = entry.item
            if allowLacedSwap and Config.LacedCandy.enabled and item ~= Config.Items.candyBag
                and item ~= Config.Items.lacedCandy and Utils.roll(Config.LacedCandy.chance) then
                -- one piece of this handful is secretly laced
                out[#out + 1] = { item = Config.Items.lacedCandy, count = 1 }
                count -= 1
            end
            if count > 0 then out[#out + 1] = { item = item, count = count } end
        end
    end
    if tier.bonus and Utils.roll(tier.bonus.chance) then
        out[#out + 1] = { item = tier.bonus.item, count = tier.bonus.amount or 1 }
    end
    return out
end

---------------------------------------------------------------------------
-- Cooldowns
---------------------------------------------------------------------------
local function checkCooldowns(cid, houseId)
    local now, cd = os.time(), Config.Cooldowns

    if PlayerLast[cid] and now - PlayerLast[cid] < cd.global then
        return false, ('Slow down! Try again in %ss.'):format(cd.global - (now - PlayerLast[cid]))
    end
    if HouseCD[houseId] and HouseCD[houseId] > now then
        return false, 'Someone just trick-or-treated here. Try another house!'
    end
    local ph = PlayerHouseCD[cid]
    if ph and ph[houseId] and ph[houseId] > now then
        return false, ('You already visited this house. Come back in %s min.'):format(math.ceil((ph[houseId] - now) / 60))
    end
    if cd.maxPerPeriod and cd.maxPerPeriod.enabled then
        local win = PlayerWindow[cid] or {}
        local fresh = {}
        for _, t in ipairs(win) do if now - t < cd.maxPerPeriod.period then fresh[#fresh + 1] = t end end
        PlayerWindow[cid] = fresh
        if #fresh >= cd.maxPerPeriod.amount then
            local wait = cd.maxPerPeriod.period - (now - fresh[1])
            return false, ('You\'re worn out from all the walking. Rest for %s min.'):format(math.ceil(wait / 60))
        end
    end
    return true
end

local function applyCooldowns(cid, houseId)
    local now, cd = os.time(), Config.Cooldowns
    PlayerLast[cid] = now
    HouseCD[houseId] = now + cd.house
    PlayerHouseCD[cid] = PlayerHouseCD[cid] or {}
    PlayerHouseCD[cid][houseId] = now + cd.playerHouse
    if cd.maxPerPeriod and cd.maxPerPeriod.enabled then
        PlayerWindow[cid] = PlayerWindow[cid] or {}
        table.insert(PlayerWindow[cid], now)
    end
end

-- periodic cleanup of expired cooldown entries (keeps memory flat on long uptimes)
CreateThread(function()
    while true do
        Wait(300000)
        local now = os.time()
        for id, t in pairs(HouseCD) do if t <= now then HouseCD[id] = nil end end
        for cid, houses in pairs(PlayerHouseCD) do
            for id, t in pairs(houses) do if t <= now then houses[id] = nil end end
            if not next(houses) then PlayerHouseCD[cid] = nil end
        end
    end
end)

---------------------------------------------------------------------------
-- Outcome selection
---------------------------------------------------------------------------
local OUTCOME_ORDER = { 'normal', 'jackpot', 'laced', 'nobody', 'trick', 'cash', 'candybag' }

local function chooseOutcome(src)
    if Forced[src] then
        local f = Forced[src]; Forced[src] = nil
        return f
    end
    if Config.Robbery.enabled and Utils.roll(Config.Robbery.chance) then return 'robbery' end
    local tier = Rep.tierFor(src)
    local entries = {}
    for _, name in ipairs(OUTCOME_ORDER) do
        local o = Config.Outcomes[name]
        if o and o.enabled then
            local w = o.weight
            if name == 'jackpot' or name == 'candybag' then w = w * (tier.rareMultiplier or 1.0) end
            if name == 'laced' and not Config.LacedCandy.enabled then w = 0 end
            entries[#entries + 1] = { name = name, weight = w }
        end
    end
    local pick = Utils.weighted(entries)
    return pick and pick.name or 'nobody'
end

---------------------------------------------------------------------------
-- KNOCK: step 1 (validate + lock + decide)
---------------------------------------------------------------------------
lib.callback.register('mozzy_tot:server:startKnock', function(src, houseId)
    if not Config.Enabled then return { ok = false, msg = 'Trick-or-treating is closed right now.' } end
    if not Utils.isSeasonActive() then return { ok = false, msg = 'It\'s not Halloween season!' } end
    if rateLimited(src) then return { ok = false } end

    houseId = tonumber(houseId)
    if not houseId or math.type(houseId) ~= 'integer' then flag(src, 'startKnock: invalid house id') return { ok = false } end
    local house = Locations[houseId]
    if not house then flag(src, ('startKnock: unknown house %s'):format(houseId)) return { ok = false } end

    if Active[src] or Robberies[src] or isBusy(src) then return { ok = false, msg = 'You\'re already busy.' } end
    if Bridge.IsDead(src) then return { ok = false } end

    local cid = Bridge.GetCitizenId(src)
    if not cid then return { ok = false } end

    local coords = playerCoords(src)
    if not coords or #(coords - house.coords) > Config.Security.maxDistance then
        flag(src, ('startKnock: too far from house %s (%.1fm)'):format(houseId, coords and #(coords - house.coords) or -1))
        return { ok = false, msg = 'You need to be at the door.' }
    end

    local allowed, msg = checkCooldowns(cid, houseId)
    if not allowed then return { ok = false, msg = msg } end
    applyCooldowns(cid, houseId)

    local outcome = chooseOutcome(src)
    local delay = Utils.range(Config.Knock.responseDelay)
    local knock = Config.Knock.duration
    local token = newToken()

    -- presentation hints only (no reward info)
    local answer = outcome ~= 'nobody' and outcome ~= 'robbery'
    local trick
    if outcome == 'trick' then trick = Utils.weighted(Config.Tricks) end
    local npcModel
    if answer and Config.DoorNPC.enabled then
        npcModel = (trick and trick.effect == 'scare') and Utils.pick(Config.DoorNPC.scareModels) or Utils.pick(Config.DoorNPC.models)
    end

    local now = GetGameTimer()
    Active[src] = {
        token = token, houseId = houseId, cid = cid, outcome = outcome, trick = trick,
        minFinish = now + knock + delay - Config.Security.timingTolerance,
        expires = now + knock + delay + 60000,
    }
    Utils.debug(('knock src=%s house=%s outcome=%s'):format(src, houseId, outcome))

    return { ok = true, token = token, knockTime = knock, delay = delay, answer = answer, npcModel = npcModel }
end)

---------------------------------------------------------------------------
-- Robbery
---------------------------------------------------------------------------
local function deleteRobberyPeds(rob)
    for _, ped in ipairs(rob.peds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
end

local function endRobbery(src, reason)
    local rob = Robberies[src]
    if not rob then return end
    Robberies[src] = nil
    PendingAlert[src] = nil
    deleteRobberyPeds(rob)
    if GetPlayerPing(src) > 0 then TriggerClientEvent('mozzy_tot:client:robberyEnd', src, reason) end
    Utils.debug(('robbery ended src=%s reason=%s'):format(src, reason))
end

local function stealCash(src)
    local c = Config.Robbery.cashTheft
    local cash = Bridge.GetMoney(src, c.moneyType)
    if cash <= 0 then return 0 end
    local pct = Utils.range(c.percent) / 100
    local amount = math.floor(cash * pct)
    amount = math.max(math.min(amount, c.max), math.min(c.min, cash))
    amount = math.min(amount, cash)
    if amount <= 0 then return 0 end
    if Bridge.RemoveMoney(src, c.moneyType, amount, 'trick-or-treat-robbery') then return amount end
    return 0
end

--- Removes random Halloween items the player ACTUALLY owns (server inventory lookup)
local function stealCandy(src)
    local c = Config.Robbery.candyTheft
    local counts = ox:Search(src, 'count', c.items) or {}
    if type(counts) == 'number' then counts = { [c.items[1]] = counts } end
    local pool, total = {}, 0
    for _, name in ipairs(c.items) do
        local n = counts[name] or 0
        if n > 0 then pool[name] = n total += n end
    end
    if total == 0 then return {} end
    local want = math.min(Utils.range(c.amount), total)
    local take = {}
    for _ = 1, want do
        local r = math.random(total)
        for name, n in pairs(pool) do
            if r <= n then
                take[name] = (take[name] or 0) + 1
                pool[name] = n - 1
                total -= 1
                if pool[name] == 0 then pool[name] = nil end
                break
            end
            r -= n
        end
    end
    local stolen = {}
    for name, n in pairs(take) do
        if ox:RemoveItem(src, name, n) then stolen[#stolen + 1] = { label = itemLabel(name), count = n } end
    end
    return stolen
end

local function setStage(src, stage, extra)
    local rob = Robberies[src]
    if not rob then return end
    rob.stage = stage
    if stage == 'leaving' then rob.leaveAt = GetGameTimer() + Config.Robbery.leaveTime * 1000 end
    if stage == 'hostile' or stage == 'chase' then
        -- server-side RPC task: reaches the ped's owner even if the victim's client never got network control
        local target = GetPlayerPed(src)
        for _, ped in ipairs(rob.peds) do
            if DoesEntityExist(ped) and GetEntityHealth(ped) > 0 then
                ClearPedTasks(ped)
                TaskCombatPed(ped, target, 0, 16)
            end
        end
    end
    TriggerClientEvent('mozzy_tot:client:robberyStage', src, stage, extra)
end

local function startRobbery(src, houseId)
    local cfg = Config.Robbery
    local count = math.random(cfg.minNPCs, math.max(cfg.minNPCs, cfg.maxNPCs))
    local origin = playerCoords(src)
    if not origin then return nil end

    local points = lib.callback.await('mozzy_tot:client:getRobberSpawns', src, count)
    if type(points) ~= 'table' then points = {} end

    local bucket = GetPlayerRoutingBucket(src)
    local peds, netIds, weapons = {}, {}, {}
    for i = 1, count do
        local p = points[i]
        local valid = type(p) == 'vector3' and #(p - origin) <= cfg.spawnDistance.max + 10.0 and #(p - origin) >= 2.0
        if not valid then
            local a = math.random() * math.pi * 2
            local dist = Utils.range(cfg.spawnDistance)
            p = vector3(origin.x + math.cos(a) * dist, origin.y + math.sin(a) * dist, origin.z)
        end
        local heading = math.deg(math.atan(origin.y - p.y, origin.x - p.x)) - 90.0
        local ped = CreatePed(4, joaat(Utils.pick(cfg.models)), p.x, p.y, p.z, heading, true, true)
        local timeout = GetGameTimer() + 3000
        while ped ~= 0 and not DoesEntityExist(ped) and GetGameTimer() < timeout do Wait(25) end
        if ped ~= 0 and DoesEntityExist(ped) then
            SetEntityRoutingBucket(ped, bucket)
            local w = Utils.weighted(cfg.weapons)
            if w then
                GiveWeaponToPed(ped, joaat(w.weapon), w.ammo or 0, false, true)
                weapons[#weapons + 1] = w.weapon
            else
                weapons[#weapons + 1] = 'WEAPON_UNARMED'
            end
            if (cfg.npc.armor or 0) > 0 then SetPedArmour(ped, cfg.npc.armor) end
            peds[#peds + 1] = ped
            netIds[#netIds + 1] = NetworkGetNetworkIdFromEntity(ped)
        end
    end

    if #peds == 0 then return nil end

    local now = GetGameTimer()
    Robberies[src] = {
        peds = peds, netIds = netIds, weapons = weapons, origin = origin, houseId = houseId,
        stage = 'approach', started = now, expires = now + cfg.timeout * 1000,
        approachEnds = now + (cfg.approachTimeout + 5) * 1000, clientDead = {}, looted = false,
    }

    if Config.PoliceAlert.enabled and Utils.roll(Config.PoliceAlert.chance) then
        SetTimeout((Config.PoliceAlert.delay or 0) * 1000, function()
            if not Robberies[src] then return end
            PendingAlert[src] = true
            local described = {}
            for _, w in ipairs(weapons) do described[#described + 1] = w:gsub('WEAPON_', ''):lower() end
            TriggerClientEvent('mozzy_tot:client:sendPoliceAlert', src, {
                suspects = Config.PoliceAlert.suspectDescription
                    and ('%s suspects, armed with: %s'):format(#peds, table.concat(described, ', ')) or nil,
            })
        end)
    end

    return { netIds = netIds, weapons = weapons }
end

---------------------------------------------------------------------------
-- KNOCK: step 2 (validate token/timing + grant)
---------------------------------------------------------------------------
lib.callback.register('mozzy_tot:server:finishKnock', function(src, token)
    local act = Active[src]
    if not act then return { ok = false } end
    if type(token) ~= 'string' or token ~= act.token then
        Active[src] = nil
        flag(src, 'finishKnock: bad token')
        return { ok = false }
    end
    local now = GetGameTimer()
    if now < act.minFinish then
        Active[src] = nil
        flag(src, 'finishKnock: finished too early (timing bypass)')
        return { ok = false }
    end
    Active[src] = nil
    if now > act.expires then return { ok = false, msg = 'You waited too long.' } end
    if Bridge.IsDead(src) then return { ok = false } end

    local coords = playerCoords(src)
    local house = Locations[act.houseId]
    if not coords or #(coords - house.coords) > Config.Security.finishDistance then
        return { ok = false, msg = 'You walked away from the door.' }
    end

    local outcome = act.outcome
    local O = Config.Outcomes[outcome]
    local result = { ok = true, outcome = outcome }

    if outcome == 'robbery' then
        local rob = startRobbery(src, act.houseId)
        if not rob then
            result.outcome = 'nobody'
            result.msg = Utils.pick(Config.Messages.nobody)
            return result
        end
        result.robbery = rob
        result.msg = Config.Robbery.messages.approach
        return result
    end

    if outcome == 'normal' then
        local given = giveItems(src, rollRewards(src, Config.CandyRewards, Utils.range(Config.CandyRolls), 1, true))
        result.msg = Utils.pick(Config.Messages.normal)
        result.given = formatGiven(given)
    elseif outcome == 'jackpot' then
        local given = giveItems(src, rollRewards(src, Config.CandyRewards, Utils.range(O.rolls), O.quantityMultiplier or 1, true))
        result.msg = Utils.pick(Config.Messages.jackpot)
        result.given = formatGiven(given)
    elseif outcome == 'laced' then
        local given = giveItems(src, { { item = Config.Items.lacedCandy, count = Utils.range(O.amount) } })
        result.msg = Utils.pick(Config.Messages.laced)
        result.given = formatGiven(given)
    elseif outcome == 'cash' then
        local amount = Utils.range(O.amount)
        if Bridge.AddMoney(src, O.moneyType or 'cash', amount, 'trick-or-treat') then
            result.given = ('$%s'):format(amount)
        end
        result.msg = Utils.pick(Config.Messages.cash)
    elseif outcome == 'candybag' then
        local given = giveItems(src, { { item = Config.Items.candyBag, count = Utils.range(O.amount) } })
        result.msg = Utils.pick(Config.Messages.candybag)
        result.given = formatGiven(given)
    elseif outcome == 'trick' then
        result.trick = act.trick or Utils.weighted(Config.Tricks)
        result.msg = result.trick.message
    else
        result.msg = Utils.pick(Config.Messages.nobody)
    end

    if O and O.rep then Rep.add(src, O.rep) end
    return result
end)

---------------------------------------------------------------------------
-- Robbery client -> server
---------------------------------------------------------------------------
local VALID_CHOICES = { money = true, candy = true, refuse = true, run = true }

lib.callback.register('mozzy_tot:server:robberyReady', function(src)
    local rob = Robberies[src]
    if not rob or rob.stage ~= 'approach' then return false end
    rob.stage = 'demand'
    rob.demandEnds = GetGameTimer() + (Config.Robbery.cooperateTime * 1000)
    return Config.Robbery.cooperateTime
end)

lib.callback.register('mozzy_tot:server:robberyChoice', function(src, choice)
    local rob = Robberies[src]
    if not rob or rob.stage ~= 'demand' then return false end
    if not VALID_CHOICES[choice] then flag(src, 'robberyChoice: invalid choice') return false end
    local cfg = Config.Robbery

    if GetGameTimer() > rob.demandEnds + Config.Security.timingTolerance then choice = 'refuse' end

    if choice == 'money' then
        local amount = stealCash(src)
        if amount <= 0 and Utils.roll(cfg.cashTheft.hostileIfBroke) then
            setStage(src, 'hostile', { reason = 'broke' })
            return { stage = 'hostile', reason = 'broke' }
        end
        Rep.add(src, Config.Reputation.gains.robberyCooperated)
        setStage(src, 'leaving', { amount = amount })
        return { stage = 'leaving', amount = amount }
    elseif choice == 'candy' then
        local stolen = stealCandy(src)
        if #stolen == 0 and Utils.roll(cfg.candyTheft.hostileIfNone) then
            setStage(src, 'hostile', { reason = 'nocandy' })
            return { stage = 'hostile', reason = 'nocandy' }
        end
        Rep.add(src, Config.Reputation.gains.robberyCooperated)
        setStage(src, 'leaving', { stolen = formatGiven(stolen) })
        return { stage = 'leaving', stolen = formatGiven(stolen) }
    elseif choice == 'refuse' then
        setStage(src, 'hostile', { reason = 'refused' })
        return { stage = 'hostile', reason = 'refused' }
    else -- run
        if cfg.run.attackOnRun or Utils.roll(cfg.run.chaseChance) then
            setStage(src, 'chase')
            return { stage = 'chase' }
        end
        setStage(src, 'leaving', { letGo = true })
        return { stage = 'leaving', letGo = true }
    end
end)

-- victim reports a robber went down (only trusted together with a server-side health check)
RegisterNetEvent('mozzy_tot:server:robberDown', function(netId)
    local src = source
    local rob = Robberies[src]
    if not rob or type(netId) ~= 'number' then return end
    for _, id in ipairs(rob.netIds) do
        if id == netId then rob.clientDead[netId] = true return end
    end
end)

lib.callback.register('mozzy_tot:server:robberyEscaped', function(src)
    local rob = Robberies[src]
    if not rob or (rob.stage ~= 'chase' and rob.stage ~= 'hostile') then return false end
    local coords = playerCoords(src)
    if not coords then return false end
    local escape = Config.Robbery.run.escapeDistance * 0.8
    for i, ped in ipairs(rob.peds) do
        if DoesEntityExist(ped) and GetEntityHealth(ped) > 0 and not rob.clientDead[rob.netIds[i]] then
            if #(GetEntityCoords(ped) - coords) < escape then return false end
        end
    end
    Rep.add(src, Config.Reputation.gains.robberyEscaped)
    Bridge.Notify(src, 'You lost them. That was close!', 'success')
    endRobbery(src, 'escaped')
    return true
end)

RegisterNetEvent('mozzy_tot:server:fallbackDispatch', function(data)
    local src = source
    if not PendingAlert[src] then return end
    PendingAlert[src] = nil
    local coords = playerCoords(src)
    if not coords then return end
    local street = type(data) == 'table' and type(data.street) == 'string' and data.street:sub(1, 80) or 'Unknown street'
    local payload = {
        title = Config.PoliceAlert.title, code = Config.PoliceAlert.code,
        description = Config.PoliceAlert.description, street = street,
        suspects = type(data) == 'table' and type(data.suspects) == 'string' and data.suspects:sub(1, 120) or nil,
        coords = coords, blip = Config.PoliceAlert.blip,
    }
    for _, cop in ipairs(Bridge.GetPoliceSources()) do
        TriggerClientEvent('mozzy_tot:client:policeBlip', cop, payload)
    end
end)

-- validates that the client only reports on its own robbery alert (for non-fallback systems)
RegisterNetEvent('mozzy_tot:server:alertSent', function() PendingAlert[source] = nil end)

---------------------------------------------------------------------------
-- Robbery monitor (only runs while robberies exist; never loops over houses)
---------------------------------------------------------------------------
local function pedDead(rob, i)
    local ped = rob.peds[i]
    if not DoesEntityExist(ped) then return true end
    local hp = GetEntityHealth(ped)
    if hp <= 0 then return true end
    return hp < 101 and rob.clientDead[rob.netIds[i]] == true
end

CreateThread(function()
    while true do
        if next(Robberies) then
            local now = GetGameTimer()
            for src, rob in pairs(Robberies) do
                local coords = playerCoords(src)
                if not coords then
                    endRobbery(src, 'invalid')
                elseif now > rob.expires then
                    endRobbery(src, 'timeout')
                elseif #(coords - rob.origin) > Config.Robbery.despawnDistance then
                    endRobbery(src, 'left_area')
                elseif rob.stage == 'leaving' then
                    if now > rob.leaveAt then endRobbery(src, 'left') end
                elseif rob.stage == 'approach' and now > rob.approachEnds then
                    rob.stage = 'demand'
                    rob.demandEnds = now + Config.Robbery.cooperateTime * 1000
                    TriggerClientEvent('mozzy_tot:client:robberyStage', src, 'demand', { forced = true })
                elseif rob.stage == 'demand' and now > rob.demandEnds + Config.Security.timingTolerance * 2 then
                    setStage(src, 'hostile', { reason = 'timeout' })
                elseif rob.stage == 'hostile' or rob.stage == 'chase' then
                    local alive = 0
                    for i = 1, #rob.peds do if not pedDead(rob, i) then alive += 1 end end
                    if alive == 0 then
                        if not rob.defeated then
                            rob.defeated = true
                            Rep.add(src, Config.Reputation.gains.robberyDefeated)
                            Bridge.Notify(src, 'You fought them off!', 'success')
                            TriggerClientEvent('mozzy_tot:client:robberyStage', src, 'defeated')
                            rob.stage = 'defeated'
                            rob.expires = now + Config.Robbery.bodyCleanupDelay * 1000
                        end
                    elseif Bridge.IsDead(src) and Config.Robbery.lootOnDown and not rob.looted then
                        rob.looted = true
                        local cash = stealCash(src)
                        local candy = stealCandy(src)
                        Bridge.Notify(src, ('While you were down they took $%s%s.'):format(cash,
                            #candy > 0 and (' and ' .. formatGiven(candy)) or ''), 'error', 9000)
                        setStage(src, 'leaving', { looted = true })
                    end
                end
            end
            Wait(1500)
        else
            Wait(3000)
        end
    end
end)

---------------------------------------------------------------------------
-- Usable items
---------------------------------------------------------------------------
--- Confirms the player still owns the item in that slot (or anywhere) and removes 1
local function consumeOne(src, name, slot)
    if slot then
        local s = ox:GetSlot(src, slot)
        if s and s.name == name and s.count > 0 then
            return ox:RemoveItem(src, name, 1, nil, slot)
        end
    end
    if (ox:Search(src, 'count', name) or 0) > 0 then return ox:RemoveItem(src, name, 1) end
    return false
end

local function runProgress(src, kind, name, duration)
    Busy[src] = GetGameTimer()
    local started = GetGameTimer()
    local ok = lib.callback.await('mozzy_tot:client:itemProgress', src, kind, name)
    local elapsed = GetGameTimer() - started
    if ok and elapsed < duration - Config.Security.timingTolerance then
        flag(src, ('itemProgress finished too fast (%sms / %sms)'):format(elapsed, duration))
        ok = false
    end
    return ok
end

local function addStatus(src, def)
    if def.hunger then
        local cur = Bridge.GetMeta(src, 'hunger')
        cur = tonumber(cur) or 0
        Bridge.SetMeta(src, 'hunger', math.min(100, cur + def.hunger))
    end
    if def.thirst then
        local cur = Bridge.GetMeta(src, 'thirst')
        cur = tonumber(cur) or 0
        Bridge.SetMeta(src, 'thirst', math.min(100, cur + def.thirst))
    end
    if def.stress then
        local cur = Bridge.GetMeta(src, 'stress')
        cur = tonumber(cur) or 0
        Bridge.SetMeta(src, 'stress', math.max(0, cur - def.stress))
    end
end

local function triggerLaced(src)
    local L = Config.LacedCandy
    TriggerClientEvent('mozzy_tot:client:laced', src, {
        delay = Utils.range(L.effectDelay),
        duration = Utils.range(L.effectDuration),
        passOut = Utils.roll(L.passOutChance),
        unconscious = Utils.range(L.unconsciousTime),
    })
end

local function useConsumable(src, name, item)
    if isBusy(src) or Active[src] or (Robberies[src] and Robberies[src].stage == 'demand') then return end
    local def = Config.Consumables[name]
    local slot = item and item.slot
    if not runProgress(src, 'eat', name, def.duration) then Busy[src] = nil return end
    if not consumeOne(src, name, slot) then Busy[src] = nil return end
    addStatus(src, def)
    if def.sourShake then TriggerClientEvent('mozzy_tot:client:sour', src) end
    if Config.LacedCandy.enabled and (def.laced or Utils.roll(def.lacedChance or 0)) then
        triggerLaced(src)
    end
    Busy[src] = nil
end

local function openCandyBag(src, item)
    if isBusy(src) or Active[src] or Robberies[src] then return end
    local B = Config.CandyBag
    local bag = Config.Items.candyBag

    -- roll first so we can check capacity BEFORE removing the bag
    local rewards = rollRewards(src, B.rewards, Utils.range(B.rolls), 1, false)
    if Utils.roll(B.rare.chance) then
        local r = Utils.weighted(B.rare.rewards)
        if r then rewards[#rewards + 1] = { item = r.item, count = Utils.range({ min = r.min or 1, max = r.max or 1 }) } end
    end
    if Config.LacedCandy.enabled and Utils.roll(B.lacedChance) then
        rewards[#rewards + 1] = { item = Config.Items.lacedCandy, count = 1 }
    end
    local weight = 0
    for _, r in ipairs(rewards) do weight += itemWeight(r.item) * r.count end
    weight -= itemWeight(bag)
    if weight > 0 and not ox:CanCarryWeight(src, weight) then
        Bridge.Notify(src, 'Your pockets are too full to open this.', 'error')
        return
    end

    if not runProgress(src, 'bag', bag, B.progress.duration) then Busy[src] = nil return end
    if not consumeOne(src, bag, item and item.slot) then Busy[src] = nil return end
    local given = giveItems(src, rewards)
    Bridge.Notify(src, ('You dumped out the bag: %s'):format(formatGiven(given)), 'success', 8000)
    Busy[src] = nil
end

CreateThread(function()
    for name in pairs(Config.Consumables) do
        Bridge.RegisterUsable(name, function(src, item) useConsumable(src, name, item) end)
    end
    Bridge.RegisterUsable(Config.Items.candyBag, function(src, item) openCandyBag(src, item) end)
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
if Config.Reputation.enabled then
    lib.addCommand(Config.Reputation.command, { help = 'Check your Halloween reputation' }, function(src)
        local rep = Rep.get(src)
        local tier, nextTier = Rep.tier(rep)
        local msg = ('Rank: **%s** (%s rep)'):format(tier.label, rep)
        if nextTier then msg = msg .. ('\nNext: %s at %s rep'):format(nextTier.label, nextTier.rep) end
        Bridge.Notify(src, msg, 'inform', 8000, '🏆 Halloween Reputation')
    end)
end

if Config.Debug then
    lib.addCommand('tot_force', {
        help = 'Force your next trick-or-treat outcome',
        params = { { name = 'outcome', type = 'string', help = 'robbery|normal|jackpot|laced|nobody|trick|cash|candybag' } },
        restricted = 'group.admin',
    }, function(src, args)
        Forced[src] = args.outcome
        Bridge.Notify(src, 'Next outcome forced: ' .. args.outcome)
    end)
    lib.addCommand('tot_resetcd', { help = 'Reset trick-or-treat cooldowns', restricted = 'group.admin' }, function(src)
        HouseCD, PlayerLast, PlayerHouseCD, PlayerWindow = {}, {}, {}, {}
        Bridge.Notify(src, 'All trick-or-treat cooldowns reset.')
    end)
    lib.addCommand('tot_laced', { help = 'Test laced candy effect', restricted = 'group.admin' }, function(src)
        triggerLaced(src)
    end)
end

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    endRobbery(src, 'dropped')
    Active[src], Busy[src], PendingAlert[src], Forced[src], LastCall[src] = nil, nil, nil, nil, nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, rob in pairs(Robberies) do deleteRobberyPeds(rob) end
end)
