-- WarriorProtection.lua
-- Updated July, 2025 - Smufrik
-- Mists of Pandaria module for Warrior: Protection spec

-- MoP: Use UnitClass instead of UnitClassBase
local _, playerClass = UnitClass('player')
if playerClass ~= 'WARRIOR' then return end

local addon, ns = ...
local Hekili = _G[ addon ]
local class, state = Hekili.Class, Hekili.State

local floor = math.floor
local strformat = string.format
local spec = Hekili:NewSpecialization( 73, true ) -- Protection spec ID for MoP (73 = melee tank in MoP Classic)


-- Register resources with proper rage generation system from Cataclysm
local function rage_amount( isOffhand )
    -- MoP rage generation calculation
    local hit_factor = 6.5
    local speed = (isOffhand and state.swings.offhand_speed or state.swings.mainhand_speed)/state.haste
    local rage_multiplier = state.talent.anger_management.enabled and 1.25 or 1

    return hit_factor * speed * rage_multiplier * (isOffhand and 0.5 or 1)
end

spec:RegisterResource( 1, { -- Rage = 1 in MoP
    anger_management = {
        talent = "anger_management",

        last = function ()
            local app = state.buff.anger_management.applied
            local t = state.query_time

            return app + floor( t - app )
        end,

        interval = 3,
        value = 1
    },

    second_wind = {
        aura = "second_wind",

        last = function ()
            local app = state.buff.second_wind.applied
            local t = state.query_time

            return app + floor( t - app )
        end,

        interval = 2,
        value = function() return talent.second_wind.rank * 2 end,
    },

    mainhand = {
        swing = "mainhand",

        last = function ()
            local swing = state.combat == 0 and state.now or state.swings.mainhand
            local t = state.query_time

            return swing + ( floor( ( t - swing ) / state.swings.mainhand_speed ) * state.swings.mainhand_speed )
        end,

        interval = "mainhand_speed",

        stop = function () return state.swings.mainhand == 0 end,
        value = function( now )
            return rage_amount()
        end,
    },

    offhand = {
        swing = "offhand",

        last = function ()
            local swing = state.combat == 0 and state.now or state.swings.offhand
            local t = state.query_time

            return swing + ( floor( ( t - swing ) / state.swings.offhand_speed ) * state.swings.offhand_speed )
        end,

        interval = "offhand_speed",

        stop = function () return state.swings.offhand == 0 end,
        value = function( now )
            return rage_amount( true ) or 0
        end,
    },
} )

-- Tier sets and combat log tracking
spec:RegisterGear( "tier14", 85329, 85330, 85331, 85332, 85333 ) -- T14 Battleplate of Resounding Rings
spec:RegisterGear( "tier15", 95571, 95573, 95574, 95575, 95576 ) -- T15 Battleplate of the Last Mogu
spec:RegisterGear( "tier16", 99334, 99335, 99336, 99337, 99338 ) -- T16 Battleplate of the Prehistoric Marauder

-- Additional tier difficulties
spec:RegisterGear( "tier14_lfr", 89087, 89088, 89089, 89090, 89091 ) -- T14 LFR
spec:RegisterGear( "tier14_heroic", 86650, 86651, 86652, 86653, 86654 ) -- T14 Heroic
spec:RegisterGear( "tier15_lfr", 96618, 96619, 96620, 96621, 96622 ) -- T15 LFR  
spec:RegisterGear( "tier15_heroic", 96901, 96902, 96903, 96904, 96905 ) -- T15 Heroic
spec:RegisterGear( "tier16_lfr", 105687, 105688, 105689, 105690, 105691 ) -- T16 LFR
spec:RegisterGear( "tier16_heroic", 104460, 104461, 104462, 104463, 104464 ) -- T16 Heroic

-- Legendary items
spec:RegisterGear( "legendary_cloak", 102246, 102247, 102248, 102249, 102250 ) -- Qian-Ying, Fortitude of Niuzao
spec:RegisterGear( "legendary_meta", 101821, 101822 ) -- Legendary meta gems

-- Notable Protection trinkets
spec:RegisterGear( "vial_of_living_corruption", 102291 ) -- SoO trinket
spec:RegisterGear( "thoks_tail_tip", 102658 ) -- SoO trinket  
spec:RegisterGear( "juggernaut_focuser", 105109 ) -- SoO trinket
spec:RegisterGear( "resolute_barrier", 104909 ) -- SoO trinket

-- Protection weapons
spec:RegisterGear( "bulwark_of_azzinoth", 104400 ) -- Shield from SoO
spec:RegisterGear( "norushen_enigma", 104404 ) -- 1H weapon from SoO
spec:RegisterGear( "korkron_juggernaut_plating", 105672 ) -- Shield from SoO

-- PvP sets
spec:RegisterGear( "gladiator_s14", 91436, 91437, 91438, 91439, 91440 ) -- Season 14 Gladiator
spec:RegisterGear( "grievous_s15", 94713, 94714, 94715, 94716, 94717 ) -- Season 15 Grievous

-- Challenge Mode sets
spec:RegisterGear( "challenge_mode", 90550, 90551, 90552, 90553, 90554 ) -- Challenge Mode Warrior set

-- Combat log tracking for Protection-specific events
local function RegisterProtectionCombatLog()
    spec:RegisterCombatLogEvent( function( _, subtype, _,  sourceGUID, sourceName, _, _, destGUID, destName, destFlags, _, spellID, spellName )
        
        if sourceGUID == state.GUID then
            -- Shield Block casts
            if subtype == "SPELL_CAST_SUCCESS" and spellID == 2565 then
                state.shield_block_cast_time = GetTime()
            end
            
            -- Shield Slam casts  
            if subtype == "SPELL_CAST_SUCCESS" and spellID == 23922 then
                state.shield_slam_cast_time = GetTime()
            end
            
            -- Devastate casts
            if subtype == "SPELL_CAST_SUCCESS" and spellID == 20243 then
                state.devastate_cast_time = GetTime()
            end
            
            -- Revenge casts
            if subtype == "SPELL_CAST_SUCCESS" and spellID == 6572 then
                state.revenge_cast_time = GetTime()
            end
            
            -- Thunder Clap casts
            if subtype == "SPELL_CAST_SUCCESS" and spellID == 6343 then
                state.thunder_clap_cast_time = GetTime()
            end
            
            -- Shield Barrier casts
            if subtype == "SPELL_CAST_SUCCESS" and spellID == 112048 then
                state.shield_barrier_cast_time = GetTime()
            end
            
            -- Shield Wall casts
            if subtype == "SPELL_CAST_SUCCESS" and spellID == 871 then
                state.shield_wall_cast_time = GetTime()
            end
            
            -- Last Stand casts
            if subtype == "SPELL_CAST_SUCCESS" and spellID == 12975 then
                state.last_stand_cast_time = GetTime()
            end
            
            -- Berserker Rage casts
            if subtype == "SPELL_CAST_SUCCESS" and spellID == 18499 then
                state.berserker_rage_cast_time = GetTime()
            end
            
            -- Spell Reflection casts
            if subtype == "SPELL_CAST_SUCCESS" and spellID == 23920 then
                state.spell_reflection_cast_time = GetTime()
            end
            
            -- Vengeance procs
            if subtype == "SPELL_AURA_APPLIED" and spellID == 76691 then
                state.vengeance_proc_time = GetTime()
            end
            
            -- Shield Block procs
            if subtype == "SPELL_AURA_APPLIED" and spellID == 132404 then
                state.shield_block_proc_time = GetTime()
            end
            
        end
    end )
end

RegisterProtectionCombatLog()

-- MoP Protection Warrior specific variables and tracking
spec:RegisterVariable( "rage_pooling", function()
    -- Determine if we should pool rage for upcoming abilities
    return rage.current < 40 and ( cooldown.shield_slam.remains < 2 or cooldown.revenge.remains < 2 )
end )

spec:RegisterVariable( "defensive_cd_up", function()
    -- Check if any major defensive cooldown is active
    return buff.shield_wall.up or buff.last_stand.up or buff.spell_reflection.up or buff.avatar.up
end )

spec:RegisterVariable( "can_shield_block", function()
    -- Check if we can and should use Shield Block
    return cooldown.shield_block.charges > 0 and rage.current >= 60 and buff.shield_block.remains < 3
end )

spec:RegisterVariable( "execute_phase", function()
    -- In MoP, there's no execute phase for Protection, but we can define low health scenarios
    return target.health.pct < 20
end )

spec:RegisterVariable( "aoe_count", function()
    -- Number of enemies for AoE decision making
    return active_enemies
end )

spec:RegisterVariable( "threat_mode", function()
    -- Determine current threat mode based on situation
    if active_enemies >= 3 then
        return "aoe"
    elseif active_enemies == 2 then
        return "cleave"
    else
        return "single"
    end
end )

spec:RegisterVariable( "vengeance_value", function()
    -- Calculate current Vengeance value for ability prioritization
    return buff.vengeance.stack or 0
end )

-- Tier set bonus tracking with generate functions
spec:RegisterGear( "tier14_2pc", function() return set_bonus.tier14_2pc end )
spec:RegisterGear( "tier14_4pc", function() return set_bonus.tier14_4pc end )
spec:RegisterGear( "tier15_2pc", function() return set_bonus.tier15_2pc end )
spec:RegisterGear( "tier15_4pc", function() return set_bonus.tier15_4pc end )
spec:RegisterGear( "tier16_2pc", function() return set_bonus.tier16_2pc end )
spec:RegisterGear( "tier16_4pc", function() return set_bonus.tier16_4pc end )

-- Talents (MoP talent system - ID, enabled, spell_id)
spec:RegisterTalents( {
    -- Tier 1 (Level 15) - Mobility
    juggernaut                 = { 1, 1, 103826 }, -- Your Charge ability has 2 charges, shares charges with Intervene, and generates 15 Rage.
    double_time                = { 1, 2, 103827 }, -- Your Charge ability has 2 charges, shares charges with Intervene, and no longer generates Rage.
    warbringer                 = { 1, 3, 103828 }, -- Charge also roots the target for 4 sec, and Hamstring generates more Rage.

    -- Tier 2 (Level 30) - Healing/Survival
    second_wind                = { 2, 1, 29838  }, -- While below 35% health, you regenerate 3% of your maximum health every 1 sec. Cannot be triggered if you were reduced below 35% by a creature that rewards experience or honor.
    enraged_regeneration       = { 2, 2, 55694  }, -- Instantly heals you for 10% of your total health and regenerates an additional 10% over 5 sec. Usable whilst stunned, frozen, incapacitated, feared, or asleep. 1 min cooldown.
    impending_victory          = { 2, 3, 103840 }, -- Instantly attack the target causing damage and healing you for 10% of your maximum health. Replaces Victory Rush. 30 sec cooldown.

    -- Tier 3 (Level 45) - Utility
    staggering_shout           = { 3, 1, 107566 }, -- Causes all enemies within 10 yards to have their movement speed reduced by 50% for 15 sec. 40 sec cooldown.
    piercing_howl              = { 3, 2, 12323  }, -- Causes all enemies within 10 yards to have their movement speed reduced by 50% for 15 sec. 30 sec cooldown.
    disrupting_shout           = { 3, 3, 102060 }, -- Interrupts all enemy spell casts and prevents any spell in that school from being cast for 4 sec. 40 sec cooldown.

    -- Tier 4 (Level 60) - Burst DPS
    bladestorm                 = { 4, 1, 46924  }, -- You become a whirlwind of steel, attacking all enemies within 8 yards for 6 sec, but you cannot use Auto Attack, Slam, or Execute during this time. Increases your chance to dodge by 30% for the duration. 1.5 min cooldown.
    shockwave                  = { 4, 2, 46968  }, -- Sends a wave of force in a frontal cone, causing damage and stunning enemies for 4 sec. This ability is usable in all stances. 40 sec cooldown. Cooldown reduced by 20 sec if it strikes at least 3 targets.
    dragon_roar                = { 4, 3, 118000 }, -- Roar powerfully, dealing damage to all enemies within 8 yards, knockback and disarming all enemies for 4 sec. The damage is always a critical hit. 1 min cooldown.

    -- Tier 5 (Level 75) - Survivability
    mass_spell_reflection      = { 5, 1, 114028 }, -- Reflects the next spell cast on you and all allies within 20 yards back at the caster. 1 min cooldown.
    safeguard                  = { 5, 2, 114029 }, -- Intervene also reduces all damage taken by the target by 20% for 6 sec.
    vigilance                  = { 5, 3, 114030 }, -- Focus your protective gaze on a group member, transferring 30% of damage taken to you. In addition, each time the target takes damage, cooldown on your next Taunt is reduced by 3 sec. Lasts 12 sec.

    -- Tier 6 (Level 90) - Damage
    avatar                     = { 6, 1, 107574 }, -- You transform into an unstoppable avatar, increasing damage done by 20% and removing and granting immunity to movement imparing effects for 24 sec. 3 min cooldown.
    bloodbath                  = { 6, 2, 12292  }, -- Increases damage by 30% and causes your auto attacks and damaging abilities to cause the target to bleed for an additional 30% of the damage you initially dealt over 6 sec. Lasts 12 sec. 1 min cooldown.
    storm_bolt                 = { 6, 3, 107570 }, -- Throws your weapon at the target, causing damage and stunning for 3 sec. This ability is usable in all stances. 30 sec cooldown.
} )

-- Protection-specific Glyphs (Enhanced System)
spec:RegisterGlyphs( {
    -- Major Glyphs - DPS/Combat
    [58095] = "bladestorm",             -- Reduces the cooldown of your Bladestorm ability by 15 sec.
    [58372] = "shield_wall",            -- Reduces the cooldown of your Shield Wall ability by 2 min, but also reduces its effect by 20%.
    [58375] = "shield_block",           -- Your Shield Block ability now increases block value by an additional 10% but no longer grants a chance to critically block.
    [58101] = "spell_reflection",       -- Reduces the cooldown of your Spell Reflection ability by 5 sec, but reduces its duration by 1 sec.
    [58387] = "hold_the_line",          -- Your Shield Wall ability now increases your critical block chance by 10% for 12 sec.
    [58357] = "cleaving",               -- Your Cleave ability now strikes up to 3 targets.
    [58358] = "resonating_power",       -- The periodic damage of your Thunder Clap ability now also causes enemies to resonate with energy, dealing 5% of the Thunder Clap damage to nearby enemies within 10 yards.
    [58369] = "incite",                 -- Increases the critical strike chance of your Heroic Strike by 20%, but it costs 10 more rage.
    [58367] = "burning_anger",          -- Increases the critical strike chance of your Thunder Clap and Shock Wave by 20%, but they cost 20 rage.
    [58370] = "sunder_armor",           -- Your Sunder Armor ability now applies a full Sunder Armor effect with a single application.
    [58368] = "thunder_strike",         -- Increases the number of targets your Thunder Clap ability hits by 50%, but reduces its damage by 20%.
    [58373] = "devastate",              -- Your Devastate ability now applies 2 stacks of Sunder Armor.
    [58374] = "revenge",                -- Your Revenge ability now has a 30% chance to reset its own cooldown.
    
    -- Major Glyphs - Mobility/Utility
    [58099] = "bull_rush",              -- Your Charge ability roots the target for 1 sec.
    [58103] = "death_from_above",       -- When you use Charge, you leap into the air on a course to the target.
    [58098] = "hamstring",              -- Reduces the global cooldown triggered by your Hamstring to 0.5 sec.
    [58386] = "long_charge",            -- Increases the range of your Charge and Intervene abilities by 5 yards.
    [58385] = "blitz",                  -- When you use Charge, you charge up to 3 enemies near the target.
    [63324] = "victory_rush",           -- Your Victory Rush ability is usable for an additional 5 sec after the duration expires, but heals you for 50% less.
    [58096] = "bloody_healing",         -- Your Victory Rush and Impending Victory abilities heal you for an additional 10% of your max health.
    
    -- Major Glyphs - Defensive/Survivability
    [58097] = "die_by_the_sword",       -- Increases the chance to parry of your Die by the Sword ability by 20%, but reduces its duration by 4 sec.
    [58356] = "unending_rage",          -- Your Enrage effects and Berserker Rage ability last an additional 2 sec.
    [58371] = "shield_slam",            -- Your Shield Slam ability reduces the target's damage done by 10% for 10 sec.
    [58378] = "taunt",                  -- Your Taunt ability now increases your damage done to the target by 10% for 3 sec.
    [58379] = "shield_bash",            -- Your Shield Bash ability now silences the target for 3 sec.
    [58380] = "defensive_stance",       -- Your Defensive Stance now provides 10% magic damage reduction.
    [58381] = "intercept",              -- Your Intercept ability now stuns the target for 1 sec.
    [58382] = "mocking_blow",           -- Your Mocking Blow ability now taunts all enemies within 8 yards.
    
    -- Major Glyphs - Control/CC
    [58377] = "intimidating_shout",     -- Your Intimidating Shout now only causes the targeted enemy to flee.
    [58383] = "rend",                   -- Your Rend ability now spreads to nearby enemies when the target dies.
    [58384] = "commanding_shout",       -- Your Commanding Shout now also provides 10% damage reduction for 10 sec.
    
    -- Minor Glyphs - Visual/Convenience
    [58355] = "battle",                 -- Your Battle Shout now also increases your maximum health by 3% for 1 hour.
    [58376] = "berserker_rage",         -- Your Berserker Rage no longer causes you to become immune to Fear, Sap, or Incapacitate effects.
    [58388] = "bloodrage",              -- Your Bloodrage ability no longer causes you to take damage.
    [58389] = "endurance",              -- Reduces the cooldown of your Second Wind by 30 sec.
    [58390] = "furious_sundering",      -- Your Sunder Armor now reduces the target's movement speed by 10% per stack.
} )

-- Protection Warrior specific auras (Enhanced System with Generate Functions)
spec:RegisterAuras( {
    -- Core Protection Mechanics
    battle_shout = {
        id = 6673,
        duration = 3600,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 6673 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 3600
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    commanding_shout = {
        id = 469,
        duration = 3600,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 469 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 3600
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    shield_block = {
        id = 132404, -- Shield Block buff effect
        duration = 6,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 132404 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 6
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    shield_barrier = {
        id = 112048,
        duration = 6,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 112048 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 6
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    shield_wall = {
        id = 871,
        duration = 12,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 871 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 12
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    last_stand = {
        id = 12975,
        duration = 20,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 12975 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 20
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    vengeance = {
        id = 76691,
        duration = 20, -- Vengeance lasts 20 seconds in MoP
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 76691 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 20
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    berserker_rage = {
        id = 18499,
        duration = function() return glyph.unending_rage.enabled and 8 or 6 end,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 18499 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - (glyph.unending_rage.enabled and 8 or 6)
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    -- Enhanced Ability Tracking
    revenge = {
        id = 6572,
        duration = 5,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 6572 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 5
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    devastate = {
        id = 20243,
        duration = 1,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 20243 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 1
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    shield_slam = {
        id = 23922,
        duration = 1,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 23922 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 1
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    thunder_clap = {
        id = 6343,
        duration = 30,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = FindUnitDebuffByID( "target", 6343 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 30
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    sunder_armor = {
        id = 7386,
        duration = 30,
        max_stack = 3,
        generate = function( t, auraType )
            local aura = FindUnitDebuffByID( "target", 7386 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 30
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    -- MoP Talent Coordination
    avatar = {
        id = 107574,
        duration = 24,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 107574 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 24
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    bladestorm = {
        id = 46924,
        duration = 6,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 46924 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 6
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    bloodbath = {
        id = 12292,
        duration = 12,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 12292 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 12
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    bloodbath_dot = {
        id = 113344,
        duration = 6,
        tick_time = 1,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = FindUnitDebuffByID( "target", 113344 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 6
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    dragon_roar = {
        id = 118000,
        duration = 4,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = FindUnitDebuffByID( "target", 118000 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 4
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    second_wind = {
        id = 29838,
        duration = 3600,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 29838 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 3600
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    vigilance = {
        id = 114030,
        duration = 12,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 114030 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 12
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    -- Enhanced Defensive/Utility Tracking
    spell_reflection = {
        id = 23920,
        duration = function() return glyph.spell_reflection.enabled and 4 or 5 end,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 23920 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - (glyph.spell_reflection.enabled and 4 or 5)
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    mass_spell_reflection = {
        id = 114028,
        duration = 5,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 114028 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 5
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    -- Tier Set and Legendary Tracking
    tier14_2pc = {
        id = 123456, -- Placeholder for T14 2pc effect
        duration = 15,
        max_stack = 1,
        generate = function( t, auraType )
            if set_bonus.tier14_2pc == 1 then
                local aura = UA_GetPlayerAuraBySpellID( 123456 )
                if aura then
                    t.name = aura.name
                    t.count = aura.applications
                    t.expires = aura.expirationTime
                    t.applied = aura.expirationTime - 15
                    t.caster = "player"
                    return
                end
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    tier14_4pc = {
        id = 123457, -- Placeholder for T14 4pc effect
        duration = 20,
        max_stack = 1,
        generate = function( t, auraType )
            if set_bonus.tier14_4pc == 1 then
                local aura = UA_GetPlayerAuraBySpellID( 123457 )
                if aura then
                    t.name = aura.name
                    t.count = aura.applications
                    t.expires = aura.expirationTime
                    t.applied = aura.expirationTime - 20
                    t.caster = "player"
                    return
                end
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    
    legendary_cloak = {
        id = 146046, -- Legendary cloak proc effect
        duration = 15,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 146046 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 15
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"        end,
    },
    
    -- Missing auras for APL compatibility
    victory_rush = {
        id = 32216,
        duration = 20,
        max_stack = 1,
        generate = function( t, auraType )
            local aura = UA_GetPlayerAuraBySpellID( 32216 )
            if aura then
                t.name = aura.name
                t.count = aura.applications
                t.expires = aura.expirationTime
                t.applied = aura.expirationTime - 20
                t.caster = "player"
                return
            end
            
            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },

    -- Additional auras needed for APL imports
    shield_slam_ready = {
        id = 52437,
        duration = 5,
        max_stack = 1,
    },
    revenge_ready = {
        id = 5302,
        duration = 5,
        max_stack = 1,
    },
    
    -- Crowd control and utility
    intimidating_shout = {
        id = 5246,
        duration = 8,
        max_stack = 1,
    },
    demoralizing_shout = {
        id = 1160,
        duration = 30,
        max_stack = 1,
    },
    shockwave = {
        id = 46968,
        duration = 4,
        max_stack = 1,
    },
    storm_bolt = {
        id = 107570,
        duration = 3,
        max_stack = 1,
    },
    hamstring = {
        id = 1715,
        duration = 15,
        max_stack = 1,
    },
    piercing_howl = {
        id = 12323,
        duration = 15,
        max_stack = 1,
    },
    taunt = {
        id = 355,
        duration = 3,
        max_stack = 1,
    },
    thunder_clap_debuff = {
        id = 6343,
        duration = 30,
        max_stack = 1,
    },
    
    -- Shield Slam related auras
    shield_slam_debuff = {
        id = 23922, -- Shield Slam debuff on target
        duration = 10,
        max_stack = 1,
    },
    
    shield_slam_silence = {
        id = 58117, -- Glyph of Shield Slam silence effect
        duration = 3,
        max_stack = 1,
    },
    
    shield_slam_threat = {
        id = 23922, -- Threat multiplier buff for Shield Slam
        duration = 3,
        max_stack = 1,
    },
    
} )

-- Protection Warrior State Variables and Helper Functions

-- Protection Warrior State Variables and Helper Functions
spec:RegisterStateExpr( "rage_deficit", function()
    return rage.max - rage.current
end )

spec:RegisterStateExpr( "rage_percent", function()
    return ( rage.current / rage.max ) * 100
end )

spec:RegisterStateExpr( "shield_block_charges_full", function()
    return cooldown.shield_block.charges == cooldown.shield_block.max_charges
end )

spec:RegisterStateExpr( "shield_block_charges_deficit", function()
    return cooldown.shield_block.max_charges - cooldown.shield_block.charges
end )

spec:RegisterStateExpr( "sunder_armor_missing", function()
    if not state.settings.maintain_sunder_armor then return false end
    return debuff.sunder_armor.down or debuff.sunder_armor.stack < 3
end )

spec:RegisterStateExpr( "revenge_available", function()
    return buff.revenge_ready.up or cooldown.revenge.ready
end )

spec:RegisterStateExpr( "incoming_damage_5s", function()
    return damage.incoming_damage_5s or 0
end )

spec:RegisterStateExpr( "health_pct", function()
    return ( health.current / health.max ) * 100
end )

spec:RegisterStateExpr( "threat_status", function()
    -- Simplified threat status: 0 = no threat, 1 = threat, 2 = high threat
    -- In practice, this would be calculated from combat log events
    return state.threat_status or 1
end )

spec:RegisterStateExpr( "vengeance_stacks", function()
    return buff.vengeance.stack or 0
end )

-- Protection Warrior specific state table modifications

-- Protection Warrior specific state table modifications
spec:RegisterStateTable( "protection", {
    -- Defensive cooldown priorities
    defensive_priority = {
        emergency = { "last_stand", "shield_wall" },
        major = { "shield_wall", "spell_reflection" },
        minor = { "shield_barrier", "shield_block" }
    },
    
    -- Rage management thresholds
    rage = {
        emergency = 10,
        low = 20,
        comfortable = 40,
        high = 80,
        max = 100
    },
    
    -- Threat management
    threat = {
        single_target_rotation = { "shield_slam", "revenge", "devastate" },
        aoe_rotation = { "thunder_clap", "revenge", "shield_slam" },
        emergency_threat = { "taunt", "challenging_shout" }
    },
    
    -- Buff/Debuff priorities
    maintain_buffs = { "battle_shout", "commanding_shout" },
    maintain_debuffs = { "sunder_armor", "thunder_clap_debuff" },
    
    -- Cooldown usage guidelines
    use_on_pull = { "charge", "shield_slam" },
    use_on_aoe = { "thunder_clap", "cleave" },
    use_emergency = { "last_stand", "shield_wall", "enraged_regeneration" }
} )



-- MoP Protection Warrior specific functions
spec:RegisterHook( "reset_precast", function()
    -- Reset any Protection-specific state
    if talent.vigilance.enabled and buff.vigilance.down then
        -- Track vigilance target if needed
    end
    
    -- Calculate optimal rage spending
    if rage.current > 80 then
        state.rage_overflow = true
    else
        state.rage_overflow = false
    end
    
    -- Track Shield Block charges more accurately
    if cooldown.shield_block.charges > 0 and buff.shield_block.down then
        state.shield_block_ready = true
    else
        state.shield_block_ready = false
    end
end )



-- Protection Warrior abilities

-- Protection Warrior abilities
spec:RegisterAbilities( {
    -- Core rotational abilities
    devastate = {
        id = 20243,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        startsCombat = true,
        texture = 132363,
        
        handler = function()
            -- 20% chance to reset Shield Slam cooldown
            if math.random() < 0.2 then
                setCooldown( "shield_slam", 0 )
            end
            
            applyBuff( "devastate" )
            
            -- Apply Sunder Armor stack
            if debuff.sunder_armor.stack < 3 then
                if glyph.sunder_armor.enabled then
                    applyDebuff( "target", "sunder_armor", nil, 3 )
                else
                    addStack( "sunder_armor", "target", 1 )
                end
            else
                applyDebuff( "target", "sunder_armor" )
            end
        end,
    },
    
    shield_slam = {
        id = 23922,
        cast = 0,
        cooldown = 6,
        gcd = "spell",
        
        spend = -15, -- Generates 15 rage in MoP
        spendType = "rage",
        
        requires = "shield",
        startsCombat = true,
        texture = 132357,
        
        handler = function()
            -- Shield Slam is Protection's signature ability
            gain( 15, "rage" ) -- Explicit rage generation
            
            -- MoP: Shield Slam damage scales with block value
            -- Apply Shield Slam debuff (reduces damage dealt)
            applyDebuff( "target", "shield_slam_debuff", 10 )
            
            -- Shield Mastery: Chance for defensive benefits
            if spec.protection and math.random() < 0.3 then
                -- 30% chance to proc Shield Block charge refresh
                if cooldown.shield_block.charges < 2 then
                    cooldown.shield_block.charges = cooldown.shield_block.charges + 1
                end
            end
            
            -- Glyph of Shield Slam: Silence effect
            if glyph.shield_slam.enabled then
                applyDebuff( "target", "shield_slam_silence", 3 )
            end
            
            -- Apply brief threat multiplier (Protection specialty)
            applyBuff( "shield_slam_threat", 3 ) -- Brief threat boost
        end,
    },
    
    thunder_clap = {
        id = 6343,
        cast = 0,
        cooldown = 6,
        gcd = "spell",
        
        spend = function() 
            if glyph.burning_anger.enabled then return 20 end
            return 0 
        end,
        spendType = "rage",
        
        startsCombat = true,
        texture = 136105,
        
        handler = function()
            -- Apply Deep Wounds effect (handled by the game)
        end,
    },
    
    revenge = {
        id = 6572,
        cast = 0,
        cooldown = 9,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        requires = "shield",
        startsCombat = true,
        texture = 132353,
        
        handler = function()
            -- Generates 15 rage
            gain( 15, "rage" )
        end,
    },
    
    heroic_strike = {
        id = 78,
        cast = 0,
        cooldown = 0,
        gcd = "off",
        
        spend = function() 
            if glyph.incite.enabled then return 40 end
            return 30 
        end,
        spendType = "rage",
        
        startsCombat = true,
        texture = 132282,
        
        handler = function()
            -- No specific effect other than damage
        end,
    },
    
    cleave = {
        id = 845,
        cast = 0,
        cooldown = 0,
        gcd = "off",
        
        spend = 20,
        spendType = "rage",
        
        startsCombat = true,
        texture = 132338,
        
        handler = function()
            -- No specific effect for Cleave
        end,
    },
    
    -- Defensive abilities
    shield_block = {
        id = 2565,
        cast = 0,
        cooldown = 9,
        charges = 2,
        recharge = 9,
        gcd = "off",
        
        spend = 60,
        spendType = "rage",
        
        toggle = "defensives",
        requires = "shield",
        
        startsCombat = false,
        texture = 132110,
        
        aura = "shield_block",
        
        handler = function()
            applyBuff( "shield_block" )
        end,
    },
    
    shield_barrier = {
        id = 112048,
        cast = 0,
        cooldown = 1.5,
        gcd = "off",
        
        spend = function() 
            -- Min 20, can use up to 60 rage for a stronger barrier
            return 20
        end,
        spendType = "rage",
        
        toggle = "defensives",
        requires = "shield",
        
        startsCombat = false,
        texture = 600676,
        
        aura = "shield_barrier",
        
        handler = function()
            applyBuff( "shield_barrier" )
        end,
    },
    
    shield_wall = {
        id = 871,
        cast = 0,
        cooldown = function() return glyph.shield_wall.enabled and 180 or 300 end,
        gcd = "off",
        
        toggle = "defensives",
        
        startsCombat = false,
        texture = 132362,
        
        handler = function()
            applyBuff( "shield_wall" )
            
            if glyph.hold_the_line.enabled then
                -- Increase critical block chance by 10% (handled by the game)
            end
        end,
    },
    
    last_stand = {
        id = 12975,
        cast = 0,
        cooldown = 180,
        gcd = "off",
        
        toggle = "defensives",
        
        startsCombat = false,
        texture = 135871,
        
        handler = function()
            applyBuff( "last_stand" )
            -- Increases max health by 30% and heals for that amount
            local health_increase = health.max * 0.3
            gain( health_increase, "health" )
        end,
    },
    
    -- Utility abilities
    battle_shout = {
        id = 6673,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        startsCombat = false,
        texture = 132333,
        
        handler = function()
            applyBuff( "battle_shout" )
        end,
    },
    
    commanding_shout = {
        id = 469,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        startsCombat = false,
        texture = 132351,
        
        handler = function()
            applyBuff( "commanding_shout" )
        end,
    },
    
    charge = {
        id = 100,
        cast = 0,
        cooldown = function() 
            if talent.juggernaut.enabled or talent.double_time.enabled then
                return 20
            end
            return 20 
        end,
        charges = function()
            if talent.juggernaut.enabled or talent.double_time.enabled then
                return 2
            end
            return 1
        end,
        recharge = 20,
        gcd = "off",
        
        spend = function()
            if talent.juggernaut.enabled then return -15 end
            return 0
        end,
        spendType = "rage",
        
        range = function() 
            if glyph.long_charge.enabled then
                return 30
            end
            return 25 
        end,
        
        startsCombat = true,
        texture = 132337,
        
        handler = function()
            if talent.warbringer.enabled or glyph.bull_rush.enabled then
                applyDebuff( "target", "charge_root" )
            end
        end,
    },
    
    intervene = {
        id = 3411,
        cast = 0,
        cooldown = function() 
            if talent.juggernaut.enabled or talent.double_time.enabled then
                return 20
            end
            return 30 
        end,
        charges = function()
            if talent.juggernaut.enabled or talent.double_time.enabled then
                return 2
            end
            return 1
        end,
        recharge = function() 
            if talent.juggernaut.enabled or talent.double_time.enabled then
                return 20
            end
            return 30 
        end,
        gcd = "off",
        
        spend = 0,
        spendType = "rage",
        
        range = function() 
            if glyph.long_charge.enabled then
                return 30
            end
            return 25 
        end,
        
        startsCombat = false,
        texture = 132365,
        
        handler = function()
            if talent.safeguard.enabled then
                -- Apply damage reduction to the target (handled by the game)
            end
        end,
    },
    
    heroic_leap = {
        id = 6544,
        cast = 0,
        cooldown = 45,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        startsCombat = true,
        texture = 236171,
        
        handler = function()
            -- No specific effect, just the leap
        end,
    },
    
    berserker_rage = {
        id = 18499,
        cast = 0,
        cooldown = 30,
        gcd = "off",
        
        spend = 0,
        spendType = "rage",
        
        startsCombat = false,
        texture = 136009,
        
        handler = function()
            applyBuff( "berserker_rage" )
        end,
    },
    
    taunt = {
        id = 355,
        cast = 0,
        cooldown = 8,
        gcd = "off",
        
        startsCombat = true,
        texture = 136080,
        
        handler = function()
            applyDebuff( "target", "taunt" )
        end,
    },
    
    rallying_cry = {
        id = 97462,
        cast = 0,
        cooldown = 180,
        gcd = "spell",
        
        toggle = "defensives",
        
        startsCombat = false,
        texture = 132351,
        
        handler = function()
            applyBuff( "rallying_cry" )
        end,
    },
    
    -- Talent abilities
    avatar = {
        id = 107574,
        cast = 0,
        cooldown = 180,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        toggle = "cooldowns",
        
        startsCombat = false,
        texture = 613534,
        
        handler = function()
            applyBuff( "avatar" )
        end,
    },
    
    bloodbath = {
        id = 12292,
        cast = 0,
        cooldown = 60,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        toggle = "cooldowns",
        
        startsCombat = false,
        texture = 236304,
        
        handler = function()
            applyBuff( "bloodbath" )
        end,
    },
    
    bladestorm = {
        id = 46924,
        cast = 0,
        cooldown = function() return glyph.bladestorm.enabled and 75 or 90 end,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        toggle = "cooldowns",
        
        startsCombat = true,
        texture = 236303,
        
        handler = function()
            applyBuff( "bladestorm" )
        end,
    },
    
    dragon_roar = {
        id = 118000,
        cast = 0,
        cooldown = 60,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        toggle = "cooldowns",
        
        startsCombat = true,
        texture = 642418,
        
        handler = function()
            applyDebuff( "target", "dragon_roar" )
        end,
    },
    
    shockwave = {
        id = 46968,
        cast = 0,
        cooldown = 40,
        gcd = "spell",
        
        spend = function() 
            if glyph.burning_anger.enabled then return 20 end
            return 0 
        end,
        spendType = "rage",
        
        toggle = "cooldowns",
        
        startsCombat = true,
        texture = 236312,
        
        handler = function()
            applyDebuff( "target", "shockwave" )
        end,
    },
    
    storm_bolt = {
        id = 107570,
        cast = 0,
        cooldown = 30,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        toggle = "cooldowns",
        
        startsCombat = true,
        texture = 613535,
        
        handler = function()
            applyDebuff( "target", "storm_bolt" )
        end,
    },
    
    vigilance = {
        id = 114030,
        cast = 0,
        cooldown = 120,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        toggle = "cooldowns",
        
        startsCombat = false,
        texture = 236331,
        
        handler = function()
            applyBuff( "vigilance" )
        end,
    },
    
    impending_victory = {
        id = 103840,
        cast = 0,
        cooldown = 30,
        gcd = "spell",
        
        spend = 10,
        spendType = "rage",
        
        startsCombat = true,
        texture = 589768,
        
        handler = function()
            local heal_amount = health.max * (glyph.bloody_healing.enabled and 0.2 or 0.1)
            gain( heal_amount, "health" )
        end,
    },
    
    staggering_shout = {
        id = 107566,
        cast = 0,
        cooldown = 40,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        startsCombat = true,
        texture = 132346,
        
        handler = function()
            applyDebuff( "target", "staggering_shout" )
        end,
    },
    
    piercing_howl = {
        id = 12323,
        cast = 0,
        cooldown = 30,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        startsCombat = true,
        texture = 132117,
        
        handler = function()
            applyDebuff( "target", "piercing_howl" )
        end,
    },
    
    disrupting_shout = {
        id = 102060,
        cast = 0,
        cooldown = 40,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        toggle = "interrupts",
        
        startsCombat = true,
        texture = 132117,
        
        handler = function()
            applyDebuff( "target", "disrupting_shout" )
        end,
    },
    
    sunder_armor = {
        id = 7386,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 15,
        spendType = "rage",
        
        startsCombat = true,
        texture = 132363,
        
        aura = "sunder_armor",
        
        handler = function()
            if debuff.sunder_armor.stack < 3 then
                if glyph.sunder_armor.enabled then
                    applyDebuff( "target", "sunder_armor", nil, 3 )
                else
                    addStack( "sunder_armor", "target", 1 )
                end
            else
                applyDebuff( "target", "sunder_armor" )
            end
            
            if glyph.furious_sundering.enabled then
                -- Apply movement speed reduction (handled by game)
            end
        end,
    },
    
    enraged_regeneration = {
        id = 55694,
        cast = 0,
        cooldown = 60,
        gcd = "off",
        
        spend = 0,
        spendType = "rage",
        
        toggle = "defensives",
        
        startsCombat = false,
        texture = 132345,
        
        handler = function()
            local instant_heal = health.max * 0.1
            gain( instant_heal, "health" )
            applyBuff( "enraged_regeneration" )
        end,
    },
    
    spell_reflection = {
        id = 23920,
        cast = 0,
        cooldown = function() return glyph.spell_reflection.enabled and 20 or 25 end,
        gcd = "off",
        
        spend = 0,
        spendType = "rage",
        
        toggle = "defensives",
        
        startsCombat = false,
        texture = 132361,
        
        handler = function()
            applyBuff( "spell_reflection" )
        end,
    },
    
    mass_spell_reflection = {
        id = 114028,
        cast = 0,
        cooldown = 60,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        toggle = "defensives",
        
        startsCombat = false,
        texture = 132361,
        
        handler = function()
            applyBuff( "mass_spell_reflection" )
        end,
    },
    
    war_banner = {
        id = 114207,
        cast = 0,
        cooldown = 180,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        toggle = "cooldowns",
        
        startsCombat = false,
        texture = 603532,
        
        handler = function()
            applyBuff( "war_banner" )
        end,
    },
    
    demoralizing_shout = {
        id = 1160,
        cast = 0,
        cooldown = 60,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        startsCombat = true,
        texture = 132366,
        
        handler = function()
            applyDebuff( "target", "demoralizing_shout" )
        end,
    },
    
    intimidating_shout = {
        id = 5246,
        cast = 0,
        cooldown = 90,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        startsCombat = true,
        texture = 132154,
        
        handler = function()
            applyDebuff( "target", "intimidating_shout" )
        end,
    },
    
    
    heroic_throw = {
        id = 57755,
        cast = 0,
        cooldown = 30,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        range = 30,
        
        startsCombat = true,
        texture = 132453,
        
        handler = function()
            -- Ranged attack that interrupts spellcasting
        end,
    },
    
    victory_rush = {
        id = 34428,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        startsCombat = false,
        texture = 132342,
        
        usable = function() return buff.victory_rush.up, "requires victory rush proc" end,
        
        handler = function()
            local heal_amount = health.max * (glyph.bloody_healing.enabled and 0.2 or 0.1)
            gain( heal_amount, "health" )
            removeBuff( "victory_rush" )
        end,
    },
    
    stance = {
        id = 71,  -- Defensive Stance
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        
        spend = 0,
        spendType = "rage",
        
        startsCombat = false,
        texture = 132341,
        
        handler = function()
            -- Switch to defensive stance
        end,
    },
} )

-- Range
spec:RegisterRanges( "devastate", "charge", "heroic_throw" )

-- Protection Warrior Settings
spec:RegisterSetting( "use_shield_wall", true, {
    name = strformat( "Use %s", Hekili:GetSpellLinkWithTexture( 871 ) ), -- Shield Wall
    desc = "If checked, Shield Wall will be recommended when health drops below the defensive threshold. If unchecked, it will not be recommended automatically.",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "use_last_stand", true, {
    name = strformat( "Use %s", Hekili:GetSpellLinkWithTexture( 12975 ) ), -- Last Stand
    desc = "If checked, Last Stand will be recommended as an emergency defensive cooldown. If unchecked, it will not be recommended automatically.",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "defensive_health_threshold", 50, {
    name = "Defensive Cooldown Health Threshold",
    desc = "Health percentage threshold below which major defensive cooldowns will be recommended (Shield Wall, Last Stand).",
    type = "range",
    min = 20,
    max = 80,
    step = 5,
    width = 1.5
} )

spec:RegisterSetting( "shield_barrier_rage_threshold", 60, {
    name = strformat( "%s Rage Threshold", Hekili:GetSpellLinkWithTexture( 112048 ) ), -- Shield Barrier
    desc = "Minimum rage required before recommending Shield Barrier for rage dumping.",
    type = "range",
    min = 20,
    max = 100,
    step = 10,
    width = 1.5
} )

spec:RegisterSetting( "maintain_sunder_armor", true, {
    name = strformat( "Maintain %s", Hekili:GetSpellLinkWithTexture( 7386 ) ), -- Sunder Armor
    desc = "If checked, the addon will prioritize maintaining 3 stacks of Sunder Armor on the target.",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "shield_block_priority", "automatic", {
    name = strformat( "%s Priority", Hekili:GetSpellLinkWithTexture( 2565 ) ), -- Shield Block
    desc = "When to prioritize Shield Block usage:",
    type = "select",
    values = {
        automatic = "Automatic (when taking physical damage)",
        always = "Always maintain uptime",
        defensive = "Only when low health",
        never = "Never recommend"
    },
    width = 2
} )

spec:RegisterSetting( "vengeance_optimization", true, {
    name = strformat( "Optimize for %s", Hekili:GetSpellLinkWithTexture( 76691 ) ), -- Vengeance
    desc = "If checked, the rotation will prioritize damage abilities when Vengeance stacks are high.",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "vengeance_stack_threshold", 5, {
    name = "Vengeance Stack Threshold",
    desc = "Minimum Vengeance stacks before prioritizing damage abilities over pure threat abilities.",
    type = "range",
    min = 1,
    max = 10,
    step = 1,
    width = 1.5
} )

spec:RegisterSetting( "aoe_enemy_threshold", 3, {
    name = "AoE Enemy Threshold",
    desc = "Number of enemies required before switching to AoE rotation (Thunder Clap, Cleave).",
    type = "range",
    min = 2,
    max = 8,
    step = 1,
    width = 1.5
} )

spec:RegisterSetting( "use_heroic_strike", true, {
    name = strformat( "Use %s", Hekili:GetSpellLinkWithTexture( 78 ) ), -- Heroic Strike
    desc = "If checked, Heroic Strike will be recommended for rage dumping on single targets.",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "threat_mode_priority", "survival", {
    name = "Rotation Priority Mode",
    desc = "Select the primary focus of the rotation:",
    type = "select",
    values = {
        survival = "Survival (Maximum Mitigation)",
        threat = "Threat (Maximum Threat Generation)",
        balanced = "Balanced (Survival + Threat)",
        damage = "Damage (When Vengeance is High)"
    },
    width = 2
} )

spec:RegisterSetting( "auto_taunt", true, {
    name = strformat( "Auto-Recommend %s", Hekili:GetSpellLinkWithTexture( 355 ) ), -- Taunt
    desc = "If checked, Taunt will be recommended when threat is low or lost.",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "use_spell_reflection", true, {
    name = strformat( "Use %s", Hekili:GetSpellLinkWithTexture( 23920 ) ), -- Spell Reflection
    desc = "If checked, Spell Reflection will be recommended against incoming magical attacks.",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "cooldown_usage", "defensive", {
    name = "Cooldown Usage Priority",
    desc = "When to use major cooldowns (Avatar, Bloodbath, etc.):",
    type = "select",
    values = {
        defensive = "Defensive situations only",
        aggressive = "Use for damage when safe",
        automatic = "Automatic based on situation",
        never = "Never recommend"
    },
    width = 2
} )

spec:RegisterSetting( "maintain_buffs", true, {
    name = "Maintain Shouts",
    desc = "If checked, the addon will remind you to maintain Battle Shout or Commanding Shout.",
    type = "toggle",
    width = "full"
} )

spec:RegisterSetting( "use_berserker_rage", true, {
    name = strformat( "Use %s", Hekili:GetSpellLinkWithTexture( 18499 ) ), -- Berserker Rage
    desc = "If checked, Berserker Rage will be recommended for fear/charm immunity and rage generation.",
    type = "toggle",
    width = "full"
} )


