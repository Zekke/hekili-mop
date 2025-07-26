-- MageFrost.lua
-- Updated May 28, 2025 - Modern Structure
-- Mists of Pandaria module for Mage: Frost spec

-- MoP: Use UnitClass instead of UnitClassBase
local _, playerClass = UnitClass('player')
if playerClass ~= 'MAGE' then return end

local addon, ns = ...
local Hekili = _G[ "Hekili" ]
    
-- Early return if Hekili is not available
if not Hekili or not Hekili.NewSpecialization then return end
    
local class = Hekili.Class
local state = Hekili.State

local strformat = string.format
    local FindUnitBuffByID, FindUnitDebuffByID = ns.FindUnitBuffByID, ns.FindUnitDebuffByID
    local PTR = ns.PTR

    local spec = Hekili:NewSpecialization( 64, true )



-- Register resources
spec:RegisterResource( 0 ) -- Mana = 0 in MoP

-- ===================
-- ENHANCED COMBAT LOG EVENT TRACKING
-- ===================

local frostCombatLogFrame = CreateFrame("Frame")
local frostCombatLogEvents = {}

local function RegisterFrostCombatLogEvent(event, handler)
    if not frostCombatLogEvents[event] then
        frostCombatLogEvents[event] = {}
        frostCombatLogFrame:RegisterEvent(event)
    end
    
    tinsert(frostCombatLogEvents[event], handler)
end

frostCombatLogFrame:SetScript("OnEvent", function(self, event, ...)
    local handlers = frostCombatLogEvents[event]
    if handlers then
        for _, handler in ipairs(handlers) do
            handler(event, ...)
        end
    end
end)

-- Frost-specific tracking variables
local frostbolt_casts = 0
local brain_freeze_procs = 0
local fingers_of_frost_procs = 0
local icy_veins_activations = 0
local water_elemental_summoned = 0

RegisterFrostCombatLogEvent("COMBAT_LOG_EVENT_UNFILTERED", function(event, ...)
    local _, subEvent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellId, spellName, spellSchool, auraType = CombatLogGetCurrentEventInfo()
    
    if sourceGUID ~= UnitGUID("player") then return end
    
    local now = GetTime()
    
    -- FROST PROC TRACKING
    if subEvent == "SPELL_AURA_APPLIED" then
        if spellId == 44549 then -- Brain Freeze (correct spell ID)
            brain_freeze_procs = brain_freeze_procs + 1
            ns.last_brain_freeze = now
            applyBuff( "brain_freeze" )
        elseif spellId == 44544 then -- Fingers of Frost
            fingers_of_frost_procs = fingers_of_frost_procs + 1
            ns.last_fingers_of_frost = now
            applyBuff( "fingers_of_frost" )
        elseif spellId == 12472 then -- Icy Veins
            icy_veins_activations = icy_veins_activations + 1
            ns.last_icy_veins = now
            applyBuff( "icy_veins" )
        end
    end
    
    -- FROSTBOLT CAST TRACKING for mastery calculation
    if subEvent == "SPELL_CAST_SUCCESS" then
        if spellId == 116 then -- Frostbolt
            frostbolt_casts = frostbolt_casts + 1
            ns.last_frostbolt = now
        elseif spellId == 30455 then -- Ice Lance
            ns.last_ice_lance = now
            -- Track if Ice Lance was enhanced by Fingers of Frost
            if FindUnitBuffByID("player", 44544) then
                ns.ice_lance_empowered = true
            end
        elseif spellId == 31687 then -- Summon Water Elemental
            water_elemental_summoned = water_elemental_summoned + 1
            ns.last_water_elemental = now
        end
    end
    
    -- SHATTER COMBO TRACKING
    if subEvent == "SPELL_DAMAGE" and spellId == 30455 then -- Ice Lance damage
        local critical = select(21, CombatLogGetCurrentEventInfo())
        if critical then
            ns.last_ice_lance_crit = now
        end
    end
end)

-- Enhanced Frost-specific combat log tracking 
RegisterFrostCombatLogEvent("COMBAT_LOG_EVENT_UNFILTERED", function(event, ...)
    local _, subEvent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellId, spellName, spellSchool, auraType = CombatLogGetCurrentEventInfo()
    
    if sourceGUID ~= UnitGUID("player") then return end
    
    local now = GetTime()
    
    -- Enhanced Frost Proc Tracking
    if subEvent == "SPELL_AURA_APPLIED" then
        -- Brain Freeze proc tracking
        if spellId == 44549 then -- Brain Freeze
            brain_freeze_procs = brain_freeze_procs + 1
            ns.last_brain_freeze = now
            state.applyBuff( "brain_freeze" )
            
            -- Track Brain Freeze for Frostfire Bolt priority
            if state.settings.brain_freeze_priority then
                ns.brain_freeze_available = true
            end
        end
        
        -- Fingers of Frost proc tracking
        if spellId == 44544 then -- Fingers of Frost
            fingers_of_frost_procs = fingers_of_frost_procs + 1
            ns.last_fingers_of_frost = now
            state.applyBuff( "fingers_of_frost" )
            
            -- Track Fingers of Frost stacks for Ice Lance priority
            local stacks = select(3, FindUnitBuffByID("player", 44544)) or 1
            ns.fingers_of_frost_stacks = stacks
        end
        
        -- Icy Veins tracking
        if spellId == 12472 then -- Icy Veins
            icy_veins_activations = icy_veins_activations + 1
            ns.last_icy_veins = now
            state.applyBuff( "icy_veins" )
        end
        
        -- Rune of Power tracking
        if spellId == 116011 then -- Rune of Power
            ns.last_rune_of_power = now
            state.applyBuff( "rune_of_power" )
        end
        
        -- Invocation tracking
        if spellId == 114003 then -- Invocation
            ns.last_invocation = now
            state.applyBuff( "invocation" )
        end
    end
    
    -- Enhanced Cast Success Tracking
    if subEvent == "SPELL_CAST_SUCCESS" then
        -- Frostbolt cast tracking
        if spellId == 116 then -- Frostbolt
            frostbolt_casts = frostbolt_casts + 1
            ns.last_frostbolt = now
            
            -- Track Frostbolt for mastery and proc generation
            ns.frostbolt_cast_time = now
        end
        
        -- Ice Lance cast tracking
        if spellId == 30455 then -- Ice Lance
            ns.last_ice_lance = now
            
            -- Track if Ice Lance was enhanced by Fingers of Frost
            if FindUnitBuffByID("player", 44544) then
                ns.ice_lance_empowered = true
                ns.fingers_of_frost_consumed = true
            end
        end
        
        -- Frostfire Bolt cast tracking
        if spellId == 44614 then -- Frostfire Bolt
            ns.last_frostfire_bolt = now
            ns.brain_freeze_consumed = true
        end
        
        -- Water Elemental summon tracking
        if spellId == 31687 then -- Summon Water Elemental
            water_elemental_summoned = water_elemental_summoned + 1
            ns.last_water_elemental = now
        end
        
        -- Frozen Orb cast tracking
        if spellId == 84714 then -- Frozen Orb
            ns.last_frozen_orb = now
            state.applyBuff( "frozen_orb" )
        end
        
        -- Deep Freeze cast tracking
        if spellId == 44572 then -- Deep Freeze
            ns.last_deep_freeze = now
            state.applyDebuff( "target", "deep_freeze" )
        end
        
        -- Blizzard cast tracking
        if spellId == 10 then -- Blizzard
            ns.last_blizzard = now
            state.applyDebuff( "target", "blizzard" )
        end
        
        -- Nether Tempest cast tracking
        if spellId == 114923 then -- Nether Tempest
            ns.last_nether_tempest = now
            state.applyDebuff( "target", "nether_tempest" )
        end
        
        -- Frost Bomb cast tracking
        if spellId == 112948 then -- Frost Bomb
            ns.last_frost_bomb = now
            state.applyDebuff( "target", "frost_bomb" )
        end
    end
    
    -- Enhanced Damage Tracking for Shatter mechanics
    if subEvent == "SPELL_DAMAGE" then
        -- Ice Lance damage tracking
        if spellId == 30455 then -- Ice Lance
            local critical = select(21, CombatLogGetCurrentEventInfo())
            if critical then
                ns.last_ice_lance_crit = now
                ns.ice_lance_crits = (ns.ice_lance_crits or 0) + 1
            end
        end
        
        -- Frostbolt damage tracking
        if spellId == 116 then -- Frostbolt
            local critical = select(21, CombatLogGetCurrentEventInfo())
            if critical then
                ns.last_frostbolt_crit = now
                ns.frostbolt_crits = (ns.frostbolt_crits or 0) + 1
            end
        end
        
        -- Frostfire Bolt damage tracking
        if spellId == 44614 then -- Frostfire Bolt
            local critical = select(21, CombatLogGetCurrentEventInfo())
            if critical then
                ns.last_frostfire_bolt_crit = now
                ns.frostfire_bolt_crits = (ns.frostfire_bolt_crits or 0) + 1
            end
        end
    end
    
    -- Enhanced Aura Removal Tracking
    if subEvent == "SPELL_AURA_REMOVED" then
        -- Brain Freeze removal tracking
        if spellId == 44549 then -- Brain Freeze
            ns.brain_freeze_available = false
            ns.brain_freeze_consumed = false
        end
        
        -- Fingers of Frost removal tracking
        if spellId == 44544 then -- Fingers of Frost
            ns.fingers_of_frost_stacks = 0
            ns.fingers_of_frost_consumed = false
        end
        
        -- Icy Veins removal tracking
        if spellId == 12472 then -- Icy Veins
            ns.icy_veins_active = false
        end
    end
end)

-- ===================
-- ENHANCED TIER SETS AND GEAR REGISTRATION  
-- ===================

-- Tier 14 - Regalia of the Burning Scroll (Complete Coverage)
spec:RegisterGear( "tier14", 85370, 85371, 85372, 85373, 85369 ) -- Normal
spec:RegisterGear( "tier14_lfr", 89335, 89336, 89337, 89338, 89339 ) -- LFR versions
spec:RegisterGear( "tier14_heroic", 90465, 90466, 90467, 90468, 90469 ) -- Heroic versions

-- Tier 15 - Kirin Tor Garb (Complete Coverage)
spec:RegisterGear( "tier15", 95893, 95894, 95895, 95897, 95892 ) -- Normal
spec:RegisterGear( "tier15_lfr", 95316, 95317, 95318, 95319, 95320 ) -- LFR versions
spec:RegisterGear( "tier15_heroic", 96626, 96627, 96628, 96629, 96630 ) -- Heroic versions
spec:RegisterGear( "tier15_thunderforged", 97261, 97262, 97263, 97264, 97265 ) -- Thunderforged versions

-- Tier 16 - Chronomancer Regalia (Complete Coverage)
spec:RegisterGear( "tier16", 99125, 99126, 99127, 99128, 99129 ) -- Normal
spec:RegisterGear( "tier16_lfr", 99780, 99781, 99782, 99783, 99784 ) -- LFR versions
spec:RegisterGear( "tier16_flex", 100290, 100291, 100292, 100293, 100294 ) -- Flexible versions
spec:RegisterGear( "tier16_heroic", 100945, 100946, 100947, 100948, 100949 ) -- Heroic versions
spec:RegisterGear( "tier16_mythic", 101610, 101611, 101612, 101613, 101614 ) -- Mythic versions

-- Legendary Items (MoP specific)
spec:RegisterGear( "legendary_cloak", 102246 ) -- Jina-Kang, Kindness of Chi-Ji (DPS version)
spec:RegisterGear( "legendary_meta_gem", 101817 ) -- Capacitive Primal Diamond

-- Notable Trinkets and Weapons (Frost-specific)
spec:RegisterGear( "unerring_vision_of_lei_shen", 94530 ) -- Throne of Thunder trinket
spec:RegisterGear( "breath_of_the_hydra", 105609 ) -- SoO trinket
spec:RegisterGear( "dysmorphic_samophlange_of_discontinuity", 105691 ) -- SoO trinket
spec:RegisterGear( "haromms_talisman", 102664 ) -- SoO trinket
spec:RegisterGear( "purified_bindings_of_immerseus", 102293 ) -- SoO trinket

-- Frost Weapons
spec:RegisterGear( "gao_lei_shao_do", 89235 ) -- MSV staff
spec:RegisterGear( "nadagast_exsanguinator", 87652 ) -- HoF dagger
spec:RegisterGear( "torall_rod_of_the_endless_storm", 95939 ) -- ToT staff
spec:RegisterGear( "xing_ho_breath_of_yu_lon", 104555 ) -- SoO staff
spec:RegisterGear( "kardris_toxic_totem", 103988 ) -- SoO weapon

-- PvP Sets (Arena/RBG specific)
spec:RegisterGear( "malevolent_gladiator", 84407, 84408, 84409, 84410, 84411 ) -- Season 12
spec:RegisterGear( "tyrannical_gladiator", 91677, 91678, 91679, 91680, 91681 ) -- Season 13
spec:RegisterGear( "grievous_gladiator", 100050, 100051, 100052, 100053, 100054 ) -- Season 14
spec:RegisterGear( "prideful_gladiator", 103036, 103037, 103038, 103039, 103040 ) -- Season 15

-- Challenge Mode Sets
spec:RegisterGear( "challenge_mode", 90318, 90319, 90320, 90321, 90322 ) -- Ethereal set
spec:RegisterGear( "challenge_mode_weapons", 90431, 90432, 90433 ) -- Challenge Mode weapons

-- Notable Meta Gems and Enchants
spec:RegisterGear( "capacitive_primal_diamond", 101817 ) -- Legendary meta gem
spec:RegisterGear( "burning_primal_diamond", 76884 ) -- Primary meta gem for Frost
spec:RegisterGear( "ember_primal_diamond", 76895 ) -- Alternative meta gem

-- Set bonus tracking with aura associations
spec:RegisterAura( "tier14_2pc_frost", {
    id = 123123, -- Tier 14 2-piece bonus aura
    duration = 3600,
    max_stack = 1,
} )

spec:RegisterAura( "tier14_4pc_frost", {
    id = 123124, -- Tier 14 4-piece bonus aura
    duration = 3600,
    max_stack = 1,
} )

spec:RegisterAura( "tier15_2pc_frost", {
    id = 138303, -- Tier 15 2-piece bonus aura
    duration = 3600,
    max_stack = 1,
} )

spec:RegisterAura( "tier15_4pc_frost", {
    id = 138304, -- Tier 15 4-piece bonus aura
    duration = 3600,
    max_stack = 1,
} )

spec:RegisterAura( "tier16_2pc_frost", {
    id = 144810, -- Tier 16 2-piece bonus aura
    duration = 3600,
    max_stack = 1,
} )

spec:RegisterAura( "tier16_4pc_frost", {
    id = 144811, -- Tier 16 4-piece bonus aura
    duration = 3600,
    max_stack = 1,
} )

-- Advanced tier set bonus tracking with generate functions
local function check_tier_bonus(tier, pieces)
    return function()
        local count = 0
        for i = 1, 5 do
            if state.set_bonus[tier] >= i then
                count = count + 1
            end
        end
        return count >= pieces
    end
end

spec:RegisterGear( "tier14_2pc", nil, {
    generate = check_tier_bonus("tier14", 2)
} )

spec:RegisterGear( "tier14_4pc", nil, {
    generate = check_tier_bonus("tier14", 4)
} )

spec:RegisterGear( "tier15_2pc", nil, {
    generate = check_tier_bonus("tier15", 2)
} )

spec:RegisterGear( "tier15_4pc", nil, {
    generate = check_tier_bonus("tier15", 4)
} )

spec:RegisterGear( "tier16_2pc", nil, {
    generate = check_tier_bonus("tier16", 2)
} )

spec:RegisterGear( "tier16_4pc", nil, {
    generate = check_tier_bonus("tier16", 4)
} )



-- Talents (MoP 6-tier system)
spec:RegisterTalents( {
    -- Tier 1 (Level 15) - Mobility/Instant Cast
    presence_of_mind      = { 1, 1, 12043 }, -- Your next 3 spells are instant cast
    blazing_speed         = { 1, 2, 108843 }, -- Increases movement speed by 150% for 1.5 sec after taking damage
    ice_floes             = { 1, 3, 108839 }, -- Allows you to cast 3 spells while moving

    -- Tier 2 (Level 30) - Survivability
    flameglow             = { 2, 1, 140468 }, -- Reduces spell damage taken by a fixed amount
    ice_barrier           = { 2, 2, 11426 }, -- Absorbs damage for 1 min
    temporal_shield       = { 2, 3, 115610 }, -- 100% of damage taken is healed back over 6 sec

    -- Tier 3 (Level 45) - Control
    ring_of_frost         = { 3, 1, 113724 }, -- Incapacitates enemies entering the ring
    ice_ward              = { 3, 2, 111264 }, -- Frost Nova gains 2 charges
    frostjaw              = { 3, 3, 102051 }, -- Silences and freezes target

    -- Tier 4 (Level 60) - Utility
    greater_invisibility  = { 4, 1, 110959 }, -- Invisible for 20 sec, 90% damage reduction when visible
    cold_snap             = { 4, 2, 11958 }, -- Finishes cooldown on Frost spells, heals 25%
    cauterize             = { 4, 3, 86949 }, -- Fatal damage brings you to 35% health

    -- Tier 5 (Level 75) - DoT/Bomb Spells
    nether_tempest        = { 5, 1, 114923 }, -- Arcane DoT that spreads
    living_bomb           = { 5, 2, 44457 }, -- Fire DoT that explodes
    frost_bomb            = { 5, 3, 112948 }, -- Frost bomb with delayed explosion

    -- Tier 6 (Level 90) - Power/Mana Management
    invocation            = { 6, 1, 114003 }, -- Evocation increases damage by 25%
    rune_of_power         = { 6, 2, 116011 }, -- Ground rune increases spell damage by 15%
    incanter_s_ward       = { 6, 3, 1463 }, -- Converts 30% damage taken to mana
} )

-- Tier Sets
spec:RegisterGear( 13, 8, { -- Tier 14
    { 88886, head = 86701, shoulder = 86702, chest = 86699, hands = 86700, legs = 86703 }, -- LFR
    { 87139, head = 85370, shoulder = 85372, chest = 85373, hands = 85371, legs = 85369 }, -- Normal
    { 87133, head = 87105, shoulder = 87107, chest = 87108, hands = 87106, legs = 87104 }, -- Heroic
} )

spec:RegisterGear( 14, 8, { -- Tier 15
    { 95890, head = 95308, shoulder = 95310, chest = 95306, hands = 95307, legs = 95309 }, -- LFR
    { 95891, head = 95893, shoulder = 95895, chest = 95897, hands = 95894, legs = 95892 }, -- Normal
    { 95892, head = 96633, shoulder = 96631, chest = 96629, hands = 96632, legs = 96630 }, -- Heroic
} )

-- Glyphs
spec:RegisterGlyphs( {
    -- Major Glyphs
    [104035] = "Glyph of Arcane Explosion",
    [104036] = "Glyph of Arcane Power",
    [104037] = "Glyph of Armors",
    [104038] = "Glyph of Blink",
    [104039] = "Glyph of Combustion",
    [104040] = "Glyph of Cone of Cold",
    [104041] = "Glyph of Dragon's Breath",
    [104042] = "Glyph of Evocation",
    [104043] = "Glyph of Frost Armor",
    [104044] = "Glyph of Frost Nova",
    [104045] = "Glyph of Frostbolt",
    [104046] = "Glyph of Frostfire",
    [104047] = "Glyph of Frostfire Bolt",
    [104048] = "Glyph of Ice Block",
    [104049] = "Glyph of Ice Lance",
    [104050] = "Glyph of Icy Veins",
    [104051] = "Glyph of Inferno Blast",
    [104052] = "Glyph of Invisibility",
    [104053] = "Glyph of Mage Armor",
    [104054] = "Glyph of Mana Gem",
    [104055] = "Glyph of Mirror Image",
    [104056] = "Glyph of Polymorph",
    [104057] = "Glyph of Remove Curse",
    [104058] = "Glyph of Slow Fall",
    [104059] = "Glyph of Spellsteal",
    [104060] = "Glyph of Water Elemental",
    -- Minor Glyphs
    [104061] = "Glyph of Illusion",
    [104062] = "Glyph of Momentum",
    [104063] = "Glyph of the Bear Cub",
    [104064] = "Glyph of the Monkey",
    [104065] = "Glyph of the Penquin",
    [104066] = "Glyph of the Porcupine",
} )

-- Auras
spec:RegisterAuras( {
    -- Frost-specific Auras
    
    frozen = {
        id = 94794,        duration = 15,
        max_stack = 1
    },
    
    -- Shared Mage Auras
    arcane_brilliance = {
        id = 1459,
        duration = 3600,
        max_stack = 1
    },
    
    alter_time = {
        id = 110909,
        duration = 6,
        max_stack = 1
    },
    
    blink = {
        id = 1953,
        duration = 0.3,
        max_stack = 1
    },
    
    polymorph = {
        id = 118,
        duration = 60,
        max_stack = 1
    },
    
    counterspell = {
        id = 2139,
        duration = 6,
        max_stack = 1
    },
    
    frost_nova = {
        id = 122,
        duration = 8,
        max_stack = 1
    },
    
    ice_block = {
        id = 45438,
        duration = 10,
        max_stack = 1
    },
    
    ice_barrier = {
        id = 11426,
        duration = 60,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitBuffByID( "player", 11426 )
            
            if name then
                t.name = name
                t.count = count
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    icy_veins = {
        id = 12472,
        duration = 20,
        max_stack = 1
    },
    
    incanter_s_ward = {
        id = 1463,
        duration = 15,
        max_stack = 1
    },
    
    slow = {
        id = 31589,
        duration = 15,
        max_stack = 1
    },
    
    slow_fall = {
        id = 130,
        duration = 30,
        max_stack = 1
    },
    
    time_warp = {
        id = 80353,
        duration = 40,
        max_stack = 1
    },
    
    presence_of_mind = {
        id = 12043,
        duration = 10,
        max_stack = 1
    },
    
    ring_of_frost = {
        id = 113724,
        duration = 10,
        max_stack = 1
    },
    
    -- Armor Auras
    frost_armor = {
        id = 7302,
        duration = 1800,
        max_stack = 1
    },
    
    mage_armor = {
        id = 6117,
        duration = 1800,
        max_stack = 1
    },
      molten_armor = {
        id = 30482,
        duration = 1800,
        max_stack = 1
    },
    
    -- ENHANCED FROST-SPECIFIC AURA TRACKING
    -- Advanced aura system with extensive generate functions for Frost optimization
    
    -- Core Frost Procs and Mechanics
    brain_freeze = {
        id = 44549,
        duration = 15,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitBuffByID( "player", 44549 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    fingers_of_frost = {
        id = 44544,
        duration = 15,
        max_stack = 2,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitBuffByID( "player", 44544 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    -- Enhanced Deep Freeze tracking with shatter mechanics
    deep_freeze = {
        id = 44572,
        duration = 5,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitDebuffByID( "target", 44572 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    -- Frost Bomb dot tracking
    frost_bomb = {
        id = 112948,
        duration = 12,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitDebuffByID( "target", 112948 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    nether_tempest = {
        id = 114923,
        duration = 12,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitDebuffByID( "target", 114923 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    blizzard = {
        id = 10,
        duration = 8,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitDebuffByID( "target", 10 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    -- Living Bomb tracking (if talented)
    living_bomb = {
        id = 44457,
        duration = 12,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitDebuffByID( "target", 44457 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    -- Enhanced Frozen Orb tracking
    frozen_orb = {
        id = 84714,
        duration = 10,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitBuffByID( "player", 84714 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    -- MoP Talent Coordination - Enhanced tracking
    invocation = {
        id = 114003,
        duration = 40,
        max_stack = 5,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitBuffByID( "player", 114003 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    rune_of_power = {
        id = 116011,
        duration = 60,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitBuffByID( "player", 116011 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    -- Enhanced Glyph Coordination
    glyph_of_icy_veins = {
        id = 131078,
        duration = 20,
        max_stack = 1,
        generate = function( t )
            if not IsSpellKnown( 56377 ) then -- Check if glyph is learned
                t.count = 0
                t.expires = 0
                t.applied = 0
                t.caster = "nobody"
                return
            end
            
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitBuffByID( "player", 12472 )
            
            if name then
                t.name = "Enhanced Icy Veins"
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    glyph_of_splitting_ice = {
        id = 56372,
        duration = 0,
        max_stack = 1,
        generate = function( t )
            if IsSpellKnown( 56372 ) then
                t.name = "Glyph of Splitting Ice"
                t.count = 1
                t.expires = 9999999999
                t.applied = 0
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    -- Enhanced Defensive and Utility Tracking
    mana_shield = {
        id = 1463,
        duration = 60,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitBuffByID( "player", 1463 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    temporal_shield = {
        id = 115610,
        duration = 4,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitBuffByID( "player", 115610 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    greater_invisibility = {
        id = 110960,
        duration = 20,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitBuffByID( "player", 110960 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    -- Enhanced CC and Control Effects
    ring_of_frost_freeze = {
        id = 82691,
        duration = 10,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitDebuffByID( "target", 82691 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    frostjaw = {
        id = 102051,
        duration = 8,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitDebuffByID( "target", 102051 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    -- Enhanced Pet Tracking
    water_elemental = {
        id = 31687,
        duration = 45,
        max_stack = 1,
        generate = function( t )
            if UnitExists("pet") and UnitCreatureType("pet") == "Elemental" then
                t.name = "Water Elemental"
                t.count = 1
                t.expires = GetTime() + 45 -- Approximate remaining duration
                t.applied = GetTime() - 1
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    -- Enhanced Movement and Mobility
    blazing_speed = {
        id = 108843,
        duration = 1.5,
        max_stack = 1,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitBuffByID( "player", 108843 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    ice_floes = {
        id = 108839,
        duration = 15,
        max_stack = 3,
        generate = function( t )
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitBuffByID( "player", 108839 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    -- Enhanced Tier Set and Legendary Tracking
    tier14_2pc_frost = {
        id = 123456, -- Placeholder ID
        duration = 0,
        max_stack = 1,
        generate = function( t )
            if equipped.tier14 >= 2 then
                t.name = "T14 2PC Frost"
                t.count = 1
                t.expires = 9999999999
                t.applied = 0
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    tier15_4pc_frost = {
        id = 123457, -- Placeholder ID
        duration = 0,
        max_stack = 1,
        generate = function( t )
            if equipped.tier15 >= 4 then
                t.name = "T15 4PC Frost"
                t.count = 1
                t.expires = 9999999999
                t.applied = 0
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
    
    legendary_meta_gem_proc = {
        id = 137323, -- Capacitive Primal Diamond proc
        duration = 30,
        max_stack = 1,
        generate = function( t )
            if not equipped.legendary_meta_gem then
                t.count = 0
                t.expires = 0
                t.applied = 0
                t.caster = "nobody"
                return
            end
            
            local name, icon, count, debuffType, duration, expirationTime, caster = FindUnitBuffByID( "player", 137323 )
            
            if name then
                t.name = name
                t.count = count > 0 and count or 1
                t.expires = expirationTime
                t.applied = expirationTime - duration
                t.caster = caster
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end
    },
} )

-- Spell Power Calculations and State Expressions
spec:RegisterStateExpr( "spell_power", function()
    return GetSpellBonusDamage(5) -- Frost school
end )

spec:RegisterStateExpr( "brain_freeze_bonus", function()
    return buff.brain_freeze.up and 0.2 or 0 -- 20% damage bonus
end )

spec:RegisterStateExpr( "fingers_of_frost_bonus", function()
    return buff.fingers_of_frost.up and 0.15 or 0 -- 15% damage bonus
end )

spec:RegisterStateExpr( "icy_veins_bonus", function()
    return buff.icy_veins.up and 0.2 or 0 -- 20% damage bonus
end )

-- Abilities
spec:RegisterAbilities( {
    -- Frost Core Abilities
    frostbolt = {
        id = 116,
        cast = 2,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0.04,
        spendType = "mana",
        
        startsCombat = true,
        texture = 135846,
        
        handler = function()
            -- Chance to proc Fingers of Frost
            -- Chance to proc Brain Freeze for Frostfire Bolt
            -- Brain Freeze has a chance to proc on each Frostbolt hit
        end,
    },
    
    frost_bomb = {
        id = 112948,
        cast = 1.5,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0.06,
        spendType = "mana",
        
        startsCombat = true,
        texture = 609814,
        
        talent = "frost_bomb",
        
        handler = function()
            applyDebuff( "target", "frost_bomb" )
        end,
    },
    
    frozen_orb = {
        id = 84714,
        cast = 0,
        cooldown = 60,
        gcd = "spell",
        
        spend = 0.03,
        spendType = "mana",
        
        startsCombat = true,
        texture = 629077,
        
        toggle = "cooldowns",
        
        handler = function()
            applyBuff( "frozen_orb" )
        end,
    },
    
    ice_lance = {
        id = 30455,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0.02,
        spendType = "mana",
        
        startsCombat = true,
        texture = 135844,
        
        handler = function()
            if buff.fingers_of_frost.up then
                removeStack( "fingers_of_frost" )
            end
        end,
    },
    
    deep_freeze = {
        id = 44572,
        cast = 0,
        cooldown = 30,
        gcd = "spell",
        
        spend = 0.04,
        spendType = "mana",
        
        startsCombat = true,
        texture = 236214,
        
        toggle = "cooldowns",
        
        handler = function()
            applyDebuff( "target", "deep_freeze" )
        end,
    },
    
    frostfire_bolt = {
        id = 44614,
        cast = function() return buff.brain_freeze.up and 0 or 2 end, -- Instant when Brain Freeze active
        cooldown = 0,
        gcd = "spell",
        
        spend = 0.04,
        spendType = "mana",
        
        startsCombat = true,
        texture = 237520,
        
        usable = function() return buff.brain_freeze.up, "requires brain freeze proc" end,
        
        handler = function()
            removeBuff( "brain_freeze" )
        end,
    },
    
    icy_veins = {
        id = 12472,
        cast = 0,
        cooldown = 180,
        gcd = "off",
        
        toggle = "cooldowns",
        
        startsCombat = false,
        texture = 135838,
        
        handler = function()
            applyBuff( "icy_veins" )
        end,
    },
    
    cold_snap = {
        id = 11958,
        cast = 0,
        cooldown = 180,
        gcd = "off",
        
        toggle = "cooldowns",
        
        startsCombat = false,
        texture = 135865,
        
        talent = "cold_snap",
        
        handler = function()
            setCooldown( "frost_nova", 0 )
            setCooldown( "ice_barrier", 0 )
            setCooldown( "ice_block", 0 )
            setCooldown( "icy_veins", 0 )
            
            -- Heal for 25% of max health
            gain( health.max * 0.25, "health" )
        end,
    },
    
    summon_water_elemental = {
        id = 31687,
        cast = 0,
        cooldown = 60,
        gcd = "spell",
        
        spend = 0.16,
        spendType = "mana",
        
        startsCombat = false,
        texture = 135862,
        
        essential = true,
        
        handler = function()
            summonPet( "water_elemental" )
        end,
    },
    
    -- Shared Mage Abilities
    arcane_brilliance = {
        id = 1459,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0.04,
        spendType = "mana",
        
        startsCombat = false,
        texture = 135932,
        
        handler = function()
            applyBuff( "arcane_brilliance" )
        end,
    },
    
    alter_time = {
        id = 108978,
        cast = 0,
        cooldown = 180,
        gcd = "off",
        
        toggle = "cooldowns",
        
        startsCombat = false,
        texture = 607849,
        
        handler = function()
            applyBuff( "alter_time" )
        end,
    },
    
    blink = {
        id = 1953,
        cast = 0,
        cooldown = 15,
        gcd = "spell",
        
        spend = 0.02,
        spendType = "mana",
        
        startsCombat = false,
        texture = 135736,
        
        handler = function()
            applyBuff( "blink" )
        end,
    },
    
    cone_of_cold = {
        id = 120,
        cast = 0,
        cooldown = 10,
        gcd = "spell",
        
        spend = 0.04,
        spendType = "mana",
        
        startsCombat = true,
        texture = 135852,
        
        handler = function()
            applyDebuff( "target", "cone_of_cold" )
        end,
    },
    
    conjure_mana_gem = {
        id = 759,
        cast = 3,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0.03,
        spendType = "mana",
        
        startsCombat = false,
        texture = 134132,
        
        handler = function()
            -- Creates a Mana Gem
        end,
    },
    
    counterspell = {
        id = 2139,
        cast = 0,
        cooldown = 24,
        gcd = "off",
        
        interrupt = true,
        
        startsCombat = true,
        texture = 135856,
        
        toggle = "interrupts",
        
        usable = function() return target.casting end,
        
        handler = function()
            interrupt()
            applyDebuff( "target", "counterspell" )
        end,
    },
    
    evocation = {
        id = 12051,
        cast = 6,
        cooldown = 120,
        gcd = "spell",
        
        toggle = "cooldowns",
        
        startsCombat = false,
        texture = 136075,
        
        talent = function() return not talent.rune_of_power.enabled end,
        
        handler = function()
            -- Restore 60% mana over 6 sec
            gain( 0.6 * mana.max, "mana" )
            
            if talent.invocation.enabled then
                applyBuff( "invocation" )
            end
        end,
    },
    
    frost_nova = {
        id = 122,
        cast = 0,
        cooldown = function() return talent.ice_ward.enabled and 20 or 30 end,
        charges = function() return talent.ice_ward.enabled and 2 or nil end,
        recharge = function() return talent.ice_ward.enabled and 20 or nil end,
        gcd = "spell",
        
        spend = 0.02,
        spendType = "mana",
        
        startsCombat = true,
        texture = 135848,
        
        handler = function()
            applyDebuff( "target", "frost_nova" )
        end,
    },
    
    frostjaw = {
        id = 102051,
        cast = 0,
        cooldown = 20,
        gcd = "spell",
        
        spend = 0.02,
        spendType = "mana",
        
        startsCombat = true,
        texture = 607853,
        
        talent = "frostjaw",
        
        handler = function()
            applyDebuff( "target", "frostjaw" )
        end,
    },
    
    ice_barrier = {
        id = 11426,
        cast = 0,
        cooldown = 25,
        gcd = "spell",
        
        spend = 0.03,
        spendType = "mana",
        
        startsCombat = false,
        texture = 135988,
        
        talent = "ice_barrier",
        
        handler = function()
            applyBuff( "ice_barrier" )
        end,
    },
    
    ice_block = {
        id = 45438,
        cast = 0,
        cooldown = 300,
        gcd = "spell",
        
        toggle = "defensives",
        
        startsCombat = false,
        texture = 135841,
        
        handler = function()
            applyBuff( "ice_block" )
            setCooldown( "hypothermia", 30 )
        end,
    },
    
    ice_floes = {
        id = 108839,
        cast = 0,
        cooldown = 45,
        charges = 3,
        recharge = 45,
        gcd = "off",
        
        startsCombat = false,
        texture = 610877,
        
        talent = "ice_floes",
        
        handler = function()
            applyBuff( "ice_floes" )
        end,
    },
    
    incanter_s_ward = {
        id = 1463,
        cast = 0,
        cooldown = 8,
        gcd = "spell",
        
        startsCombat = false,
        texture = 250986,
        
        talent = "incanter_s_ward",
        
        handler = function()
            applyBuff( "incanter_s_ward" )
        end,
    },
    
    invisibility = {
        id = 66,
        cast = 0,
        cooldown = 300,
        gcd = "spell",
        
        toggle = "defensives",
        
        startsCombat = false,
        texture = 132220,
        
        handler = function()
            applyBuff( "invisibility" )
        end,
    },
    
    greater_invisibility = {
        id = 110959,
        cast = 0,
        cooldown = 90,
        gcd = "spell",
        
        toggle = "defensives",
        
        startsCombat = false,
        texture = 606086,
        
        talent = "greater_invisibility",
        
        handler = function()
            applyBuff( "greater_invisibility" )
        end,
    },
    
    presence_of_mind = {
        id = 12043,
        cast = 0,
        cooldown = 90,
        gcd = "off",
        
        toggle = "cooldowns",
        
        startsCombat = false,
        texture = 136031,
        
        talent = "presence_of_mind",
        
        handler = function()
            applyBuff( "presence_of_mind" )
        end,
    },
    
    ring_of_frost = {
        id = 113724,
        cast = 1.5,
        cooldown = 45,
        gcd = "spell",
        
        spend = 0.08,
        spendType = "mana",
        
        startsCombat = false,
        texture = 464484,
        
        talent = "ring_of_frost",
        
        handler = function()
            -- Places Ring of Frost at target location
        end,
    },
    
    rune_of_power = {
        id = 116011,
        cast = 1.5,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0.03,
        spendType = "mana",
        
        startsCombat = false,
        texture = 609815,
        
        talent = "rune_of_power",
        
        handler = function()
            -- Places Rune of Power on the ground
        end,
    },
    
    slow = {
        id = 31589,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0.02,
        spendType = "mana",
        
        startsCombat = true,
        texture = 136091,
        
        handler = function()
            applyDebuff( "target", "slow" )
        end,
    },
    
    slow_fall = {
        id = 130,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0.01,
        spendType = "mana",
        
        startsCombat = false,
        texture = 135992,
        
        handler = function()
            applyBuff( "slow_fall" )
        end,
    },
    
    spellsteal = {
        id = 30449,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0.07,
        spendType = "mana",
        
        startsCombat = true,
        texture = 135729,
        
        handler = function()
            -- Attempt to steal a buff from the target
        end,
    },
    
    time_warp = {
        id = 80353,
        cast = 0,
        cooldown = 300,
        gcd = "off",
        
        toggle = "cooldowns",
        
        startsCombat = false,
        texture = 458224,
        
        handler = function()
            applyBuff( "time_warp" )
            applyDebuff( "player", "temporal_displacement" )
        end,
    },
    
    -- Armor Spells
    frost_armor = {
        id = 7302,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        startsCombat = false,
        texture = 135843,
        
        handler = function()
            removeBuff( "mage_armor" )
            removeBuff( "molten_armor" )
            applyBuff( "frost_armor" )
        end,
    },
    
    mage_armor = {
        id = 6117,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        startsCombat = false,
        texture = 135991,
        
        handler = function()
            removeBuff( "frost_armor" )
            removeBuff( "molten_armor" )
            applyBuff( "mage_armor" )
        end,
    },
    
    molten_armor = {
        id = 30482,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        startsCombat = false,
        texture = 132221,
        
        handler = function()
            removeBuff( "frost_armor" )
            removeBuff( "mage_armor" )
            applyBuff( "molten_armor" )
        end,
    },
    
    blizzard = {
        id = 10,
        cast = 8,
        channeled = true,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0.08,
        spendType = "mana",
        
        startsCombat = true,
        texture = 135846,
        
        handler = function()
            applyDebuff( "target", "blizzard" )
        end,
    },
    
    nether_tempest = {
        id = 114923,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0.04,
        spendType = "mana",
        
        startsCombat = true,
        texture = 610472,
        
        talent = "nether_tempest",
        
        handler = function()
            applyDebuff( "target", "nether_tempest" )
        end,
    },
} )

-- Water Elemental Abilities
spec:RegisterPet( "water_elemental", 78116, "summon_water_elemental", 600 )


-- State Functions and Expressions
spec:RegisterStateExpr( "brain_freeze_active", function()
    return buff.brain_freeze.up
end )

spec:RegisterStateExpr( "fingers_of_frost_active", function()
    return buff.fingers_of_frost.up
end )

spec:RegisterStateTable( "frost_info", {
    -- For Virtual Fingers of Frost / Brain Freeze procs
} )

-- Range
spec:RegisterRanges( "frostbolt", "polymorph", "blink" )

-- Options
spec:RegisterOptions( {
    enabled = true,
    
    aoe = 3,
    
    nameplates = true,
    nameplateRange = 40,
    
    damage = true,
    damageExpiration = 8,
    
    potion = "jade_serpent_potion",
    
    package = "Frost",
} )

-- SIMC-derived settings from MageFrost.simc
spec:RegisterSetting( "time_warp_health_threshold", 25, {
    name = "Time Warp Health Threshold",
    desc = "Target health percentage below which Time Warp should be used (default: 25%)",
    type = "range",
    min = 10,
    max = 50,
    step = 5,
    width = 1.5
} )

spec:RegisterSetting( "time_warp_time_threshold", 5, {
    name = "Time Warp Time Threshold",
    desc = "Time in seconds after which Time Warp should be used regardless of target health (default: 5s)",
    type = "range",
    min = 3,
    max = 15,
    step = 1,
    width = 1.5
} )

spec:RegisterSetting( "trinket_icy_veins_threshold", 20, {
    name = "Trinket Icy Veins Threshold",
    desc = "Seconds remaining on Icy Veins cooldown above which trinkets should be used (default: 20s)",
    type = "range",
    min = 10,
    max = 30,
    step = 5,
    width = 1.5
} )

spec:RegisterSetting( "aoe_enemy_threshold", 3, {
    name = "AoE Enemy Threshold",
    desc = "Number of enemies at which AoE abilities like Blizzard should be used (default: 3)",
    type = "range",
    min = 2,
    max = 6,
    step = 1,
    width = 1.5
} )

spec:RegisterSetting( "use_racial_abilities", true, {
    name = "Use Racial Abilities",
    desc = "If checked, racial abilities like Berserking and Blood Fury will be recommended during Icy Veins or Brain Freeze",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "use_trinkets", true, {
    name = "Use Trinkets",
    desc = "If checked, trinkets will be recommended during Icy Veins or when Icy Veins cooldown is above threshold",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "alter_time_brain_freeze", true, {
    name = "Alter Time with Brain Freeze",
    desc = "If checked, Alter Time will be recommended when Brain Freeze is available",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "alter_time_fingers_of_frost", true, {
    name = "Alter Time with Fingers of Frost",
    desc = "If checked, Alter Time will be recommended when Fingers of Frost has more than 1 stack",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "water_elemental_freeze", true, {
    name = "Water Elemental Freeze",
    desc = "If checked, Water Elemental's Freeze will be recommended when Fingers of Frost stacks are low",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "ice_lance_moving", true, {
    name = "Ice Lance While Moving",
    desc = "If checked, Ice Lance will be recommended while moving as a fallback option",
    type = "toggle",
    width = "full"
} )

-- Enhanced Frost-specific settings (based on Hunter Survival patterns)
spec:RegisterSetting( "mana_dump_threshold", 80, {
    name = "Mana Dump Threshold",
    desc = strformat( "Mana level at which to prioritize spending abilities like %s and %s to avoid mana capping.",
        Hekili:GetSpellLinkWithTexture( spec.abilities.frostbolt.id ),
        Hekili:GetSpellLinkWithTexture( spec.abilities.ice_lance.id ) ),
    type = "range",
    min = 50,
    max = 120,
    step = 5,
    width = 1.5
} )

spec:RegisterSetting( "frostbolt_mana_threshold", 4, {
    name = "Frostbolt Mana Threshold",
    desc = "Minimum mana percentage required to cast Frostbolt (default: 4%)",
    type = "range",
    min = 1,
    max = 10,
    step = 1,
    width = 1.5
} )

spec:RegisterSetting( "ice_lance_mana_threshold", 2, {
    name = "Ice Lance Mana Threshold",
    desc = "Minimum mana percentage required to cast Ice Lance (default: 2%)",
    type = "range",
    min = 1,
    max = 5,
    step = 1,
    width = 1.5
} )

spec:RegisterSetting( "frostfire_bolt_mana_threshold", 4, {
    name = "Frostfire Bolt Mana Threshold",
    desc = "Minimum mana percentage required to cast Frostfire Bolt (default: 4%)",
    type = "range",
    min = 1,
    max = 10,
    step = 1,
    width = 1.5
} )

spec:RegisterSetting( "blizzard_mana_threshold", 8, {
    name = "Blizzard Mana Threshold",
    desc = "Minimum mana percentage required to cast Blizzard (default: 8%)",
    type = "range",
    min = 5,
    max = 15,
    step = 1,
    width = 1.5
} )

spec:RegisterSetting( "fingers_of_frost_stacks", 2, {
    name = "Fingers of Frost Stacks",
    desc = "Number of Fingers of Frost stacks at which to prioritize Ice Lance (default: 2)",
    type = "range",
    min = 1,
    max = 3,
    step = 1,
    width = 1.5
} )

spec:RegisterSetting( "brain_freeze_priority", true, {
    name = "Brain Freeze Priority",
    desc = "If checked, Frostfire Bolt will be prioritized when Brain Freeze is active",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "frozen_orb_priority", true, {
    name = "Frozen Orb Priority",
    desc = "If checked, Frozen Orb will be used on cooldown for AoE damage",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "deep_freeze_priority", false, {
    name = "Deep Freeze Priority",
    desc = "If checked, Deep Freeze will be used for control and damage",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "water_elemental_priority", true, {
    name = "Water Elemental Priority",
    desc = "If checked, Water Elemental will be summoned when available",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "rune_of_power_priority", true, {
    name = "Rune of Power Priority",
    desc = "If checked, Rune of Power will be used for damage amplification",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "evocation_mana_threshold", 45, {
    name = "Evocation Mana Threshold",
    desc = "Mana percentage below which Evocation should be used (default: 45%)",
    type = "range",
    min = 20,
    max = 80,
    step = 5,
    width = 1.5
} )

spec:RegisterSetting( "icy_veins_bloodlust_threshold", 180, {
    name = "Icy Veins Bloodlust Threshold",
    desc = "Seconds remaining on Bloodlust/Sated above which Icy Veins should be used (default: 180s)",
    type = "range",
    min = 60,
    max = 300,
    step = 30,
    width = 1.5
} )

spec:RegisterSetting( "alter_time_complex_conditions", true, {
    name = "Alter Time Complex Conditions",
    desc = "If checked, Alter Time will use complex conditions including Bloodlust/Sated timing",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "nether_tempest_targets", 5, {
    name = "Nether Tempest Targets",
    desc = "Number of targets at which Nether Tempest should be maintained (default: 5)",
    type = "range",
    min = 1,
    max = 10,
    step = 1,
    width = 1.5
} )

spec:RegisterSetting( "frost_bomb_priority", true, {
    name = "Frost Bomb Priority",
    desc = "If checked, Frost Bomb will be used when not ticking on target",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "cone_of_cold_moving", true, {
    name = "Cone of Cold While Moving",
    desc = "If checked, Cone of Cold will be used while moving in AoE situations",
    type = "toggle",
    width = "full"
} )

-- Register default pack for MoP Frost Mage
spec:RegisterPack( "Frost", 20250727, [[Hekili:1Ev4UTTnq4NLGc40I1PAlhN0oKeGTUnSASvmm39xjrltLqejsnkQKMGa9SV7OKOOOfTxl6cqmSj)4DhpE33Dx0IOpfTzhrrJ(y48WvZVi8IG5lG)UiAJ6XsA0Mss6DKBGVWjfWNSu6dkALc34XCbzhkGkrTmf2mAZ2AwU6d8OTti15VB5BbSL00OpE(zrBULTBhTfkTknAZNULv1KG)tAs6uBtIid(DQIj4nj5SkfSDMq2K8B07y5SGOn6f1xdAgPoxbF9J6Rv7PI2KkQ5kQeuCEE0gkNSnNUl6NIuG1H4gwztQKbize4YtK3qvb3sj5QBdktvnjx2KeUQj55NBsuScW0UUjz1GAW1IFGilrbV02akysPqgZk0(XrgWz24yPpgFpLXRCaTYguMu8eLhlKBDqD(bUl5uUkOusRO8uASilUGX3f0d2iBxeOyVWRy3wNLfyS5G6YwFJE5TscJhNjP0NObskOGbTSfElOY7y8Bq5)2V9Ypxi2fNvlFeL)7CKV55sY43rvl(pOXuHiFN4bU1wsAbyav6yGW5quDUqzjtqVlMFyfh()GId1kEXXceGqOkv8wrX2(qGMKznjNGX1P63f7OToOArFO8fTOL1CD0tP4bQ0J01)uFJhJgVPdAE0EALV8ykNXVxKsWJpsZTo3H9gRNHn0k5SJRKucsNexHj77CVJDkBmM6sB9nApTsxD4CaGccWJ8lABxRQx6nrWkljd82qYg6g1pKbvkGwvh7SOj5vdg1Gg02JFQeh(WLZ1gtNRjfIwJR4KY9zwmBPLVFofJheiH2sKsgexGzddkXEN9uJ1MAfDeYLdXIODyzmjiqbuubLMlvIJ02ZB7ir04Yja9QUYJl9WXew3thwes7omCdgZVJyaqCt6UGcYNTi2PQoCAD7NHapW90ykNwWOilZvWJCFSDH4(rKdBZzp9uxmCOFQb)Y0vGPI2CEmArl0Lov(Qu6hdNI4(ZzDvG9tGsxVlfO2id9myjfSPejRS9G)bu6(hAs(v0eSsBKqUmeGiz55mZl7E2CmrwiKow9OR2dem)JMtlGqCIBxkhLtAswx)uP67oq(WbFtf23f0ldROuivD9wDAxRuN2KiP)tnKea8BvcSNhsTsuawlSq6TeigTkOz9VZ4Wwlbh0FZRQlrjHaiDTTDQDdqNAWFMx8MYDdGx5f8qdrdOxS4qW7QOzb3VPpuEWc(5EHB45Sq)2dBlgogRJ8Ud4A6IGhqho3l6H8Eh4VxWVN2cwdYjamWd7ceqOe6RPVTF5Ip)Qbv5)zON7WYU8)iyY8TqFOOhlxKo4otKNlEq36bPwsaoiirawVUcpidoKcH1lbCIcSoKQhhxOZmQ5JqVBhcggZHSLubSdRBs(E4yw1u6wYLlVBztuo871tKeAyN(wLg68iJUNM1FOOhxOZGwW2ahsT6wK7AtrDMKDhYzkYy5WCmVOjXMvSz9lGv(ZEBUzDRSQcmxJV7Q3ShH50WSynNgGZnzAqJO9Enl7Qd2J662lWp3Y8zKiih75hTx3mWxRSDMx8YWvp)mc56v2hYMk0EDRGHHfhO2Sx1DknRRMVr8Sp(W4x4b3BYJNF2xFL2YWmI1xVmGKVyOowXRXryUQF0jpYZ)Kqxho)Osn8RtQTreFcAMeQ)8MZHVQ9YUprDLtSEg2FaRzN0p8J1z)IcqnsyMNrNgfnzQAzj29hpA2uJgnwoJgwzKWMCmOzN4zaOEV57fiH6FjuAfARRHzqmVwod(m7LEcR6I3MUN5Rx8QXzZDvOrTyLUUC(mFJXmop1mHbkGtMyALz(NuzVihtXFZD(WjnMABg8tp1Xi(ctta(pK2tDz4SVGEbUeMYO)v9hf)Y0pQ9L5rnJRomhW1xTC2jT9Np(5zyeGPpu)zA1mmp9n5um1e5F3Z)IUwV(VUPdW2HJ(3)]] )
