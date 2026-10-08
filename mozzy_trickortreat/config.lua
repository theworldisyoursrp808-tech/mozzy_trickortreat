--[[
    ███╗   ███╗ ██████╗ ███████╗███████╗██╗   ██╗
    ████╗ ████║██╔═══██╗╚══███╔╝╚══███╔╝╚██╗ ██╔╝
    ██╔████╔██║██║   ██║  ███╔╝   ███╔╝  ╚████╔╝
    ██║╚██╔╝██║██║   ██║ ███╔╝   ███╔╝    ╚██╔╝
    ██║ ╚═╝ ██║╚██████╔╝███████╗███████╗   ██║
    ╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚══════╝   ╚═╝
                 🎃 TRICK OR TREAT 🎃

    Every chance/weight value below is configurable. Weights do NOT need to add
    up to 100 - each entry's odds are (its weight / total of all weights).
    "chance" values (single yes/no rolls) are percentages from 0 - 100.
]]

Config = {}

Config.Enabled = true            -- master switch
Config.Debug = false             -- prints + visible target zones + admin test commands

-- Optional season lock (server time). Set enabled = false to allow all year.
Config.Season = {
    enabled = false,
    startMonth = 10, startDay = 1,   -- Oct 1st
    endMonth = 11, endDay = 2,       -- Nov 2nd (inclusive)
}

-- Optional in-game night requirement (client clock). Cosmetic gate only.
Config.NightOnly = {
    enabled = false,
    startHour = 18,   -- 6 PM
    endHour = 5,      -- 5 AM
}

---------------------------------------------------------------------------
-- 🔑 ITEMS (spawn names) - change here if you rename items in ox_inventory
---------------------------------------------------------------------------
Config.Items = {
    chocolate     = 'mozzy_chocolate',
    gummyWorms    = 'mozzy_gummy_worms',
    candyCorn     = 'mozzy_candy_corn',
    lollipop      = 'mozzy_lollipop',
    gummyBears    = 'mozzy_gummy_bears',
    sourCandy     = 'mozzy_sour_candy',
    caramelApple  = 'mozzy_caramel_apple',
    candyPumpkins = 'mozzy_candy_pumpkins',
    candyBag      = 'mozzy_candy_bag',
    mysteryCandy  = 'mozzy_mystery_candy',
    lacedCandy    = 'mozzy_laced_candy',
}
local I = Config.Items

---------------------------------------------------------------------------
-- 🏠 TRICK OR TREAT INTERACTION
---------------------------------------------------------------------------
Config.Target = {
    label = 'Trick or Treat',
    icon = 'fas fa-ghost',
    iconColor = '#ff7a18',
    zoneRadius = 1.4,            -- size of the ox_target sphere on each door
    interactDistance = 2.0,      -- ox_target option distance
    loadDistance = 30.0,         -- target zones are only created when you are this close (lib.points)
}

Config.Blips = {
    enabled = false,             -- one small blip per house (can be a lot of blips!)
    sprite = 484, color = 47, scale = 0.15, shortRange = true,
    label = 'Trick or Treat',
}

Config.Cooldowns = {
    global = 20,                 -- seconds between ANY two knocks by the same player (anti-spam)
    house = 600,                 -- seconds a house is unavailable to EVERYONE after being knocked
    playerHouse = 3600,          -- seconds before the SAME player can knock the SAME house again
    maxPerPeriod = { enabled = true, amount = 25, period = 3600 }, -- max knocks per player per period (seconds)
}

Config.Knock = {
    duration = 3500,             -- ms knocking / ringing (progress circle)
    responseDelay = { min = 2000, max = 6000 }, -- ms random wait for an answer
    useProgress = true,
    progressLabel = 'Knocking...',
    waitingLabel = 'Waiting for someone to answer...',
    doorbellSound = { enabled = true, name = 'DOOR_BUZZ', set = 'MP_PLAYER_APARTMENT' },
    anims = {                    -- one is picked at random
        { dict = 'timetable@jimmy@doorknock@', clip = 'knockdoor_idle', flag = 49 },
    },
    handoverAnim = { dict = 'mp_common', player = 'givetake1_b', npc = 'givetake1_a' },
}

Config.DoorNPC = {
    enabled = true,              -- show a homeowner at the door
    distance = 1.1,              -- metres in front of the player
    stayTime = 3000,             -- ms the NPC stays after handing over
    models = {
        'a_f_m_ktown_02', 'a_f_m_fatwhite_01', 'a_f_y_hipster_02', 'a_m_m_malibu_01',
        'a_m_o_beach_01', 'a_f_y_bevhills_01', 'a_m_m_bevhills_02', 'a_f_m_bevhills_02',
        'a_m_y_hipster_01', 'a_f_o_genstreet_01',
    },
    scareModels = { 'u_m_y_zombie_01', 'u_m_m_jesus_01' }, -- used by "scare" tricks
}

---------------------------------------------------------------------------
-- 🎭 DOOR OUTCOMES (weighted)  - robbery is rolled separately (Config.Robbery.chance)
---------------------------------------------------------------------------
Config.Outcomes = {
    normal   = { enabled = true, weight = 55, rep = 2 },
    jackpot  = { enabled = true, weight = 6,  rep = 5, rolls = { min = 3, max = 5 }, quantityMultiplier = 2 },
    laced    = { enabled = true, weight = 3,  rep = 2, amount = { min = 1, max = 2 } }, -- hands out disguised laced candy
    nobody   = { enabled = true, weight = 14, rep = 0 },
    trick    = { enabled = true, weight = 10, rep = 1 },
    cash     = { enabled = true, weight = 7,  rep = 2, amount = { min = 5, max = 50 }, moneyType = 'cash' },
    candybag = { enabled = true, weight = 5,  rep = 3, amount = { min = 1, max = 1 } },
}

Config.Messages = {
    normal  = { 'Happy Halloween! Here you go.', 'Aww, cute costume! Take some candy.', 'Only one handful, okay?' },
    jackpot = { 'Take the whole bowl, I\'m going to bed!', 'JACKPOT! They dumped half the bowl in your bag.', 'Best costume tonight - grab as much as you want!' },
    laced   = { 'They hand you some... homemade candy.', 'A weird guy smiles and drops something into your bag.', 'Here, I made these myself. Enjoy~' },
    nobody  = { 'Nobody seems to be home.', 'The lights are off... nobody answered.', 'You hear the TV turn down. Nobody comes to the door.' },
    cash    = { 'We ran out of candy - here\'s some cash instead!', 'An old man hands you a few bucks. "Buy yourself something sweet."' },
    candybag = { 'They hand you a full Halloween candy bag!', 'Somebody pre-made goodie bags. Lucky you!' },
}

-- Tricks: effect = 'none' | 'scare' | 'shake' | 'trip' | 'egg'
Config.Tricks = {
    { weight = 30, effect = 'scare', message = 'BOO! Someone in a zombie mask leaps out at you!' },
    { weight = 25, effect = 'none',  message = 'They hand you a toothbrush. "Dentist\'s orders!"' },
    { weight = 20, effect = 'egg',   message = 'SPLAT! Somebody egged you from the window!' },
    { weight = 15, effect = 'trip',  message = 'You trip over a fake skeleton on the porch!' },
    { weight = 10, effect = 'shake', message = 'A blast of fog and a horn sends you jumping out of your skin!' },
}

---------------------------------------------------------------------------
-- 🍬 CANDY REWARDS (weighted) - used by "normal" / "jackpot" outcomes
---------------------------------------------------------------------------
Config.CandyRolls = { min = 1, max = 2 }   -- how many reward rolls a normal treat gives

Config.CandyRewards = {
    { item = I.chocolate,     weight = 22, min = 1, max = 2 },
    { item = I.gummyWorms,    weight = 18, min = 1, max = 2 },
    { item = I.candyCorn,     weight = 18, min = 1, max = 3 },
    { item = I.lollipop,      weight = 13, min = 1, max = 2 },
    { item = I.gummyBears,    weight = 9,  min = 1, max = 2 },
    { item = I.candyPumpkins, weight = 7,  min = 1, max = 2 },
    { item = I.sourCandy,     weight = 5,  min = 1, max = 2 },
    { item = I.mysteryCandy,  weight = 3,  min = 1, max = 1 },
    { item = I.caramelApple,  weight = 2,  min = 1, max = 1 },
    { item = I.candyBag,      weight = 2,  min = 1, max = 1 },
    { item = I.lacedCandy,    weight = 1,  min = 1, max = 1 },
}

---------------------------------------------------------------------------
-- 🎁 HALLOWEEN CANDY BAG (usable)
---------------------------------------------------------------------------
Config.CandyBag = {
    progress = {
        duration = 4000, label = 'Opening Halloween candy bag...',
        anim = { dict = 'missheistdocksprep1hold_cellphone', clip = 'static' },
        prop = nil,
    },
    rolls = { min = 3, max = 5 },
    rewards = {
        { item = I.chocolate,     weight = 22, min = 1, max = 3 },
        { item = I.gummyWorms,    weight = 18, min = 1, max = 3 },
        { item = I.candyCorn,     weight = 18, min = 2, max = 4 },
        { item = I.lollipop,      weight = 14, min = 1, max = 2 },
        { item = I.gummyBears,    weight = 12, min = 1, max = 3 },
        { item = I.candyPumpkins, weight = 10, min = 1, max = 3 },
        { item = I.sourCandy,     weight = 6,  min = 1, max = 2 },
    },
    rare = {
        chance = 12,              -- % chance per bag of a rare bonus
        rewards = {
            { item = I.caramelApple, weight = 50, min = 1, max = 1 },
            { item = I.mysteryCandy, weight = 35, min = 1, max = 2 },
            { item = I.candyBag,     weight = 15, min = 1, max = 1 },
        },
    },
    lacedChance = 4,              -- % chance the bag contains a laced candy
}

---------------------------------------------------------------------------
-- 😋 EATING CANDY (usable items)
-- hunger / thirst add to Qbox metadata (0-100), stress is removed.
-- lacedChance = hidden % chance THIS item is secretly laced when eaten.
---------------------------------------------------------------------------
local eatAnim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' }
Config.Consumables = {
    [I.chocolate]     = { duration = 3000, label = 'Eating chocolate...',     hunger = 8,  stress = 3, anim = eatAnim, prop = { model = 'prop_choc_ego', bone = 60309, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) } },
    [I.gummyWorms]    = { duration = 2500, label = 'Eating gummy worms...',   hunger = 5,  stress = 2, anim = eatAnim },
    [I.candyCorn]     = { duration = 2500, label = 'Eating candy corn...',    hunger = 4,  stress = 2, anim = eatAnim },
    [I.lollipop]      = { duration = 4000, label = 'Licking lollipop...',     hunger = 3,  stress = 4, anim = eatAnim },
    [I.gummyBears]    = { duration = 2500, label = 'Eating gummy bears...',   hunger = 5,  stress = 2, anim = eatAnim },
    [I.candyPumpkins] = { duration = 2500, label = 'Eating candy pumpkins...', hunger = 5, stress = 2, anim = eatAnim },
    [I.sourCandy]     = { duration = 2500, label = 'Eating sour candy...',    hunger = 3,  stress = 1, anim = eatAnim, sourShake = true },
    [I.caramelApple]  = { duration = 5000, label = 'Eating caramel apple...', hunger = 20, thirst = 2, stress = 5, anim = eatAnim },
    [I.mysteryCandy]  = { duration = 2500, label = 'Eating mystery candy...', hunger = 4,  stress = 2, anim = eatAnim, lacedChance = 15 },
    [I.lacedCandy]    = { duration = 2500, label = 'Eating Halloween candy...', hunger = 4, stress = 2, anim = eatAnim, laced = true },
}

---------------------------------------------------------------------------
-- 😵 LACED CANDY
---------------------------------------------------------------------------
Config.LacedCandy = {
    enabled = true,
    chance = 2,                   -- % chance each candy handed out at a door is swapped for a laced one
    effectDelay = { min = 20, max = 40 },      -- seconds before symptoms start
    effectDuration = { min = 90, max = 150 },  -- seconds the high lasts
    passOutChance = 40,           -- % chance of passing out
    passOutAt = 0.55,             -- fraction of the duration when the pass out happens
    unconsciousTime = { min = 12, max = 20 },  -- seconds unconscious
    fadeOutTime = 15,             -- seconds for remaining effects to wear off at the end
    onsetMessage = 'You feel... a little funny.',
    passOutMessage = 'Everything goes dark...',
    wakeMessage = 'You come to with a pounding headache.',
    endMessage = 'Your head finally clears.',

    effects = {
        timecycle = { enabled = true, modifiers = { 'spectator5', 'drug_wobbly', 'DRUG_gas_huffin' }, maxStrength = 0.9 },
        postFx = { enabled = true, names = { 'DrugsMichaelAliensFight', 'DrugsTrevorClownsFight' } },
        cameraShake = { enabled = true, name = 'DRUNK_SHAKE', intensity = 1.2 },
        motionBlur = { enabled = true },
        walkStyle = { enabled = true, clipset = 'move_m@drunk@verydrunk' },
        noSprint = { enabled = true },
        movementSpeed = { enabled = true, min = 0.75, max = 1.15 }, -- random move-rate drift
        randomRagdoll = { enabled = true, chance = 6, interval = 8 },   -- % chance every interval seconds
        randomAnims = {
            enabled = true, chance = 20, interval = 12,
            list = {
                { dict = 'missfam5_yoga', clip = 'c1_pose' },
                { dict = 'anim@mp_player_intcelebrationmale@face_palm', clip = 'face_palm' },
                { dict = 'move_m@_idles@shake_off', clip = 'shakeoff_1' },
            },
        },
    },
    godmodeWhileUnconscious = false,
}

---------------------------------------------------------------------------
-- 🔪 ROBBERY SETUP
---------------------------------------------------------------------------
Config.Robbery = {
    enabled = true,
    chance = 35,                   -- % chance ANY knock turns into a robbery setup (rolled before outcomes)
    minNPCs = 1,
    maxNPCs = 4,
    spawnDistance = { min = 12.0, max = 20.0 }, -- metres from the player
    surroundRadius = 2.6,
    approachTimeout = 25,         -- seconds for robbers to reach the player
    cooperateTime = 15,           -- seconds the player has to choose
    leaveTime = 20,               -- seconds robbers take walking off before being deleted
    timeout = 240,                -- hard limit (seconds) for the whole event
    despawnDistance = 150.0,      -- player this far away = event cleaned up
    bodyCleanupDelay = 30,        -- seconds dead robbers stay before deletion
    lootOnDown = true,            -- if the player goes down during the fight, robbers take cash + candy and leave
    messages = {
        approach = 'You hear footsteps behind you... this was a setup!',
        demand = '"Trick or treat, sweetheart. Empty your pockets!"',
    },

    models = {
        'g_m_y_lost_01', 'g_m_y_lost_02', 'g_m_y_mexgoon_01', 'g_m_y_ballasout_01',
        'g_m_y_famca_01', 'a_m_y_methhead_01', 'g_m_y_salvagoon_01', 'u_m_y_zombie_01',
    },
    weapons = {
        { weapon = 'WEAPON_KNIFE',   weight = 35, ammo = 0 },
        { weapon = 'WEAPON_BAT',     weight = 30, ammo = 0 },
        { weapon = 'WEAPON_CROWBAR', weight = 20, ammo = 0 },
        --{ weapon = 'WEAPON_PISTOL',  weight = 15, ammo = 60 },
    },
    npc = {
        health = 200,             -- 100 - 1000
        armor = 0,
        accuracy = 25,            -- 0 - 100
        combatAbility = 1,        -- 0 poor, 1 average, 2 professional
        combatMovement = 2,       -- 0 stationary, 1 defensive, 2 will advance, 3 will retreat
        combatRange = 0,          -- 0 near, 1 medium, 2 far
        canBeKnockedDown = true,
    },

    cashTheft = {
        moneyType = 'cash',
        percent = { min = 20, max = 50 },  -- % of carried cash
        min = 25, max = 2500,             -- clamp in $
        hostileIfBroke = 70,              -- % chance robbers attack if you have no cash
    },
    candyTheft = {
        items = { I.chocolate, I.candyCorn, I.gummyWorms, I.lollipop, I.gummyBears, I.sourCandy, I.candyPumpkins, I.caramelApple, I.candyBag, I.mysteryCandy, I.lacedCandy },
        amount = { min = 3, max = 8 },    -- total pieces taken
        hostileIfNone = 80,               -- % chance robbers attack if you have no candy
    },
    run = {
        attackOnRun = true,               -- true = running ALWAYS makes them chase & attack
        chaseChance = 100,                -- only used when attackOnRun = false (% chance they chase)
        autoRunDistance = 8.0,            -- moving this far from the robbers during the demand counts as running
        escapeDistance = 60.0,            -- get this far away to escape
    },
}

---------------------------------------------------------------------------
-- 🚓 POLICE ALERT (see shared/bridge.lua for dispatch systems)
---------------------------------------------------------------------------
Config.PoliceAlert = {
    enabled = true,
    chance = 25,                  -- % chance a robbery is reported
    delay = 5,                    -- seconds after the robbery starts
    system = 'auto',              -- 'auto' | 'ps-dispatch' | 'cd_dispatch' | 'qs-dispatch' | 'core_dispatch' | 'rcore_dispatch' | 'qbx' | 'custom'
    jobs = { 'police', 'sheriff' },
    jobType = 'leo',              -- used by the 'qbx' fallback
    code = '10-31',
    title = 'Suspicious Activity / Armed Robbery Reported',
    description = 'Caller reports a group of armed individuals robbing a trick-or-treater.',
    suspectDescription = true,
    blip = { sprite = 484, color = 1, scale = 1.0, radius = 80.0, time = 90 },
}

---------------------------------------------------------------------------
-- 🏆 REPUTATION (Qbox player metadata - no SQL needed)
---------------------------------------------------------------------------
Config.Reputation = {
    enabled = true,
    metadataKey = 'mozzy_tot_rep',
    command = 'totrep',
    gains = {
        robberyCooperated = 1,
        robberyEscaped = 6,
        robberyDefeated = 12,
    },
    -- quantityBonus adds to every reward quantity, rareMultiplier multiplies jackpot/candybag weights
    -- bonus = extra % roll for a special item on every successful treat
    tiers = {
        { rep = 0,    label = 'Trick-or-Treater', quantityBonus = 0, rareMultiplier = 1.0 },
        { rep = 100,  label = 'Candy Hunter',     quantityBonus = 0, rareMultiplier = 1.15 },
        { rep = 250,  label = 'Halloween Regular', quantityBonus = 1, rareMultiplier = 1.25 },
        { rep = 500,  label = 'Candy Collector',  quantityBonus = 1, rareMultiplier = 1.4, bonus = { chance = 5, item = I.caramelApple, amount = 1 } },
        { rep = 1000, label = 'Pumpkin King',     quantityBonus = 2, rareMultiplier = 1.6, bonus = { chance = 8, item = I.candyBag, amount = 1 } },
    },
}

---------------------------------------------------------------------------
-- 🛡️ SECURITY
---------------------------------------------------------------------------
Config.Security = {
    maxDistance = 4.0,            -- server-side max distance from the door when knocking
    finishDistance = 8.0,         -- max distance from the door when the treat is handed over
    timingTolerance = 1000,       -- ms of latency allowance on minimum timings
    rateLimit = 800,              -- ms between server requests per player
    logExploits = true,
    dropOnExploit = false,        -- kick players that send impossible requests
}

---------------------------------------------------------------------------
-- 📍 TRICK OR TREAT LOCATIONS
-- Plain vector3 OR { coords = vector3(...), label = 'Optional' }
-- (defaults imported + de-duplicated from gl-halloween door list)
---------------------------------------------------------------------------
Config.TrickOrTreatLocations = {
    vector3(-1112.25, -1578.40, 7.70),
    vector3(-1114.34, -1579.47, 7.70),
    vector3(-1114.95, -1577.57, 3.56),
    vector3(373.93, 427.88, 144.73),
    vector3(346.44, 440.63, 146.78),
    vector3(331.41, 465.68, 150.26),
    vector3(316.07, 501.48, 152.23),
    vector3(325.34, 537.40, 152.92),
    vector3(223.65, 514.00, 139.82),
    vector3(119.23, 494.32, 146.39),
    vector3(80.12, 485.87, 147.25),
    vector3(57.87, 450.09, 146.08),
    vector3(42.98, 468.65, 147.15),
    vector3(-7.61, 468.40, 144.92),
    vector3(-66.48, 490.80, 143.74),
    vector3(-109.86, 502.62, 142.35),
    vector3(-174.72, 502.60, 136.47),
    vector3(8.66, 539.83, 175.08),
    vector3(84.86, 561.97, 181.82),
    vector3(119.08, 564.55, 183.00),
    vector3(215.65, 620.19, 186.67),
    vector3(231.96, 672.45, 189.00),
    vector3(-230.55, 488.46, 127.82),
    vector3(-311.92, 474.82, 110.87),
    vector3(-166.72, 424.66, 110.86),
    vector3(-297.89, 380.32, 111.15),
    vector3(-328.29, 369.91, 109.06),
    vector3(-371.79, 344.12, 108.99),
    vector3(-409.42, 341.69, 107.96),
    vector3(-349.24, 514.65, 119.70),
    vector3(-386.68, 504.57, 119.46),
    vector3(-406.49, 567.51, 123.65),
    vector3(-459.11, 537.52, 120.51),
    vector3(-500.55, 552.23, 119.66),
    vector3(-520.27, 594.22, 119.89),
    vector3(-475.14, 585.83, 127.73),
    vector3(-559.41, 664.38, 144.51),
    vector3(-605.94, 672.87, 150.65),
    vector3(-579.73, 733.11, 183.26),
    vector3(-655.08, 803.48, 198.04),
    vector3(-746.91, 808.44, 214.08),
    vector3(-597.13, 851.83, 210.48),
    vector3(-494.42, 795.82, 183.39),
    vector3(-495.46, 738.96, 162.08),
    vector3(-533.05, 709.09, 152.13),
    vector3(-686.18, 596.12, 142.69),
    vector3(-732.78, 594.09, 141.19),
    vector3(-752.81, 620.97, 141.56),
    vector3(-699.11, 706.78, 157.00),
    vector3(-476.86, 648.34, 143.44),
    vector3(-400.10, 665.43, 162.88),
    vector3(-353.28, 667.85, 168.12),
    vector3(-299.85, 635.06, 174.73),
    vector3(-293.53, 601.43, 180.63),
    vector3(-232.61, 588.76, 189.59),
    vector3(-189.13, 617.61, 198.71),
    vector3(-185.31, 591.82, 196.87),
    vector3(-126.83, 588.74, 203.57),
    vector3(-527.07, 517.58, 111.99),
    vector3(-580.68, 492.39, 107.95),
    vector3(-640.75, 519.71, 108.74),
    vector3(-667.32, 471.97, 113.19),
    vector3(-678.86, 511.73, 112.58),
    vector3(-718.13, 449.26, 105.96),
    vector3(-762.30, 431.53, 99.23),
    vector3(-784.20, 459.13, 99.23),
    vector3(-824.72, 422.08, 91.17),
    vector3(-843.20, 466.75, 86.65),
    vector3(-848.96, 508.85, 89.87),
    vector3(-883.86, 518.02, 91.49),
    vector3(-905.25, 587.44, 100.04),
    vector3(-924.66, 561.78, 99.00),
    vector3(-947.94, 568.20, 100.53),
    vector3(-974.39, 582.12, 101.98),
    vector3(-1022.67, 587.36, 102.28),
    vector3(-1107.26, 593.98, 103.50),
    vector3(-1125.42, 548.67, 101.62),
    vector3(-1146.43, 545.89, 100.95),
    vector3(-1193.07, 563.76, 99.39),
    vector3(-970.97, 456.05, 78.86),
    vector3(-967.30, 510.33, 81.12),
    vector3(-987.42, 487.65, 81.32),
    vector3(-1052.02, 432.39, 76.12),
    vector3(-1094.18, 427.41, 74.93),
    vector3(-1122.76, 485.68, 81.21),
    vector3(-1174.95, 440.32, 85.90),
    vector3(-1215.70, 458.47, 90.90),
    vector3(-1294.42, 454.86, 96.53),
    vector3(-1308.19, 449.26, 100.02),
    vector3(-1413.60, 462.29, 108.26),
    vector3(-1404.86, 561.22, 124.46),
    vector3(-1346.74, 560.86, 129.58),
    vector3(-1366.83, 611.17, 132.96),
    vector3(-1337.76, 606.11, 133.43),
    vector3(-1291.72, 650.07, 140.55),
    vector3(-1248.57, 643.02, 141.75),
    vector3(-1241.25, 674.06, 141.86),
    vector3(-1219.12, 665.68, 143.58),
    vector3(-1197.68, 693.69, 146.44),
    vector3(-1165.65, 727.11, 154.66),
    vector3(-1130.03, 784.15, 162.94),
    vector3(-1100.42, 797.42, 166.31),
    vector3(-1056.18, 761.75, 166.37),
    vector3(-999.09, 816.50, 172.10),
    vector3(-962.65, 813.90, 176.62),
    vector3(-912.37, 777.61, 186.06),
    vector3(-867.36, 785.29, 190.98),
    vector3(-824.05, 806.05, 201.83),
    vector3(-1065.28, 727.38, 164.52),
    vector3(-1019.86, 719.11, 163.05),
    vector3(-931.44, 691.45, 152.52),
    vector3(-908.86, 693.88, 150.49),
    vector3(-885.51, 699.33, 150.32),
    vector3(-853.56, 696.36, 147.83),
    vector3(-819.35, 696.51, 147.15),
    vector3(-765.37, 650.64, 144.75),
    vector3(1777.18, 3737.91, 33.71),
    vector3(1748.65, 3783.68, 33.88),
    vector3(1639.65, 3731.57, 34.12),
    vector3(1642.62, 3727.40, 34.12),
    vector3(1691.53, 3866.06, 33.96),
    vector3(1700.34, 3867.13, 33.95),
    vector3(1733.62, 3895.49, 34.61),
    vector3(1786.60, 3913.04, 33.96),
    vector3(1803.44, 3913.95, 36.11),
    vector3(1809.08, 3907.70, 32.80),
    vector3(1838.58, 3907.40, 32.38),
    vector3(1841.91, 3928.62, 32.77),
    vector3(1880.29, 3920.65, 32.26),
    vector3(1895.44, 3873.76, 31.80),
    vector3(1888.47, 3892.89, 32.22),
    vector3(1943.68, 3804.37, 31.09),
    vector3(-374.51, 6190.96, 30.78),
    vector3(-356.90, 6207.45, 30.89),
    vector3(-347.48, 6225.40, 30.94),
    vector3(-360.12, 6260.69, 30.95),
    vector3(-407.24, 6314.19, 27.99),
    vector3(-359.73, 6334.64, 28.90),
    vector3(-332.52, 6302.32, 32.13),
    vector3(-302.24, 6326.92, 31.94),
    vector3(-280.51, 6350.70, 31.65),
    vector3(-247.74, 6370.15, 30.90),
    vector3(-227.14, 6377.43, 30.81),
    vector3(-272.45, 6400.94, 30.46),
    vector3(-246.13, 6413.95, 30.51),
    vector3(-213.85, 6396.29, 32.13),
    vector3(-188.93, 6409.47, 31.35),
    vector3(-215.05, 6444.32, 30.36),
    vector3(-15.29, 6557.61, 32.29),
    vector3(4.47, 6568.09, 32.12),
    vector3(30.94, 6596.58, 31.86),
    vector3(-9.35, 6654.24, 30.44),
    vector3(-41.70, 6637.40, 30.14),
    vector3(-34.11, -1846.87, 25.24),
    vector3(-20.60, -1858.61, 24.46),
    vector3(21.13, -1844.65, 23.65),
    vector3(-5.17, -1871.82, 23.20),
    vector3(4.92, -1884.34, 22.75),
    vector3(46.01, -1864.28, 22.33),
    vector3(23.07, -1896.69, 22.05),
    vector3(54.56, -1873.20, 21.88),
    vector3(38.99, -1911.64, 21.00),
    vector3(56.54, -1922.60, 20.96),
    vector3(100.86, -1912.48, 20.45),
    vector3(72.05, -1938.94, 20.42),
    vector3(76.55, -1948.38, 20.22),
    vector3(85.69, -1959.40, 20.17),
    vector3(114.54, -1961.07, 20.36),
    vector3(126.51, -1929.90, 20.43),
    vector3(104.08, -1885.35, 23.37),
    vector3(130.79, -1853.33, 24.33),
    vector3(150.05, -1864.90, 23.63),
    vector3(127.76, -1897.18, 22.71),
    vector3(148.67, -1904.12, 22.54),
    vector3(171.31, -1871.40, 23.45),
    vector3(192.45, -1883.45, 24.15),
    vector3(179.09, -1924.26, 20.42),
    vector3(165.54, -1945.03, 19.27),
    vector3(148.88, -1960.53, 18.54),
    vector3(143.86, -1968.96, 17.91),
    vector3(236.57, -2045.96, 17.43),
    vector3(256.69, -2023.40, 18.38),
    vector3(279.56, -1993.75, 19.89),
    vector3(291.36, -1980.29, 20.65),
    vector3(295.86, -1971.99, 21.82),
    vector3(312.07, -1956.29, 23.67),
    vector3(324.42, -1937.93, 24.06),
    vector3(319.88, -1854.21, 26.56),
    vector3(329.25, -1845.75, 26.80),
    vector3(339.09, -1829.26, 27.38),
    vector3(348.77, -1820.53, 27.94),
    vector3(440.25, -1829.99, 27.41),
    vector3(427.45, -1841.81, 27.50),
    vector3(412.55, -1856.12, 26.37),
    vector3(399.58, -1864.59, 25.77),
    vector3(385.06, -1881.49, 25.09),
    vector3(495.37, -1823.46, 27.92),
    vector3(512.52, -1790.43, 27.97),
    vector3(472.18, -1775.28, 28.12),
    vector3(479.37, -1735.73, 28.20),
    vector3(489.68, -1713.97, 28.72),
    vector3(500.45, -1697.03, 28.83),
    vector3(405.31, -1751.11, 28.76),
    vector3(419.15, -1735.93, 28.66),
    vector3(431.09, -1725.81, 28.65),
    vector3(443.41, -1707.24, 28.76),
    vector3(332.92, -1741.04, 28.78),
    vector3(320.86, -1760.21, 28.69),
    vector3(304.51, -1775.37, 28.20),
    vector3(300.01, -1784.35, 27.49),
    vector3(288.71, -1792.51, 27.17),
    vector3(198.20, -1725.60, 28.71),
    vector3(216.56, -1717.31, 28.73),
    vector3(249.61, -1730.61, 28.72),
    vector3(223.07, -1702.96, 28.74),
    vector3(257.28, -1723.16, 28.70),
    vector3(269.30, -1712.88, 28.72),
    vector3(252.80, -1670.62, 28.71),
    vector3(240.78, -1687.92, 28.74),
    vector3(1060.57, -378.40, 67.28),
    vector3(1029.08, -408.58, 65.18),
    vector3(1044.27, -449.12, 65.30),
    vector3(1010.52, -423.34, 64.40),
    vector3(1014.43, -469.01, 63.56),
    vector3(987.85, -433.59, 62.94),
    vector3(967.12, -451.58, 61.84),
    vector3(970.17, -502.16, 61.19),
    vector3(943.95, -463.34, 60.45),
    vector3(945.99, -518.91, 59.67),
    vector3(921.91, -478.17, 60.13),
    vector3(906.48, -490.10, 58.49),
    vector3(878.56, -498.10, 57.14),
    vector3(862.47, -509.76, 56.38),
    vector3(850.82, -532.65, 56.98),
    vector3(893.16, -540.62, 57.56),
    vector3(844.06, -563.20, 56.88),
    vector3(861.78, -583.19, 57.21),
    vector3(886.88, -608.09, 57.49),
    vector3(903.26, -615.67, 57.50),
    vector3(928.97, -639.68, 57.29),
    vector3(943.52, -653.42, 57.47),
    vector3(960.41, -669.75, 57.50),
    vector3(970.89, -701.39, 57.53),
    vector3(979.31, -716.30, 57.27),
    vector3(997.11, -729.27, 56.86),
    vector3(1090.01, -484.24, 64.71),
    vector3(1098.59, -464.70, 66.37),
    vector3(1099.41, -438.34, 66.83),
    vector3(1100.84, -411.40, 66.60),
    vector3(1046.23, -497.91, 63.13),
    vector3(1051.85, -470.53, 62.95),
    vector3(1056.18, -448.89, 65.31),
    vector3(964.15, -596.05, 58.95),
    vector3(976.36, -579.23, 58.69),
    vector3(1009.91, -572.39, 59.64),
    vector3(1229.29, -725.46, 59.84),
    vector3(1222.60, -697.06, 59.86),
    vector3(1221.36, -669.04, 62.54),
    vector3(1206.82, -620.28, 65.49),
    vector3(1200.94, -575.83, 68.19),
    vector3(1241.92, -566.23, 68.71),
    vector3(1240.51, -601.58, 68.83),
    vector3(1251.30, -621.66, 68.46),
    vector3(1265.59, -648.35, 66.97),
    vector3(1270.99, -683.50, 65.08),
    vector3(1265.16, -703.12, 63.62),
    vector3(1251.33, -515.73, 68.40),
    vector3(1251.59, -494.16, 68.96),
    vector3(1260.58, -479.61, 69.24),
    vector3(1266.29, -457.90, 69.57),
    vector3(1263.20, -429.37, 68.86),
    vector3(1301.04, -574.02, 70.78),
    vector3(1302.90, -527.92, 70.51),
    vector3(1323.52, -582.87, 72.30),
    vector3(1348.26, -547.14, 72.94),
    vector3(1341.79, -597.49, 73.75),
    vector3(1367.32, -605.94, 73.76),
    vector3(1385.77, -593.06, 73.54),
    vector3(1388.75, -569.70, 73.55),
    vector3(1372.82, -555.70, 73.74),
    vector3(1328.18, -535.96, 71.49),
    vector3(1203.47, -1671.02, 41.76),
    vector3(1220.29, -1658.95, 47.68),
    vector3(1252.81, -1638.59, 52.18),
    vector3(1276.39, -1628.86, 53.83),
    vector3(1297.36, -1618.01, 53.63),
    vector3(1336.96, -1579.08, 53.53),
    vector3(1437.17, -1492.46, 62.68),
    vector3(1404.58, -1496.26, 59.01),
    vector3(1411.39, -1490.81, 59.71),
    vector3(1390.94, -1508.09, 57.49),
    vector3(1381.91, -1544.80, 56.16),
    vector3(1338.29, -1524.48, 53.66),
    vector3(1315.86, -1526.36, 50.85),
    vector3(1327.48, -1552.90, 53.10),
    vector3(1286.64, -1604.19, 53.87),
    vector3(1230.73, -1590.91, 52.82),
    vector3(1261.35, -1616.60, 53.79),
    vector3(1245.14, -1626.56, 52.33),
    vector3(1210.68, -1607.11, 49.58),
    vector3(1214.29, -1644.03, 47.69),
    vector3(1193.24, -1622.40, 44.27),
    vector3(1193.29, -1656.07, 42.08),
    vector3(1258.86, -1761.50, 48.71),
    vector3(1250.82, -1734.79, 51.08),
    vector3(1294.98, -1739.77, 53.32),
    vector3(1289.49, -1711.03, 54.54),
    vector3(1314.77, -1732.93, 53.75),
    vector3(1316.89, -1698.85, 57.27),
    vector3(1355.07, -1690.53, 59.54),
    vector3(1365.33, -1721.38, 64.68),}
