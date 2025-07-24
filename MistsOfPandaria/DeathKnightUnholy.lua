-- DeathKnightUnholy.lua
-- January 2025

-- MoP: Use UnitClass instead of UnitClassBase
local _, playerClass = UnitClass('player')
if playerClass ~= 'DEATHKNIGHT' then return end

local addon, ns = ...
local Hekili = _G[ addon ]
local class, state = Hekili.Class, Hekili.State

local FindUnitBuffByID = ns.FindUnitBuffByID
local strformat = string.format

local spec = Hekili:NewSpecialization( 252, true )

spec.name = "Unholy"
spec.role = "DAMAGER"
spec.primaryStat = 1 -- Strength

-- Register resources using MoP power types from Constants.lua
spec:RegisterResource( 5 ) -- Runes = 5 in MoP
spec:RegisterResource( 6 ) -- RunicPower = 6 in MoP

spec:RegisterResource( 5, {
    rune_regen = {
        last = function () return state.query_time end,
        stop = function( x ) return x == 6 end,

        interval = function( time, val )
            val = floor( val )
            if val == 6 then return -1 end
            return state.runes.expiry[ val + 1 ] - time
        end,
        value = 1,
    }
}, setmetatable( {
    expiry = { 0, 0, 0, 0, 0, 0 },
    cooldown = 10,
    regen = 0,
    max = 6,
    forecast = {},
    fcount = 0,
    times = {},
    values = {},
    resource = "runes",

    reset = function()
        local t = state.runes
        for i = 1, 6 do
            local start, duration, ready = GetRuneCooldown( i )
            start = start or 0
            duration = duration or ( 10 * state.haste )
            t.expiry[ i ] = ready and 0 or ( start + duration )
            t.cooldown = duration
        end
        table.sort( t.expiry )
        t.actual = nil -- Reset actual to force recalculation
    end,

    gain = function( amount )
        local t = state.runes
        for i = 1, amount do
            table.insert( t.expiry, 0 )
            t.expiry[ 7 ] = nil
        end
        table.sort( t.expiry )
        t.actual = nil
    end,

    spend = function( amount )
        local t = state.runes
        for i = 1, amount do
            local nextReady = ( t.expiry[ 4 ] > 0 and t.expiry[ 4 ] or state.query_time ) + t.cooldown
            table.remove( t.expiry, 1 )
            table.insert( t.expiry, nextReady )
        end

        state.gain( amount * 10, "runic_power" )
        if state.set_bonus.tier20_4pc == 1 then
            state.cooldown.army_of_the_dead.expires = max( 0, state.cooldown.army_of_the_dead.expires - 1 )
        end

        t.actual = nil
    end,

    timeTo = function( x )
        return state:TimeToResource( state.runes, x )
    end,
}, {
    __index = function( t, k )
        if k == "actual" then
            -- Calculate the number of runes available based on `expiry`.
            local amount = 0
            for i = 1, 6 do
                if t.expiry[ i ] <= state.query_time then
                    amount = amount + 1
                end
            end
            return amount

        elseif k == "current" then
            -- If this is a modeled resource, use our lookup system.
            if t.forecast and t.fcount > 0 then
                local q = state.query_time
                local index, slice

                if t.values[ q ] then return t.values[ q ] end

                for i = 1, t.fcount do
                    local v = t.forecast[ i ]
                    if v.t <= q and v.v ~= nil then
                        index = i
                        slice = v
                    else
                        break
                    end
                end

                -- We have a slice.
                if index and slice and slice.v then
                    t.values[ q ] = max( 0, min( t.max, slice.v ) )
                    return t.values[ q ]
                end
            end

            return t.actual

        elseif k == "current_fractional" then
            local current = t.current
            local fraction = t.cooldown and ( t.time_to_next / t.cooldown ) or 0

            return current + fraction

        elseif k == "deficit" then
            return t.max - t.current

        elseif k == "time_to_next" then
            return t[ "time_to_" .. t.current + 1 ]

        elseif k == "time_to_max" then
            return t.current == t.max and 0 or max( 0, t.expiry[ 6 ] - state.query_time )

        else
            local amount = k:match( "time_to_(%d+)" )
            amount = amount and tonumber( amount )
            if amount then return t.timeTo( amount ) end
        end
    end
}))

spec:RegisterResource( 6, {
    -- Frost Fever Tick RP (20% chance to generate 4 RP)
    frost_fever_tick = {
        aura = "frost_fever",

        last = function ()
            local app = state.dot.frost_fever.applied
            return app + floor( state.query_time - app )
        end,

        interval = 1,
        value = function ()
            -- 20% chance * 4 RP = 0.8 RP per tick
            -- We'll lowball to 0.6 RP for conservative estimate
            return 0.6 * min( state.active_dot.frost_fever or 0, 5 )
        end,
    },

    -- Runic Attenuation (mainhand swings 50% chance to generate 3 RP)
    runic_attenuation = {
        talent = "runic_attenuation",
        swing = "mainhand",

        last = function ()
            local swing = state.swings.mainhand
            local t = state.query_time
            if state.mainhand_speed == 0 then
                return 0
            else
                return swing + floor( ( t - swing ) / state.mainhand_speed ) * state.mainhand_speed
            end
        end,

        interval = "mainhand_speed",

        stop = function () return state.swings.mainhand == 0 end,

        value = function ()
            -- 50% chance * 3 RP = 1.5 RP per swing
            -- We'll lowball to 1.0 RP
            return state.talent.runic_attenuation.enabled and 1.0 or 0
        end,
    }
} )


local spendHook = function( amt, resource, noHook )
    if amt > 0 and resource == "runes" and active_dot.shackle_the_unworthy > 0 then
        reduceCooldown( "shackle_the_unworthy", 4 * amt )
    end
end

spec:RegisterHook( "spend", spendHook )

-- Talents
spec:RegisterTalents( {
    -- Tier 1 (Level 56)
    roiling_blood             = { 1, 1, 108170 }, -- Your Pestilence refreshes disease durations and spreads diseases from each diseased target to all other targets.
    plague_leech              = { 1, 2, 123693 }, -- Extract diseases from an enemy target, consuming up to 2 diseases on the target to gain 1 Rune of each type that was removed.
    unholy_blight             = { 1, 3, 115989 }, -- Causes you to spread your diseases to all enemy targets within 10 yards.

    -- Tier 2 (Level 57)
    lichborne                 = { 2, 1,  49039 }, -- Draw upon unholy energy to become undead for 10 sec. While undead, you are immune to Charm, Fear, and Sleep effects.
    anti_magic_zone           = { 2, 2,  51052 }, -- Places a large, stationary Anti-Magic Zone that reduces spell damage taken by party or raid members by 40%. The Anti-Magic Zone lasts for 30 sec or until it absorbs a massive amount of spell damage.
    purgatory                 = { 2, 3, 114556 }, -- An unholy pact that prevents fatal damage, instead absorbing incoming healing equal to the damage that would have been fatal for 3 sec.

    -- Tier 3 (Level 58)
    deaths_advance            = { 3, 1,  96268 }, -- For 8 sec, you are immune to movement impairing effects and your movement speed is increased by 50%.
    chilblains                = { 3, 2,  50041 }, -- Victims of your Chains of Ice take 5% increased damage from your abilities for 8 sec.
    asphyxiate                = { 3, 3, 108194 }, -- Lifts the enemy target off the ground, crushing their throat and stunning them for 5 sec.

    -- Tier 4 (Level 60)
    death_pact                = { 4, 1,  48743 }, -- Drains 50% of your summoned minion's health to heal you for 25% of your maximum health.
    death_siphon              = { 4, 2, 108196 }, -- Deals Shadow damage to the target and heals you for 150% of the damage dealt.
    conversion                = { 4, 3, 119975 }, -- Continuously converts 2% of your maximum health per second into 20% of maximum health as healing.

    -- Tier 5 (Level 75)
    blood_tap                 = { 5, 1,  45529 }, -- Consume 5 charges from your Blood Charges to immediately activate a random depleted rune.
    runic_empowerment         = { 5, 2,  81229 }, -- When you use a rune, you have a 45% chance to immediately regenerate that rune.
    runic_corruption          = { 5, 3,  51462 }, -- When you hit with a Death Coil, Frost Strike, or Rune Strike, you have a 45% chance to regenerate a rune.

    -- Tier 6 (Level 90)
    gorefiends_grasp          = { 6, 1, 108199 }, -- Shadowy tendrils coil around all enemies within 20 yards of a hostile target, pulling them to the target's location.
    remorseless_winter        = { 6, 2, 108200 }, -- Surrounds the Death Knight with a swirling blizzard that grows over 8 sec, slowing enemies by up to 50% and reducing their melee and ranged attack speed by up to 20%.
    desecrated_ground         = { 6, 3, 108201 }, -- Corrupts the ground beneath you, causing all nearby enemies to deal 10% less damage for 30 sec.
} )

-- Glyphs (Enhanced System - authentic MoP 5.4.8 glyph system)
spec:RegisterGlyphs( {
    -- Major glyphs - Unholy Combat
    [58616] = "anti_magic_shell",    -- Reduces the cooldown on Anti-Magic Shell by 5 sec, but the amount it absorbs is reduced by 50%
    [58617] = "army_of_the_dead",    -- Your Army of the Dead spell summons an additional skeleton, but the cast time is increased by 2 sec
    [58618] = "bone_armor",          -- Your Bone Armor gains an additional charge but the duration is reduced by 30 sec
    [58619] = "chains_of_ice",       -- Your Chains of Ice no longer reduces movement speed but increases the duration by 2 sec
    [58620] = "dark_simulacrum",     -- Dark Simulacrum gains an additional charge but the duration is reduced by 4 sec
    [58621] = "death_and_decay",     -- Your Death and Decay no longer slows enemies but lasts 50% longer
    [58622] = "death_coil",          -- Your Death Coil refunds 20 runic power when used on friendly targets but heals for 30% less
    [58623] = "death_grip",          -- Your Death Grip no longer moves the target but reduces its movement speed by 50% for 8 sec
    [58624] = "death_pact",          -- Your Death Pact no longer requires a ghoul but heals for 50% less
    [58625] = "death_strike",        -- Your Death Strike deals 25% additional damage but heals for 25% less
    [58626] = "frost_strike",        -- Your Frost Strike has no runic power cost but deals 20% less damage
    [58627] = "heart_strike",        -- Your Heart Strike generates 10 additional runic power but affects 1 fewer target
    [58628] = "icebound_fortitude",  -- Your Icebound Fortitude grants immunity to stun effects but the damage reduction is lowered by 20%
    [58629] = "icy_touch",           -- Your Icy Touch dispels 1 beneficial magic effect but no longer applies Frost Fever
    [58630] = "mind_freeze",         -- Your Mind Freeze has its cooldown reduced by 2 sec but its range is reduced by 5 yards
    [58631] = "outbreak",            -- Your Outbreak no longer costs a Blood rune but deals 50% less damage
    [58632] = "plague_strike",       -- Your Plague Strike does additional disease damage but no longer applies Blood Plague
    [58633] = "raise_dead",          -- Your Raise Dead spell no longer requires a corpse but the ghoul has 20% less health
    [58634] = "rune_strike",         -- Your Rune Strike generates 10% more threat but costs 10 additional runic power
    [58635] = "rune_tap",            -- Your Rune Tap heals nearby allies for 5% of their maximum health but heals you for 50% less
    [58636] = "scourge_strike",      -- Your Scourge Strike deals additional Shadow damage for each disease on the target but consumes all diseases
    [58637] = "strangulate",         -- Your Strangulate has its cooldown reduced by 10 sec but the duration is reduced by 2 sec
    [58638] = "vampiric_blood",      -- Your Vampiric Blood generates 5 runic power per second but increases damage taken by 10%
    [58639] = "blood_boil",          -- Your Blood Boil deals 20% additional damage but no longer spreads diseases
    [58640] = "dancing_rune_weapon", -- Your Dancing Rune Weapon lasts 5 sec longer but generates 20% less runic power
    [58641] = "vampiric_aura",       -- Your Vampiric Aura affects 2 additional party members but the healing is reduced by 25%
    [58642] = "unholy_frenzy",       -- Your Unholy Frenzy grants an additional 10% attack speed but lasts 50% shorter
    [58643] = "corpse_explosion",    -- Your corpses explode when they expire, dealing damage to nearby enemies
    [58644] = "disease",             -- Your diseases last 50% longer but deal 25% less damage
    [58645] = "resilient_grip",      -- Your Death Grip removes one movement impairing effect from yourself
    [58646] = "shifting_presences",  -- Reduces the rune cost to change presences by 1, but you cannot change presences while in combat
    
    -- Minor glyphs - Cosmetic and convenience
    [58647] = "corpse_walker",       -- Your undead minions appear to be spectral
    [58648] = "the_geist",           -- Your ghoul appears as a geist
    [58649] = "deaths_embrace",      -- Your death grip has enhanced visual effects
    [58650] = "bone_spikes",         -- Your abilities create bone spike visual effects
    [58651] = "unholy_vigor",        -- Your character emanates an unholy aura
    [58652] = "the_bloodied",        -- Your weapons appear to be constantly dripping blood
    [58653] = "runic_mastery",       -- Your runes glow with enhanced energy when available
    [58654] = "the_forsaken",        -- Your character appears more skeletal and undead
    [58655] = "shadow_walk",         -- Your movement leaves shadowy footprints
    [58656] = "deaths_door",         -- Your abilities create portal-like visual effects
} )

-- Auras
spec:RegisterAuras( {
    -- Talent: Absorbing up to $w1 magic damage. Immune to harmful magic effects.
    -- https://wowhead.com/spell=48707
    antimagic_shell = {
        id = 48707,
        duration = 5,
        max_stack = 1
    },
    -- Talent: Stunned.
    -- https://wowhead.com/spell=108194
    asphyxiate = {
        id = 108194,
        duration = 5.0,
        mechanic = "stun",
        type = "Magic",
        max_stack = 1
    },
    -- Talent: Movement slowed $w1% $?$w5!=0[and Haste reduced $w5% ][]by frozen chains.
    -- https://wowhead.com/spell=45524
    chains_of_ice = {
        id = 45524,
        duration = 8,
        mechanic = "snare",
        type = "Magic",
        max_stack = 1
    },
    -- Taunted.
    -- https://wowhead.com/spell=56222
    dark_command = {
        id = 56222,
        duration = 3,
        mechanic = "taunt",
        max_stack = 1
    },
    -- Your next Death Strike is free and heals for an additional $s1% of maximum health.
    -- https://wowhead.com/spell=101568
    dark_succor = {
        id = 101568,
        duration = 20,
        max_stack = 1
    },
    -- Talent: $?$w2>0[Transformed into an undead monstrosity.][Gassy.] Damage dealt increased by $w1%.
    -- https://wowhead.com/spell=63560
    dark_transformation = {
        id = 63560,
        duration = 30,
        type = "Magic",
        max_stack = 1,
        generate = function( t )
            local name, _, count, _, duration, expires, caster, _, _, spellID, _, _, _, _, timeMod, v1, v2, v3 = FindUnitBuffByID( "pet", 63560 )

            if name then
                t.name = t.name or name or class.abilities.dark_transformation.name
                t.count = count > 0 and count or 1
                t.expires = expires
                t.duration = duration
                t.applied = expires - duration
                t.caster = "player"
                return
            end

            t.name = t.name or class.abilities.dark_transformation.name
            t.count = 0
            t.expires = 0
            t.duration = class.auras.dark_transformation.duration
            t.applied = 0
            t.caster = "nobody"
        end
    },
    -- Inflicts $s1 Shadow damage every sec.
    death_and_decay = {
        id = 43265,
        duration = 10,
        tick_time = 1.0,
        max_stack = 1
    },
    -- Your movement speed is increased by $w1%, you cannot be slowed below $s2% of normal speed, and you are immune to forced movement effects and knockbacks.
    deaths_advance = {
        id = 96268,
        duration = 8,
        type = "Magic",
        max_stack = 1
    },
    -- Defile the targeted ground, dealing Shadow damage to all enemies over $d. While you remain within your Defile, your Scourge Strike will hit multiple enemies near the target. If any enemies are standing in the Defile, it grows in size and deals increasing damage every sec.
    defile = {
        id = 152280,
        duration = 30,
        tick_time = 1,
        max_stack = 1
    },
    -- Suffering $w1 Frost damage every $t1 sec.
    -- https://wowhead.com/spell=55095
    frost_fever = {
        id = 55095,
        duration = 30,
        tick_time = 3,
        max_stack = 1,
        type = "Disease"
    },
    -- Talent: Damage taken reduced by $w3%. Immune to Stun effects.
    -- https://wowhead.com/spell=48792
    icebound_fortitude = {
        id = 48792,
        duration = 8,
        max_stack = 1
    },
    -- Leech increased by $s1%$?a389682[, damage taken reduced by $s8%][] and immune to Charm, Fear and Sleep. Undead.
    -- https://wowhead.com/spell=49039
    lichborne = {
        id = 49039,
        duration = 10,
        tick_time = 1,
        max_stack = 1
    },
    -- A necrotic strike shield that absorbs the next $w1 healing received.
    necrotic_strike = {
        id = 73975,
        duration = 15,
        max_stack = 1
    },
    -- Grants the ability to walk across water.
    -- https://wowhead.com/spell=3714
    path_of_frost = {
        id = 3714,
        duration = 600,
        tick_time = 0.5,
        max_stack = 1
    },
    -- Inflicted with a plague that spreads to nearby enemies when dispelled.
    plague_leech = {
        id = 123693,
        duration = 3,
        max_stack = 1
    },
    -- An unholy pact that prevents fatal damage.
    purgatory = {
        id = 114556,
        duration = 3,
        max_stack = 1
    },
    -- TODO: Is a pet.
    raise_dead = {
        id = 46585,
        duration = 60,
        max_stack = 1
    },
    -- Frost damage taken from the Death Knight's abilities increased by $s1%.
    -- https://wowhead.com/spell=51714
    razorice = {
        id = 51714,
        duration = 20,
        tick_time = 1,
        type = "Magic",
        max_stack = 5
    },
    -- Increases your rune regeneration rate for 3 sec.
    runic_corruption = {
        id = 51460,
        duration = function () return 3 * haste end,
        max_stack = 1
    },
    -- Talent: Afflicted by Soul Reaper, if the target is below $s3% health this effect will explode dealing additional Shadowfrost damage.
    -- https://wowhead.com/spell=130736
    soul_reaper = {
        id = 130736,
        duration = 5,
        tick_time = 5,
        type = "Magic",
        max_stack = 1
    },
    -- Your next Death Coil cost no Runic Power and is guaranteed to critically strike.
    sudden_doom = {
        id = 49530,
        duration = 10,
        max_stack = 1
    },
    -- Shadow Infusion stacks that empower your ghoul.
    shadow_infusion = {
        id = 91342,
        duration = 30,
        max_stack = 5
    },
    -- Dark Empowerment increases ghoul damage by 50%.
    dark_empowerment = {
        id = 91342, -- Reusing shadow_infusion ID as it's related
        duration = 30,
        max_stack = 1
    },
    -- Silenced.
    strangulate = {
        id = 47476,
        duration = 5,
        max_stack = 1
    },
    -- The presence of the Unholy, increasing attack speed by 15% and movement speed by 15%.
    unholy_presence = {
        id = 48265,
        duration = 3600,
        max_stack = 1
    },
    -- Suffering $w1 Shadow damage every $t1 sec. Erupts for damage split among all nearby enemies when the infected dies.
    -- https://wowhead.com/spell=191587  
    virulent_plague = {
        id = 191587,
        duration = 21,
        tick_time = 3,
        type = "Disease",
        max_stack = 1
    },
    -- The touch of the spirit realm lingers....
    -- https://wowhead.com/spell=97821
    voidtouched = {
        id = 97821,
        duration = 300,
        max_stack = 1
    },
    -- Talent: Movement speed increased by $w1%. Cannot be slowed below $s2% of normal movement speed. Cannot attack.
    -- https://wowhead.com/spell=212552
    wraith_walk = {
        id = 212552,
        duration = 4,
        max_stack = 1
    },

    -- PvP Talents
    -- Your next spell with a mana cost will be copied by the Death Knight's runeblade.
    dark_simulacrum = {
        id = 77606,
        duration = 12,
        max_stack = 1
    },
    -- Your runeblade contains trapped magical energies, ready to be unleashed.
    dark_simulacrum_buff = {
        id = 77616,
        duration = 12,
        max_stack = 1
    },

    -- Blood Tap charges for converting runes to Death Runes
    blood_charge = {
        id = 114851,
        duration = 60,
        max_stack = 10
    },

    -- Horn of Winter buff - increases Attack Power and Strength
    horn_of_winter = {
        id = 57330,
        duration = 120,
        max_stack = 1
    },

    -- Festering Wounds that burst when consumed by abilities
    festering_wound = {
        id = 194310,
        duration = 30,
        max_stack = 6,
        type = "Disease"
    },

    -- Unholy Blight area effect
    unholy_blight = {
        id = 115989,
        duration = 10,
        max_stack = 1
    },

    -- Inflicted with a disease that deals Shadow damage over time.
    blood_plague = {
        id = 55078,
        duration = 21,
        tick_time = 3,
        type = "Disease",
        max_stack = 1
    }
} )

-- Pets
spec:RegisterPets({
    ghoul = {
        id = 26125,
        spell = "raise_dead",
        duration = function() return talent.raise_dead_2.enabled and 3600 or 60 end
    },
    risen_skulker = {
        id = 99541,
        spell = "raise_dead",
        duration = function() return talent.raise_dead_2.enabled and 3600 or 60 end,
    },
})

-- Totems (which are sometimes pets in MoP)
spec:RegisterTotems( {
    gargoyle = {
        id = 49206,
        duration = 30,
    },
    ghoul = {
        id = 26125,
        duration = function() return talent.raise_dead_2.enabled and 3600 or 60 end,
    },
    army_ghoul = {
        id = 24207,
        duration = 40,
    }
} )



local dmg_events = {
    SPELL_DAMAGE = 1,
    SPELL_PERIODIC_DAMAGE = 1
}

local aura_removals = {
    SPELL_AURA_REMOVED = 1,
    SPELL_AURA_REMOVED_DOSE = 1
}

local dnd_damage_ids = {
    [43265] = "death_and_decay",
    [152280] = "defile"
}

local last_dnd_tick, dnd_spell = 0, "death_and_decay"

local sd_consumers = {
    death_coil = "doomed_bidding_magus_coil",
    epidemic = "doomed_bidding_magus_epi"
}

local db_casts = {}
local doomed_biddings = {}

local last_bb_summon = 0

-- 20250426: Decouple Death and Decay *buff* from dot.death_and_decay.ticking
spec:RegisterCombatLogEvent( function( _, subtype, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, spellID, spellName )
    if sourceGUID ~= state.GUID then return end

    if dnd_damage_ids[ spellID ] and dmg_events[ subtype ] then
        last_dnd_tick = GetTime()
        dnd_spell = dnd_damage_ids[ spellID ]
        return
    end

    if state.talent.doomed_bidding.enabled then
        if subtype == "SPELL_CAST_SUCCESS" then
            local consumer = class.abilities[ spellID ]
            if not consumer then return end
            consumer = consumer and consumer.key

            if sd_consumers[ consumer ] then
                db_casts[ GetTime() ] = consumer

            end
            return
        end

        if spellID == class.auras.sudden_doom.id and aura_removals[ subtype ] and #doomed_biddings > 0 then
            local now = GetTime()
            for time, consumer in pairs( db_casts ) do
                if now - time < 0.5 then
                    doomed_biddings[ now + 6 ] = sd_consumers[ consumer ]
                    db_casts[ time ] = nil
                end
            end
            return
        end
    end

    if subtype == "SPELL_SUMMON" and spellID == 434237 then
        last_bb_summon = GetTime()
        return
    end
end )


local dnd_model = setmetatable( {}, {
    __index = function( t, k )
        if k == "ticking" then
            -- Disabled
            -- if state.query_time - class.abilities.any_dnd.lastCast < 10 then return true end
            return debuff.death_and_decay.up

        elseif k == "remains" then
            return debuff.death_and_decay.remains

        end

        return false
    end
} )

spec:RegisterStateTable( "death_and_decay", dnd_model )
spec:RegisterStateTable( "defile", dnd_model )

-- Death Knight state table with runeforge support
local mt_runeforges = {
    __index = function( t, k )
        return false
    end,
}

spec:RegisterStateTable( "death_knight", setmetatable( {
    disable_aotd = false,
    delay = 6,
    runeforge = setmetatable( {}, mt_runeforges )
}, {
    __index = function( t, k )
        if k == "fwounded_targets" then return state.active_dot.festering_wound end
        if k == "disable_iqd_execute" then return state.settings.disable_iqd_execute and 1 or 0 end
        return 0
    end,
} ) )

spec:RegisterStateExpr( "dnd_ticking", function ()
    return death_and_decay.ticking
end )

spec:RegisterStateExpr( "dnd_remains", function ()
    return death_and_decay.remains
end )

spec:RegisterStateExpr( "spreading_wounds", function ()
    if talent.infected_claws.enabled and pet.ghoul.up then return false end -- Ghoul is dumping wounds for us, don't bother.
    return azerite.festermight.enabled and settings.cycle and settings.festermight_cycle and cooldown.death_and_decay.remains < 9 and active_dot.festering_wound < spell_targets.festering_strike
end )

spec:RegisterStateFunction( "time_to_wounds", function( x )
    if debuff.festering_wound.stack >= x then return 0 end
    return 3600
    --[[No timeable wounds mechanic in SL?
    if buff.unholy_frenzy.down then return 3600 end

    local deficit = x - debuff.festering_wound.stack
    local swing, speed = state.swings.mainhand, state.swings.mainhand_speed

    local last = swing + ( speed * floor( query_time - swing ) / swing )
    local fw = last + ( speed * deficit ) - query_time

    if fw > buff.unholy_frenzy.remains then return 3600 end
    return fw--]]
end )

spec:RegisterHook( "step", function ( time )
    if Hekili.ActiveDebug then Hekili:Debug( "Rune Regeneration Time: 1=%.2f, 2=%.2f, 3=%.2f, 4=%.2f, 5=%.2f, 6=%.2f\n", runes.time_to_1, runes.time_to_2, runes.time_to_3, runes.time_to_4, runes.time_to_5, runes.time_to_6 ) end
end )

local Glyphed = IsSpellKnownOrOverridesKnown

spec:RegisterGear({
    -- Mists of Pandaria Tier Sets
    tier16 = {
        items = { 99369, 99370, 99371, 99372, 99373 }, -- Death Knight T16
        auras = {
            death_shroud = {
                id = 144901,
                duration = 30,
                max_stack = 5
            }
        }
    },
    tier15 = {
        items = { 95339, 95340, 95341, 95342, 95343 }, -- Death Knight T15
        auras = {
            unholy_vigor = {
                id = 138547,
                duration = 15,
                max_stack = 1
            }
        }
    },
    tier14 = {
        items = { 84407, 84408, 84409, 84410, 84411 }, -- Death Knight T14
        auras = {
            shadow_clone = {
                id = 123556,
                duration = 8,
                max_stack = 1
            }
        }
    }
})

local wound_spender_set = false

local TriggerInflictionOfSorrow = setfenv( function ()
    applyBuff( "infliction_of_sorrow" )
end, state )

local ApplyFestermight = setfenv( function ( woundsPopped )
    -- Festermight doesn't exist in MoP, removing this function but keeping structure for compatibility
    return woundsPopped
end, state )

local PopWounds = setfenv( function ( attemptedPop, targetCount )
    targetCount = targetCount or 1
    local realPop = targetCount
    realPop = ApplyFestermight( removeDebuffStack( "target", "festering_wound", attemptedPop ) * targetCount )
    gain( realPop * 10, "runic_power" ) -- MoP gives 10 RP per rune spent, not 3 per wound

    -- Festering Scythe doesn't exist in MoP
end, state )

spec:RegisterHook( "TALENTS_UPDATED", function()
    class.abilityList.any_dnd = "|T136144:0|t |cff00ccff[Any " .. class.abilities.death_and_decay.name .. "]|r"
    local dnd = talent.defile.enabled and "defile" or "death_and_decay"

    class.abilities.any_dnd = class.abilities[ dnd ]
    rawset( cooldown, "any_dnd", nil )
    rawset( cooldown, "death_and_decay", nil )
    rawset( cooldown, "defile", nil )

    if dnd == "defile" then rawset( cooldown, "death_and_decay", cooldown.defile )
    else rawset( cooldown, "defile", cooldown.death_and_decay ) end
end )

-- MoP ghoul/pet summoning system - much simpler than later expansions
local ghoul_applicators = {
    army_of_the_dead = {
        army_ghoul = { 40 },
    },
    summon_gargoyle = {
        gargoyle = { 30 }
    }
}

spec:RegisterHook( "reset_precast", function ()
    if totem.gargoyle.remains > 0 then
        summonPet( "gargoyle", totem.gargoyle.remains )
    end

    local control_expires = action.control_undead.lastCast + 300
    if control_expires > now and pet.up and not pet.ghoul.up then
        summonPet( "controlled_undead", control_expires - now )
    end

    for spell, ghouls in pairs( ghoul_applicators ) do
        local cast_time = action[ spell ].lastCast

        for ghoul, info in pairs( ghouls ) do
            dismissPet( ghoul )

            if cast_time > 0 then
                local expires = cast_time + info[ 1 ]

                if expires > now then
                    summonPet( ghoul, expires - now )
                end
            end
        end
    end

    if buff.death_and_decay.up then
        local duration = buff.death_and_decay.duration
        if duration > 4 then
            if Hekili.ActiveDebug then Hekili:Debug( "Death and Decay buff extended by 4; %.2f to %.2f.", buff.death_and_decay.remains, buff.death_and_decay.remains + 4 ) end
            buff.death_and_decay.expires = buff.death_and_decay.expires + 4
        else
            if Hekili.ActiveDebug then Hekili:Debug( "Death and Decay buff with duration of %.2f not extended; %.2f remains.", duration, buff.death_and_decay.remains ) end
        end
    end

    -- Death and Decay tick time is 1s; if we haven't seen a tick in 2 seconds, it's not ticking.
    local last_dnd = action[ dnd_spell ].lastCast
    local dnd_expires = last_dnd + 10
    if now - last_dnd_tick < 2 and dnd_expires > now then
        applyDebuff( "target", "death_and_decay", dnd_expires - now )
        debuff.death_and_decay.duration = 10
        debuff.death_and_decay.applied = debuff.death_and_decay.expires - 10
    end

    -- MoP doesn't have vampiric strike or gift of the sanlayn

    -- In MoP, scourge strike is the primary wound spender
    class.abilities.wound_spender = class.abilities.scourge_strike
    cooldown.wound_spender = cooldown.scourge_strike

    if not wound_spender_set then
        class.abilityList.wound_spender = "|T237530:0|t |cff00ccff[Wound Spender]|r"
        wound_spender_set = true
    end

    -- MoP doesn't have infliction of sorrow

    if Hekili.ActiveDebug then Hekili:Debug( "Pet is %s.", pet.alive and "alive" or "dead" ) end

    -- MoP doesn't have festering scythe (spell ID 458128)
end )

-- MoP runeforges are different
local runeforges = {
    [3370] = "razorice",
    [3368] = "fallen_crusader",
    [3847] = "stoneskin_gargoyle"
}

local function ResetRuneforges()
    if not state.death_knight then
        state.death_knight = {}
    end
    if not state.death_knight.runeforge then
        state.death_knight.runeforge = {}
    end
    table.wipe( state.death_knight.runeforge )
end

local function UpdateRuneforge( slot, item )
    if ( slot == 16 or slot == 17 ) then
        if not state.death_knight then
            state.death_knight = {}
        end
        if not state.death_knight.runeforge then
            state.death_knight.runeforge = {}
        end
        
        local link = GetInventoryItemLink( "player", slot )
        local enchant = link:match( "item:%d+:(%d+)" )

        if enchant then
            enchant = tonumber( enchant )
            local name = runeforges[ enchant ]

            if name then
                state.death_knight.runeforge[ name ] = true

                if name == "razorice" and slot == 16 then
                    state.death_knight.runeforge.razorice_mh = true
                elseif name == "razorice" and slot == 17 then
                    state.death_knight.runeforge.razorice_oh = true
                end
            end
        end
    end
end

Hekili:RegisterGearHook( ResetRuneforges, UpdateRuneforge )

-- Abilities
spec:RegisterAbilities( {
    -- Talent: Surrounds you in an Anti-Magic Shell for $d, absorbing up to $<shield> magic ...
    antimagic_shell = {
        id = 48707,
        cast = 0,
        cooldown = 45,
        gcd = "off",

        startsCombat = false,

        toggle = function()
            if settings.dps_shell then return end
            return "defensives"
        end,

        handler = function ()
            applyBuff( "antimagic_shell" )
        end,
    },

    -- Talent: Places an Anti-Magic Zone that reduces spell damage taken by party or raid me...
    antimagic_zone = {
        id = 51052,
        cast = 0,
        cooldown = 120,
        gcd = "spell",

        talent = "antimagic_zone",
        startsCombat = false,

        toggle = "cooldowns",

        handler = function ()
            applyBuff( "antimagic_zone" )
        end,
    },

    -- Talent: Summons a legion of ghouls who swarms your enemies, fighting anything they ca...
    army_of_the_dead = {
        id = 42650,
        cast = 4,
        cooldown = 600,
        gcd = "spell",

        spend = 3,
        spendType = "runes",

        talent = "army_of_the_dead",
        startsCombat = false,
        texture = 237511,

        toggle = "cooldowns",

        handler = function ()
            applyBuff( "army_of_the_dead", 4 )
            summonPet( "army_ghoul", 40 )
        end,
    },

    -- Talent: Lifts the enemy target off the ground, crushing their throat with dark energy...
    asphyxiate = {
        id = 108194,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        talent = "asphyxiate",
        startsCombat = true,

        toggle = "interrupts",

        debuff = "casting",
        readyTime = state.timeToInterrupt,

        handler = function ()
            applyDebuff( "target", "asphyxiate" )
        end,
    },

    -- Talent: Convert health to available runes
    blood_tap = {
        id = 45529,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        talent = "blood_tap",
        startsCombat = false,

        usable = function () return buff.blood_charge.stack >= 5 end,

        handler = function ()
            removeBuff( "blood_charge", 5 )
            gain( 1, "runes" )
        end,
    },

    -- Empower Rune Weapon: Instantly activates all your runes and grants RP
    empower_rune_weapon = {
        id = 47568,
        cast = 0,
        cooldown = 300,
        gcd = "off",

        startsCombat = false,
        toggle = "cooldowns",

        handler = function ()
            gain( 6, "runes" )
            gain( 25, "runic_power" )
        end,
    },

    -- Festering Strike: A vicious strike that deals weapon damage and infects the target with a disease
    festering_strike = {
        id = 85948,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 2,
        spendType = "runes",

        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "festering_wound", nil, math.min( 6, debuff.festering_wound.stack + 2 ) )
            gain( 10, "runic_power" )
        end,
    },

    -- Outbreak: Instantly applies both Frost Fever and Blood Plague to the target
    outbreak = {
        id = 77575,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "frost_fever" )
            applyDebuff( "target", "blood_plague" )
        end,
    },

    -- Pestilence: Spreads diseases from the target to nearby enemies
    pestilence = {
        id = 50842,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        startsCombat = true,

        usable = function () return debuff.frost_fever.up or debuff.blood_plague.up end,

        handler = function ()
            if debuff.frost_fever.up then
                active_dot.frost_fever = min( active_enemies, active_dot.frost_fever + active_enemies - 1 )
            end
            if debuff.blood_plague.up then
                active_dot.blood_plague = min( active_enemies, active_dot.blood_plague + active_enemies - 1 )
            end
        end,
    },

    -- Talent: Extract diseases from target to gain runes
    plague_leech = {
        id = 123693,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        talent = "plague_leech",
        startsCombat = true,

        usable = function () return debuff.frost_fever.up or debuff.blood_plague.up end,

        handler = function ()
            local runes_gained = 0
            if debuff.frost_fever.up then
                removeDebuff( "target", "frost_fever" )
                runes_gained = runes_gained + 1
            end
            if debuff.blood_plague.up then
                removeDebuff( "target", "blood_plague" )
                runes_gained = runes_gained + 1
            end
            gain( runes_gained, "runes" )
        end,
    },

    -- Talent: Surrounds the caster with unholy energy that damages nearby enemies
    unholy_blight = {
        id = 115989,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        talent = "unholy_blight",
        startsCombat = true,

        handler = function ()
            applyBuff( "unholy_blight" )
            applyDebuff( "target", "frost_fever" )
            applyDebuff( "target", "blood_plague" )
        end,
    },

    -- Talent: Shackles the target $?a373930[and $373930s1 nearby enemy ][]with frozen chain...
    chains_of_ice = {
        id = 45524,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "chains_of_ice" )
        end,
    },

    -- Command the target to attack you.
    dark_command = {
        id = 56222,
        cast = 0,
        cooldown = 8,
        gcd = "off",

        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "dark_command" )
        end,
    },

    dark_simulacrum = {
        id = 77606,
        cast = 0,
        cooldown = 20,
        gcd = "off",

        pvptalent = "dark_simulacrum",
        startsCombat = false,
        texture = 135888,

        usable = function ()
            if not target.is_player then return false, "target is not a player" end
            return true
        end,
        handler = function ()
            applyDebuff( "target", "dark_simulacrum" )
        end,
    },

    -- Talent: Your $?s207313[abomination]?s58640[geist][ghoul] deals $344955s1 Shadow damag...
    dark_transformation = {
        id = 63560,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        talent = "dark_transformation",
        startsCombat = false,

        usable = function ()
            if Hekili.ActiveDebug then Hekili:Debug( "Pet is %s.", pet.alive and "alive" or "dead" ) end
            return pet.alive, "requires a living ghoul"
        end,
        handler = function ()
            applyBuff( "dark_transformation" )

            if talent.shadow_infusion.enabled then
                applyBuff( "dark_empowerment" )
            end
        end,
    },

    -- Corrupts the targeted ground, causing ${$52212m1*11} Shadow damage over $d to...
    death_and_decay = {
        id = 43265,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        startsCombat = true,
        notalent = "defile",

        usable = function () return ( settings.dnd_while_moving or not moving ), "cannot cast while moving" end,

        handler = function ()
            applyBuff( "death_and_decay" )
            applyDebuff( "target", "death_and_decay" )
        end,

        bind = { "defile", "any_dnd" },

        copy = "any_dnd"
    },

    -- Fires a blast of unholy energy at the target$?a377580[ and $377580s2 addition...
    death_coil = {
        id = 47541,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function ()
            return 40 - ( buff.sudden_doom.up and 40 or 0 )
        end,
        spendType = "runic_power",

        startsCombat = true,

        handler = function ()
            if buff.sudden_doom.up then
                removeBuff( "sudden_doom" )
            end
        end
    },

    -- Opens a gate which you can use to return to Ebon Hold.    Using a Death Gate ...
    death_gate = {
        id = 50977,
        cast = 4,
        cooldown = 60,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        startsCombat = false,

        handler = function ()
        end
    },

    -- Harnesses the energy that surrounds and binds all matter, drawing the target ...
    death_grip = {
        id = 49576,
        cast = 0,
        cooldown = 35,
        gcd = "off",
        icd = 0.5,

        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "death_grip" )
            setDistance( 5 )
        end
    },

    -- Talent: Create a death pact that heals you for $s1% of your maximum health, but absor...
    death_pact = {
        id = 48743,
        cast = 0,
        cooldown = 120,
        gcd = "off",

        talent = "death_pact",
        startsCombat = false,

        toggle = "defensives",

        usable = function() return pet.alive, "requires an undead pet" end,

        handler = function ()
            gain( health.max * 0.25, "health" )
            dismissPet( "ghoul" )
        end
    },

    -- Talent: Focuses dark power into a strike$?s137006[ with both weapons, that deals a to...
    death_strike = {
        id = 49998,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function()
            if buff.dark_succor.up then return 0 end
            return 40
        end,
        spendType = "runic_power",

        startsCombat = true,

        handler = function ()
            removeBuff( "dark_succor" )
        end
    },

    -- For $d, your movement speed is increased by $s1%, you cannot be slowed below ...
    deaths_advance = {
        id = 96268,
        cast = 0,
        cooldown = 120,
        gcd = "off",

        talent = "deaths_advance",
        startsCombat = false,

        handler = function ()
            applyBuff( "deaths_advance" )
        end
    },

    -- Defile the targeted ground, dealing Shadow damage over time. While you remain within your Defile, your Scourge Strike will hit multiple enemies near the target. If any enemies are standing in the Defile, it grows in size and deals increasing damage every sec.
    defile = {
        id = 152280,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        talent = "defile",
        startsCombat = true,

        usable = function () return ( settings.dnd_while_moving or not moving ), "cannot cast while moving" end,

        handler = function ()
            applyDebuff( "target", "defile" )
            applyBuff( "death_and_decay" )
            applyDebuff( "target", "death_and_decay" )
        end,

        bind = { "death_and_decay", "any_dnd" }
    },

    -- Strike an enemy for Frost damage and infect them with Frost Fever
    icy_touch = {
        id = 45477,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "frost_fever" )
        end,
    },

    -- Talent: Your blood freezes, granting immunity to Stun effects and reducing all damage...
    icebound_fortitude = {
        id = 48792,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        talent = "icebound_fortitude",
        startsCombat = false,

        toggle = "defensives",

        handler = function ()
            applyBuff( "icebound_fortitude" )
        end
    },

    -- Draw upon unholy energy to become Undead for $d, increasing Leech by $s1%$?a3...
    lichborne = {
        id = 49039,
        cast = 0,
        cooldown = 120,
        gcd = "off",

        talent = "lichborne",
        startsCombat = false,

        toggle = "defensives",

        handler = function ()
            applyBuff( "lichborne" )
        end
    },

    -- Talent: Smash the target's mind with cold, interrupting spellcasting and preventing a...
    mind_freeze = {
        id = 47528,
        cast = 0,
        cooldown = 15,
        gcd = "off",

        startsCombat = true,

        toggle = "interrupts",

        debuff = "casting",
        readyTime = state.timeToInterrupt,

        handler = function ()
            interrupt()
        end
    },

    -- A necrotic strike that deals weapon damage and applies a Necrotic Strike shield
    necrotic_strike = {
        id = 73975,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        talent = "necrotic_strike",
        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "necrotic_strike" )
        end,
    },

    -- Activates a freezing aura for $d that creates ice beneath your feet, allowing...
    path_of_frost = {
        id = 3714,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        startsCombat = false,

        handler = function ()
            applyBuff( "path_of_frost" )
        end
    },

    -- Strike an enemy for Unholy damage and infect them with Blood Plague
    plague_strike = {
        id = 45462,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "blood_plague" )
        end,
    },

    -- An unholy pact that prevents fatal damage, instead absorbing incoming healing
    purgatory = {
        id = 114556,
        cast = 0,
        cooldown = 240,
        gcd = "off",

        talent = "purgatory",
        startsCombat = false,

        toggle = "defensives",

        handler = function ()
            applyBuff( "purgatory" )
        end,
    },

    raise_ally = {
        id = 61999,
        cast = 0,
        cooldown = 600,
        gcd = "spell",

        spend = 30,
        spendType = "runic_power",

        startsCombat = false,
        texture = 136143,

        toggle = "cooldowns",

        handler = function ()
        end
    },

    -- Talent: Raises $?s207313[an abomination]?s58640[a geist][a ghoul] to fight by your si...
    raise_dead = {
        id = 46585,
        cast = 0,
        cooldown = function() return talent.raise_dead_2.enabled and 0 or 120 end,
        gcd = function() return talent.raise_dead_2.enabled and "spell" or "off" end,

        startsCombat = false,
        texture = 1100170,

        essential = true,
        nomounted = true,

        usable = function() return not pet.alive end,
        handler = function ()
            summonPet( "ghoul", talent.raise_dead_2.enabled and 3600 or 60 )
        end,
    },

    -- An unholy strike that deals Physical damage and Shadow damage
    scourge_strike = {
        id = 55090,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        startsCombat = true,
        
        handler = function ()
            -- Scourge Strike base functionality for MoP
        end,

        bind = { "wound_spender" }
    },

    -- Talent: Strike an enemy for Shadow damage and mark their soul. After 5 sec, if they are below 45% health, the mark will detonate for massive Shadow damage.
    soul_reaper = {
        id = 130736,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        talent = "soul_reaper",
        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "soul_reaper" )
        end
    },

    strangulate = {
        id = 47476,
        cast = 0,
        cooldown = 120,
        gcd = "off",

        startsCombat = false,
        texture = 136214,

        toggle = "interrupts",

        debuff = "casting",
        readyTime = state.timeToInterrupt,

        handler = function ()
            interrupt()
            applyDebuff( "target", "strangulate" )
        end
    },



    -- Talent: Summon a Gargoyle into the area to bombard the target for $61777d.    The Gar...
    summon_gargoyle = {
        id = 49206,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        startsCombat = true,

        toggle = "cooldowns",

        handler = function ()
            summonPet( "gargoyle", 30 )
        end,
    },



    -- The presence of the Unholy, increasing attack speed by 15% and movement speed by 15%.
    unholy_presence = {
        id = 48265,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        talent = "unholy_presence",
        startsCombat = false,

        handler = function ()
            applyBuff( "unholy_presence" )
        end,
    },

    -- Stub.
    any_dnd = {
        name = function() return "|T136144:0|t |cff00ccff[Any " .. ( class.abilities.death_and_decay and class.abilities.death_and_decay.name or "Death and Decay" ) .. "]|r" end,
        cast = 0,
        cooldown = 0,
        copy = "any_dnd_stub"
    },

    wound_spender = {
        name = "|T237530:0|t |cff00ccff[Wound Spender]|r",
        cast = 0,
        cooldown = 0,
        copy = "wound_spender_stub"
    }
} )

spec:RegisterRanges( "festering_strike", "mind_freeze", "death_coil" )

spec:RegisterOptions( {
    enabled = true,

    aoe = 2,

    nameplates = true,
    nameplateRange = 10,
    rangeFilter = false,

    damage = true,
    damageExpiration = 8,

    cycle = true,
    cycleDebuff = "festering_wound",

    potion = "tempered_potion",

    package = "Unholy",
} )

spec:RegisterSetting( "dnd_while_moving", true, {
    name = strformat( "Allow %s while moving", Hekili:GetSpellLinkWithTexture( spec.abilities.death_and_decay.id ) ),
    desc = strformat( "If checked, then allow recommending %s while the player is moving otherwise only recommend it if the player is standing still.", Hekili:GetSpellLinkWithTexture( spec.abilities.death_and_decay.id ) ),
    type = "toggle",
    width = "full",
} )

spec:RegisterSetting( "dps_shell", false, {
    name = strformat( "Use %s Offensively", Hekili:GetSpellLinkWithTexture( spec.abilities.antimagic_shell.id ) ),
    desc = strformat( "If checked, %s will not be on the Defensives toggle by default.", Hekili:GetSpellLinkWithTexture( spec.abilities.antimagic_shell.id ) ),
    type = "toggle",
    width = "full",
} )

spec:RegisterSetting( "pl_macro", nil, {
    name = function() 
        local plague_strike = spec.abilities and spec.abilities.plague_strike
        return plague_strike and strformat( "%s Macro", Hekili:GetSpellLinkWithTexture( plague_strike.id ) ) or "Plague Strike Macro"
    end,
    desc = function()
        local plague_strike = spec.abilities and spec.abilities.plague_strike
        local blood_plague = spec.auras and spec.auras.blood_plague
        if plague_strike and blood_plague then
            return strformat( "Using a mouseover macro makes it easier to apply %s and %s to other enemies without retargeting.",
                Hekili:GetSpellLinkWithTexture( plague_strike.id ), Hekili:GetSpellLinkWithTexture( blood_plague.id ) )
        else
            return "Using a mouseover macro makes it easier to apply Plague Strike and Blood Plague to other enemies without retargeting."
        end
    end,
    type = "input",
    width = "full",
    multiline = true,
    get = function() 
        local plague_strike = class.abilities and class.abilities.plague_strike
        return plague_strike and "#showtooltip\n/use [@mouseover,harm,nodead][] " .. plague_strike.name or "#showtooltip\n/use [@mouseover,harm,nodead][] Plague Strike"
    end,
    set = function() end,
} )

spec:RegisterSetting( "it_macro", nil, {
    name = strformat( "%s Macro", Hekili:GetSpellLinkWithTexture( spec.abilities.icy_touch.id ) ),
    desc = strformat( "Using a mouseover macro makes it easier to apply %s and %s to other enemies without retargeting.",
        Hekili:GetSpellLinkWithTexture( spec.abilities.icy_touch.id ), Hekili:GetSpellLinkWithTexture( spec.auras.frost_fever.id ) ),
    type = "input",
    width = "full",
    multiline = true,
    get = function() return "#showtooltip\n/use [@mouseover,harm,nodead][] " .. class.abilities.icy_touch.name end,
    set = function() end,
} )

spec:RegisterPack( "Unholy", 20250715, [[Hekili:S3ZEVnoUX)zjO48gVpCSKtYT31ydS9A7V2dfTfnTO)rrJSITCS6kl5QhBUCiqF2)XHuIIuA4djBVpUUOO7TRf1WzgoVj5O7CU7VF3TR9ZdU7p7o19QPxoB6eNRH)3D3M)0(G7UDV)Q37)a5Ve7VJ8N)J4Tjrpb)8trj(RHxplPiDf5rBZZ3N99xCXdH5BlUFYQKDxKfURiYppmjEvQ)MC4FV6I7U9(IWO8)y8D3Jp3xsG5(GvKF(kxcydxVoGn2GSv3Dlm23m9Y3mB63xU82KIOYL)Ta)9bPL)y5pw)q3RGhgU7hkxM9u8QFD5YnH)u5Y39x(DIJY5sYO(THz5HXpueMTLmG7t2rgBk8NVlD3tsJ2vcM3DBe5nZOCa)yVnK3NagY)8ptzQbX(3hfS(UFZD3Uknmpin0hOa)8TEVpo8HT5t83L55FFws69EeSFvqCE5YfLlNwUCu5Y0I4WvE7tEKqxlVPC5LtV7w)vaNK8FJZd35)a55zBdIIUlNWPuoL3xSzZKW4nrH032lzJhzkttECsX(gq(ysr8ApcxpEDqkaWzkb4zLlPWKrl(KxBDWk)NiGJI41p(d(72hMc4yEA47dKMn)4N8whVgMNl1J4zfWIV36KKD1tqUFeHvnb(PG1E3tKoiS9jvGOC5ZptwEcY9UpjUiBs(Jp66D5(v03KcXGSSG4vbaFiFBG39rjjR9(VfbbXt8Z925)teeMiYNjoxBsdI)5qy2GrNVnmnlVzgTKOz8RvjH0fSRus35(PpeKpzBGFu(2j7xrKkUzE5YzxvHr0Nseac8Yt8whgqfAUQzEiQJrEPuncyIU24cP9i93QewNxUCDafABcYGFl(bpQm1ek3KGJajuU8nLl3tqFFIAwym1WWeyQ(qaL4wLKeTo5rYVTpzLF0t7ZcMKgSZpmoJsLFWNmzKjN(CpcpGmnLlhZw0nslDKXFRg9uD0Yn6jLMzS59zOdzsZjpnjWJiHsqnT2kAHbzREIiVkrqiGVJHaLJvsIJkL)HWOaYsDCoX0cHyeLV5lmTgdFXHWsUQwtqbZts7Im9pTIakM4CgWhqm6ydYlzsDdDQikQvWTC58AdQALTiO)dRwpHGF4iwBRu4IuDfGwTfGpyRjKyYjpnjk6E)yYYFuL9xSjRTPbeDrzTyUAXEcncCjjNheANjx6fehSlmGrU83jyF4AYpVQHLX8(eWC7GJIAnQyeD0m3GLU2yBl8PMDu)YygMA7OHg6qA4E2V(V(dbVpmk8FtCXt8UqKW34dRlGQDrgzEU3pd(1KyI5wIDwYFMuUKiBqeI2ciA2Rj)02qcQr))KHTYhEVNskkxU1hmMXiiINOh93tgdxx6(I8jtM4t8N8IQNUNAdJZaGPI8JrpvU83xl1xU8FcYzzt6HB4ZPQIvA23xKsJXb88hK12ZLb1FW2QbLmW4otmHVObV1MIiWteJP5XyLK1q3YLVKRVzn8FlBKTfoiEfCyIi(HR9c(aqj(Rj8QgDBYl7yymlOMVa4BGTwh8rWMqq(vGrYerxqDnmgZ7YNa14ZRiM2rrzblhrp0I3QAHAmUvJV7JSvJpHKpMrkNPFsLiWxtCuhaIbeqbroKaqmWwVHYvRdUOFRBkOAvrAO0HUYOlrapjgVvRj52LeGfHx9ujBV1(OpbHSlL1iaJzEmJz40RQfLcA28E(zz(fr5I4agSRvQmJFUwh14mUzxdUHuytrDEQ6OaJyMKdbRDq24UipC17PEUHhYNT2JQfJqWUXA)03tIx0poBts6oA2f6ZwEDcGGPfaM6TpY)HIaks0q58q0XgAAajh3STaG7g(qLuY9ruLoj6w)ieLbqOOg6FC3jL4RolWtm7kSjwZOeN8UdRzQBy6jf53tsC(96ccVj7bRK1QcCfs(TVrsJRDZXJgAXlkC39vMDIciHFQpVYZ0iTQWOsh1gSCOKvwegHOkC7aZ1w6kB8awnDH72NM8HaGGQ9LwpVQkMHAlh9VscQ1lTHgo7qidvcQ683IsGWcBn6iGY7zw3zruzSUiUc1IPtTli6wRYTtn4WPct57Jxlj10ialCCxDvXqyJQfIYz1rol)GuFLni)qkf37Vb5BKkPOvARh9cnRQaW0F)HWn511WLW2I8Fsa7zwRSOqX1ErsYZjtsEsXQTcMRyJHx7Hz1AhueGPeVIqHf0YkWZSqrXNLu6jHx82PcQkyuJi1EskATUQK)yyCCLwhXHOhtCczUe8Vzf2kgG1mvM0mSNaDTmRtVTEzrlFwqwaBiICnw1bq0DexVmPBXl2Os1IHU)aNzwI6iUfcgtgW6YVQT0(NB9QJjYxoifTqJhtQQcXxh5VwxIZP1NASgpAM2xf9XujLFrF32KrwMoN(nUrZMVir59y)xSjQPk0Mz6GybhtbJl(OYxIbJgCB)UYzNjzUsDzTmWzLkNDhUtNYfzn7rbIwvwcwocG8U(ane4UyvxwJm5OkzfqA7HTeBjsIkgYrOsEkjJ5GzdKrPN4sR70bxjy4LnMJTHiCout)oUF8OWwL3rZoSjLwBp2amEkZTCkyQedcoC3LKsInlm)PUUzvenPyuozfeNue7ne6x69bmytAswU3gcJkTtboGNZcmbd9qQhXPViiKL3R)KwkewrVuuOn1bKyYNRGBzrlW0SbBwRzgj3r5D6nol4A1LBsXegOrDZX1uzvGDSNUhAwyX8OTJ9k3vaDbb32KHnBr0zg3NqbPmnBLO5Q43g7g0l9ssiLtUSrWbB3Du5U3CwHnww2r(TvaLUJyFaNzGN3OquHgcoPDgMUIr82SN34EdAEct2E8WeamP4WrwAOStMwZhBPhTWg3FVSoqQ(vjFdY8)pNim9r(ehB(z5mhJfrzTtiXI4I7mYM645mTNsN6KbxCsKbhQayJfwX9T8ZIt4JPjtBTnW0o4pSBC89RoS4oJ6JXMbx7uKT7V7M8ITKQ6ayOFNOngYboH0ojqvlPQ2Ty9rwWzgz0WPP1MR2AGPkR8wBs7cnDJQAxyr(khqsvhcPXTl8sXqbhaz62ygsv(D9JnyoZltCGEmzcjV1Zu1uukq803AkUEp2S5EMmOQ05o3qgDu3zMsPBqz1XG19GXaYKYhXN200mVa8Y6tuGn(FmjlocpdUwrKGKbxNFVP0xDmljoSUS5wfusAJQSrZFCvOAgnVBuZZC6IW24r8Se)(GCu76ChrpL6hb(vHqEwt0n3L21ZpzLEhysIeHr94L2WVZrJ5)kf26ieOJrk8Y28Dff9L(S0DpPTiF6L3fw0aavf(hjAJ1TuEOhEuOaySkuWUmskzGAsRg2qRvBdstkYyM53fssIlTvbSqyCo4SuUtYr2wNhA411KGk0rtT6QeTCq1BREONJhiPNjPGEOLUezswxKshxvonF7S6jSZy3NgMqq3NQ5y0vv2ZMK7oPXWx9ewlg1mMT(zE1JR2GomkT4f4EVLi(iM0prrnkjxGFQX5z1yC1YZD)yWZDhkp3Tfp3XcEUJ98C3HWZD1LneMC(zOR2sSDrcesqMB6yQKJmt7qOgOmUddFT)oF4iUFQK1LnPMvSBhXHZdeF6jpff0BdQJS0(S9ZQntPTXkjAhTdafdcQEBs6hi1hyLBtDpSJYpM8BR9G0L41HICy2EqTHhdpbV68Hu7t3C2poxHzpvv9eWSNIPB7Qq329OOBJaL(PBFmSP(PrwZ(z1MP8R629bn)Yx32fR2D162W75T1hU2DTpilA9DRv)3OAMeDAjCWCfRhoodaFSz6KpSrhuqJl4vVVFkM2iT3Nu7mcSrAZG0Q5qx2PybelT8PxirR6als4ALIgbE(HSrXPRrxvsLVJQ36h)cWVv5YFOsMjZQ600SdNFkozodVuVhUC)nSZwJvO5xRtlDudVoTF9q7uXL7NzwRnSztinh)I72ZtWJQI8Eco(odPmSRd2qvQRTdZJpjmEThrUj4NdezuiMUs2tmXhK38Q1Cq4Vfve0DhqH89PdZJvEpbonMXL(pblAnbIxomeJkANaomAowWIIlM29TR0TkZYTrusw2uRu8kxvrUEbrWbqCkN6NHjqBMPzARdxO6mrBLxWkRLQ3sEBO6BAcpuYqu9afngGxYzaxRqcPZHKETVwNse93Xynh67k3SD1l1kvah7Gg5oHBffsPcmVmxX5ok9TM29BRztLX0UhYAKmGQq5Wn6LnfCvO8aKPDam7XQw8HxxarPnRIvH5CzoUiCtSIAU3H1dgri0vcvHxcSEVo4d(eXizxATplrvx7B08rPruH5RPs7KR62RlNyLinlUDbd0WjZWlDp2bgXWYjhe(XuoM3Uw3HEk6O5YqjIzYwaD4IlUyhUeZQge(7RSB19vIYb6VZyVuG3lr0u2QeG2waBxoSiGCXZQhJpjgsyyuPgyrUtSKTLaKw66CcJY1EPjQTw06ysvp2BH)9kaenSvI1)ip2)WdA2FSw(NWYEvMJSPw7D28yp7sZS6uUABwZL3DbRotFcbrLUco4A5Ka2jykfUQZfQoJnM48MI0NM0S9pVIQFdI1s63IzMORquNBv95GrAv1VUEA7TZUBbhg15jnEiMBMuRnLHKx9inhDblHCNqa5hyjLxeytjbBCMBelAgcvKq9DZKlsqsTlifWJF5lsOMupurc9q(uksOAMfej4dHksOoHtkaRcSfUjXXpKVf9uBJE2F4Xbi(uXi3WQkc)LApTMErHR3hTwazE)NI1pSR2uO27aRZB)fLSTZBpe5xhvDQTJImQZBf8yrIRcQIuKh4QKUmP(8eRaDQwbahInbkdpRtAbYpMYM748CFreR4EoQVBR12j3eMgqnU(lEZKQP0HlLzbGpncGAN4gbc(iOsdQVIWiPv5uZYvA(ulowFj(4wR9FGM8rku4xAvUu1h62NW(VYBebjmDqQbDBiWyXoDnVFKffP8fn7vWSPmmr544qMl)1Bb7ztpePxP3gP6kJ6(OoVVfYQZyBiJ6etoxi79D78HZoPY9QZU6HJDECndBfYrMirORxiAdwENgP0U6uJe3FWo7Ott5bf7cwif7xrcDC7XkKpKzqkk0OfKVWUl1zNcO0V2u4gm9t1SWxwfpNnN8LFxXMwIS5J7UTidQ6YgVhwTUARrC10)8eVeF9QZ8pttk1inQFDn2f9sukyuZ6FXdQ6oL0DPgWjTTZ5bIwUdgTOOK6a5ga(mC0rOzzayL6O6ggw5mmSQgD02qD)yIr092sDP3osRhSMBimvQ9OHQHi7)QQBMj5ZYHFKFueBOoCKriE11jgrbvGkA6()aHO29KAc5CnbWYt)T7f(u(D12dJjJQv78MEsZVIBsEaYwat(666VFe5LS(YaWlv7QtnV8mLSRJjssrp1(EWudPyxfB2IMELHGZ8x)Ke5Ea9BorTg7cjuoXiIFsRzM9Gr0P081FpEawVAFUMMXJw96RATJa2O2BRsSXO58bGqaYq(P9PbKa0U3V75KGfqjnsAb0nx9vRQta4naNEgRR2nR(FiiYLp70qGDGyALTOMhgMnr517QzFJADyabuQxhBczuYvhk52tuYTbLuCQhmTzKnexDLjKIsXgEfgBDdugcGijcHzydil8H4aUYj9qY)K8EAkmEGifWVURY6qUxYoaMVYakQAyyik7cKttwwXPqWw2URE2Uo5bmrhDSD3EY2DnX21JCi8tmuu1WmW275jPOR0(ws4mEvuupL31U17d8mb0ipyaXmzHOVNjaBrmhp23WUgu6d6oB(NRTwfJkrpl8n1g9BWpqwndyon7AHqlXIOyyZhgKApXJ7PReHZQ2KR4RlSpTeTtdQNlmUMxyAFPOSBHX1eJ6iVWyC(gYcJ9QlDxyAN0ypxyQV4xTsZwRAJXLUg6c)sH1iq25I4kvMofW)CtRhxy4M8oMAJg2IZjDSQlh3dFKiWdKO1pIgRKIZz9HksMmcJ(qe9SjkQUs)TXucYz606YNoMw3Uwqa1IbgJWXkgr7ysvtMogzeo9Gr4GWiCvYi06lPZbiYsvdfxnY(OHG9CrH4oKgKGDlEGoAlNLa(N8(2Oy)sdV6iC2WNdTiT(1G(mqCl(mJ4QxPog9)nfN)BD1GRYrQM2q4qo864RzFA)wsIJtd(Jhj(kNQRHQPvUb15(gspLZ09OaB1uOsUOgM6tlO7a63DkTfO8BzNjUUP7lHcjEP(wjfqQ(kqO4kVPsdjx4O0(1w10X4(b)1w1KifqfT6vRAQZZX6MmNzi3bSO(f1NQoh4NB6uimYWPTHlB17JaJ2OT18UlyNVjb5EJsLJSxiFyhgiROfK3T6Q6lKDTfy3aoUqwHFk6AgTqqfcjNazGxvVhD6LegOjSbkRRvVQkPCKdILPfGpgTJm92vCnxZHwvi7lf7kU)cYUcgT85KDfm87Zb7kUFXyxbtVQh2vCnAx5u0Y94p)R9bpZt55woRJ(AVYYu45Dj(pd7vwNI(GNvkCFT509vfU(t5F5RW9zyZPRxaaZXOcayF7OBKHjqUks9oIlhR(ktmYqKqCKW421rMYVBQA(wNb2r1Y6a60wRlBHNrGnsBj6SAoufeVU2ux9LaqtLpL7Ckwurx5(TXiX6Bl(HShRQYw064q(Q0RCVwawxNcUYo6VIFmpr6fFAkPxRogN18JBQt7qjPuTkRPD2yvh1AKDT9MRXxcuvXb1KTs65mBijT2d09Cjxak2Lc1N73p2DgVZmVjNChQN6EJNMTirwa1IV8smsxkcRtFp3JxQMr2hCN1MrTmEToxLbEBBut0(n(eTsbs4JRoU8TfF9SKS5YXJgIs8ZwIHpVLvDnbfF4Xv0Ikv)vfxTXEB3G2Aa35tNS6tQGSe4dPu7NykQQV)mkcqceWu5cU(zDJUvynHDRKWSbB9gKlR(w3ARWREeBNT4obL(IwRXUPjFCxkOvkGQnnQlA08k2x7stFO0vF0bqMlnciQvCmWHvXXS9tzEFByzQPbQklXrqg80)S7u3RMEPlXP(J(PW14Lq9)9TejSWD7tsjAQeZOLlFrvSYzVGyCj4)wesVz)zjWg26xKNqm0c)arXl(HGSjL)4FkeSan77HR)FmzYOpUgktKRohbM5jcpnVZJp35NgBbqBNCccGrgYje4NiW(XbNVubyD0V415Xs4QAGAexrhYje4NiW(XbNV6Okt0cNpUa3cWEawlU(OYFpPa3cWEaAEF7rfxpPa3iyhMGML48WaUrWomwHL48WaUrWomwHL48WaUrWIu1pD8cHXyfwpuWBeWifHuh)OV49qbpbWL)isaHInX0xCKckCiYdFCIf6Kei7X11)jf4wa2dW1Kkh)onFLTWqsHN9PaCdtK6KcCla7biVQkSexn8vx181psGByc8NuGBbypaTjl8C1dC9KcCJGDyQbwIZdd4gb7WyfwIZdd4gb7WyfwIZdd4Qc8G3zqEXrjQd5lHPcvnHhBv0g6Uf4itH2bBLxDx9urNhBjq7bvyyWw507KX20oHs9Hc8PP9qSh4yDVc85qXiTCQ2NMSI1FY2NPlXevJ7ipnGyMx)b)xx(1U8RoIPEW46JIQ2jupJdDi2dCRyC6gPLtLDc0Qh3rEA0Q381L)bU8RoyQEW46JbN3(XEL67mhUyVQw1jg8Nma)PhV7XcCFKOAnHj7dyOugj84ycqvDaphDUYtv5iDK638n8FcP7(mF6ZpxbxnD1hBNaDTZN5thtMkl5yu27rNtCQzehB(axMXzQ5eY6vTGBjtE0H)PdYFoG5MfDhKP)2ZOztdU9qHaHypUMg0pb2Rsyd)9OZjo1mIJnFOrOXrBHeQNxebtDvEujupO6zQbxhMY6Pg(2azGGPNHR6pplky1ThJTyUTWxvnH0aAOXzHzXI9Z2bfhCO40xOyEbYIOep6W3giBEbcFm2I52c)ElaCCw6oiXOoU4otzqFAm5JBt75NptHDjIvw1q7CDwe(gn326XV8CNjx9kfQLKNI8UqZae)jnnbqaUVscTao7BATEn(BCMoD84XlegjwmQi8xveGJrcWrjb4OHaCAraUseqTK0N5scx85RKWfwjj0La(SrsOIaeS(6Eum(OckwAiS8h)J09VcEx47yb7yzxUe6O(W2tb96(KnHq)X8x9RkxUnpFF23FXfpeMVT4EYcWUlYc3ver5WRs93Kd)7vxaFBKcZZUiFBWJ(PpsgDy8fVJc7)A1D5(pbZWf0JBo7J2Hh72lmbaq5pcZ2)ypd9x7NtivakLlVnC3pqi53TpnmQCPRlCtBDVI2UqV0D9QRNndikgzKnHVDCVA(fn99F8N3(wm(A5U8)Cx8xRw441q30AEl96xtfrM3SOikZ1exSUmM7ZS6IoRUkMvDbJ3NzTrh71j7Nt7VQDOB1Z0lDAuk7UFgDEkwfvFP70x30QufMv0cB)6vjXRdP5Myd(1Avsc7A9m0MbFpyKUgzK6wYezvDlWDNN2dgPIDiaHrQd)Aj4PGrQe36dJu0(CBwPRif60tHH(GeUhcsC80nbFyTNEhXPF6KReqGEuGYrnCSJAzySeUwx1HJ3c6HYlvxrNrnl8NgE5rQswhl5Y6o6I1kghsOZkJCEiboFyzqHu7JJwSZTcDwzouhwkuijVF0cEUvSZYjrzJ4LI(g0rqkR7tQfnKX2fZLjgHOrjy7UW41EBsdc(5aXFwMie(QLwH4vOT8DuFUJAqiC9O1bIf6aXEExBwgeZKm4jW8WSsvDE5U5QrkUvOWlmI)MYTJH63EXvQrZM7EQmwEUgSzbFTuGibZcTTkpE05k7VZMq6BCNos(AzxnGrTxgF(5QjjnHygn2lpPyf8bXwflRyp)nqVJTlMF5BWVY2elCs3xA1llf71XY7C)HL59OThJg(fE37GGlca8Mzt1OGuDdWBRwFE9kOiJK7Du8hhDgol)5Nr(Y4twjhdoayGjChjy4peaxG(6Bk9OZBTK6YNu4XqCSRd(GpzXHApLojb3m75NrU88p)mZ0AX61e8ADsYokA1y(PrGx1AxTqGGjZUSq)ykQ7rsEp3AZJ0PtZhrX6zw982U3BuBt5vQ5UVQMZtSBg)ZHKNrNY8THPz5VKZxKOOX8xABr8dmMd7fQ1j36NEFi8i6QdHnpcHVpMvhIFWpkQC57QkncTWfIuy7VhHnC4kxbzVM9vmKWld3W1oKB07MbikWotf0a8(V5Vk0pscx9txb9AI8KucZmhGGOshXKfv00v8vylWBksFcg(5u2uZVXdH4vZwmxsEUsVEeIqorfGRR2QjQ98ZC7ekAVAlUguhrBRuJW7CS3mxnsZuc704lgH3vW0dPwoxN7osXh0wc9dD(TrYgJ1aBP1JG0SGuamcRh8F7lP1dmKEyRh4q64SEGbBX1dA7(jZ7)uS(HDv6u0xSYRFDqYGdDotMzYEh8Mvg8f(foX1T3Zun42Gw9li5cWNy2gAbtrEGfgQ0JZB)mwkX5T9vAaEJdDv35Tigm3xq8fcCSoqNWuaBM1blSyUuCmn)mH(fH7MW0aQQEJsm)N(cshgdN77IMgaDORLkbTKbv)hObZKcnkTURXZDgDUcfA0j9kiQHYL3sIWa2vLFOI1l5gEFc83WKNCgDORIuCfV1ZnA20fZv(8kOuT8zTCWSP9DbN)gDsqzu7Fw4DuSedjkq3SOSGYL34xUCBAWM5VOENQE8XhN8yYJBH2sjD7Q2hefn3z60RNEbvd9nHXBkGUn0lw8xznBQ)y1pCZf(lkx(42WOEa5l)o3PxFbBb6n1lqVyX)x1FJbZWSYLf7FD5sFYF5Xai6s4Vz7C4(TxD939Dx0KN6lw8o(FNndWLrJTHz2c0RNDfHLaYfVrwU4fl(TKFSC5Fx6xRiKn2pbwI12coRy0evWYLXj5LvnjpIcjvyPrtmm(djVNO)9teVVXepJG2rDAUePbVAPdf6QigIhHzX(M5UUnvyOL(BDojT3bsEDI70Z(6ONyq9b8lEMEGzT(UZBhRMsotfPOXQKAOP)LW49Mmr(kNPl4JbBT3tEzN7YORVOzAn1cLOb3tvvsL)RBFknCZ)MUZ1nfjvO2FcvJwOCEJH7v6oif5Hekili:nRvBpUTns4Fllkoh7EjowAxNnPyTbAVEan7DxqrDUVkjAjABHvw0NevxShm0V9oKuVqsrklTXO31IKytY5foZ8mZqA6549vVnrik27lUlCxU4ENLZDDDCDx6TH(YjS3MtOWNq7HpKIoc)DXHYakoNYM4LeckIXGCsrwimP3MTfXj0pN6TTdxx46(XfFWBdQGEGK5TzZXIDzXp5T5qCuewqbop0BZxpeNxgW(dQmOs6LbKDW3dPXK0YGK4Ckm9oswzWVGFkojEoOozKDXjGs8DLb)mgrb98FKgV)a9hkd(3PhijVu(y5JFhm7VMHdjh3IOLb)iNJ5LpkyD(8t1Z9xx9Eqnt9j78FooLIZEB8Uv3STy3U5QJpV4KzYl4c1hgkhNgInVOmuCo2pcJImppk74lmzrpuVkXE4NX7qfjg2banhJtJ83LHX)xS8WOuA8r0(4q)8d4KK3gHGVHx5SG9FSDxiHKerEoDU2kNNHpIItZxTqMDfGEhtXhFllUyfnlo9jm1HXhUrkcL9KpndLMdUPJigvYwkBmWDemyBcHaB0ISxgdr4SCC2tXP7hbrOSquk2NsYYWPugHzfPG55e5zC2d3VyYa5Zjc7tJqWvXqBtybYm6OOeqdMRm(CCkABcoAY0icD(Umso1Fh(3HqZkh3d3E(mBkHb7ucAFbUDUznXuqOikhWAO0iaLGHOR)fkfIrocIuwRAdA5GIty689hifjZzl53vc6ecZpbJdpiP)Yd3Q(tTRKtSU1MD(80MixsbDBgg9uZ0oZMjRo1ZZuLP30rC04qwKX5Z3OlUQzMnPruMCE1s11GjihIWFcZny2KRmvXHVaXBfcRMn1rMGiwop)qsCIw856pT48zE8wEbltRFeHCeuvGuf67UFKNgsXN4deDsKjKIY2dU9dyuc9W8tH03D73pTZG)LQrG0jm0JFumE2dRUD5GSIRVRoW8hj)DJj6e2WTvBzrWNpofFmgNVEL7KUXtv2TortnU3P8LVYfcQeFYzcykXcUmVwT9BJ(M11haWhaCeIEXSwjWURCQ3DBabNGF3x5MQYGFJq7y8bvWx8nFwTprgtebBsa3DrcZ5c0x4B6YIhUBOA2CfozogQ3KDmBPDULhcTvSxg5uz6yENAR4eUnFLZm78zh0UcgkVSxItvU5j8GGvU2jwe(qrNKYE1mwtQl(oumC4bgPZZPqNlRxTS2DVOhRMcY9ci1byLAbxQHJnaRE0fR2Q1le2Q(i2EkO7hmvvMytrl1g7HK8aQy8kJ6m5noGaA8Jt3vKZya33kb0U6bn25C3Es16e5ITOQZr8roT(S0C(pdj4fy26W2jcKsL3NfglLtUBgbiPeRKhefb9IdD9YyL1SW92mtJxwD6g)7RuM2BXqNHQvxgBPeDUPHf1N2AUoNomQN60kY6v2kqNDV5zUgb3c(9Thsl4ZidK928mklf8u5SJCcD9gd0NrRow5BuGjVPmid)FkIZWqJX5KJSEKlOeW6Zga2FP7X5ZlF8FgNct5WpXzEXjg)ylqONatn47EtdzUwjtn4OLIBTsHEA8wAUZknn(W2fV0(oPjeRD1Fy0BG7FfBGpokD6tJA1olg3YT7PnymDS7GvJTLiXUh2q0oJoEK8ossc5zwsiimndLxgaReghoXnWIyGCkBz18I1zyzW2cA96sjCyqrQYQJIylocrrBHtj(dqHGG3bKjbXRgYygk(mQ7ZQb1QUwpABckwjhdiua1FTWLT1ogcC00QT7OAtKoeqOwzIHafTbUSdh7nnKDmPjiGD0OP9TD0Oj8IDWOv8IDx8)hJxmJkUy8FK4kaVwyaPBnCiGaT7iCi(yLg5gKFU9IMgKpw(wLguE36RdAqzCvUhhjkSdMBUdhPvpUsQoVsqSJDuS0f5OT()gjfAGLVAcmlNL5Ii638NY99aHYuYGf27)gfw7MFCjXCUupfkzV)tpbJ9QVxoLsZV8W1kPITe12HKA)QjdPcRPSe2bL6)Ik)pXj1jL)JF(yTMENQmyMzVn5NWHEFXDPR3g(GSF1nObi4F(c)NWR6yxE)K3MWSywRZiVnwVN5GjG61ZHV5lO)dGxg8a4taLGRQEBABkYJck6RtNSD48(f2TVEHz4G7TsPf8ZKYDCtE1uAaDzXdlDPvfsykldwbGMwUP2bhJdFqryDr0Ac8ERcu6O0LbRHQZlkdoFMf3A6sa03GHv79pkRosMfvT4tw1cB3sa3py5Mca1fSsl1Llqntwolg2wgIBUFbxm3ujPo3JqReuNIlg7GljxPqaC9t678ylX3BfHH2qb5agEL7BOFyDVxSz)Hn9cnL2rUIOKPq2pPiwbSr8BRl((S(cITJlBnvUAMk3wgQFfanGWRDigFjYUtlXC2H1Jdn9bR85s3CphcVOpBU9mbv281AHNQm0Kn)JddPTMH0STLVyQHEUVF1Ir90tNOkrRdFaqefLSNCk2)za4rm3zLL2rXFdbS2YjAhAFvZjAhxFLZjwDc3MSH1eiDuvTsq6wGAk0oTQrmNLx9sT2kEUmEBeVxgt53epqQ6xctRWBhza5WlozkpNcRD7WA3rW6lKfZcHArCShDt)PYggZAEmoJOlM2W3bjd13Ut)j0gedfpINbLvZEZ1t72)Pwwmw93(7hwP8RIOUq2ma2R)MDAzu7PPgwcmtpLN6T40lVfm0iU(MSPxeRpZh(sD4lvYKiRzxi)4uEUq7hxGPa3y9idCbpMIusi46TYfYS2J21zd3w62XE)s23nT8R5(R48YEIJRZHmCg5HECSNVOZDfXp0nel9984idt)(MrLUojUF9bi9)TlhH)DTs)asx3gxPTN8raeRFfoIs9UYjlg7jzRdlNkxhUTZ(2Xen23Z7CsckotVuq95JDSNn0(oZ85H1pDnRWU9SzM4UKdq7jqjU)eFrbv2nOWyU9KC6m)HbZB1d0X7NP5618698DJVRm(lNol(KysZV(5M2J0QyuFtBAORBLxQunb1vPCPi63SM6AR)FV)i]] )