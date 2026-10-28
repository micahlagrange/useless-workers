-- Skill stats. Every morphi starts at 0 in each and earns points by doing
-- the work the skill helps with:
--   scrappy  digging, building and hunting
--   sightful gathering (grass, berries) and nurturing babies
--   grit     shaking trees for sticks
local Skills = {}

Skills.NAMES = { 'scrappy', 'sightful', 'grit' }

Skills.GAIN_DIG      = 0.05  -- per tile dug
Skills.GAIN_BUILD    = 0.1   -- per structure built
Skills.GAIN_HUNT     = 0.1   -- per critter caught
Skills.GAIN_GATHER   = 0.05  -- per grass or berry picked
Skills.GAIN_NURTURE  = 0.05  -- per visit to a baby
Skills.GAIN_SHAKE    = 0.05  -- per tree shaken
Skills.HUNT_BASE     = 0.30  -- hunting chance with no scrappy
Skills.HUNT_PER_POINT = 0.05 -- added per scrappy point

function Skills.new()
    return { scrappy = 0, sightful = 0, grit = 0 }
end

function Skills.add(skills, name, amount)
    skills[name] = (skills[name] or 0) + amount
end

-- Chance a hunt catches its critter, 0..1.
function Skills.huntChance(skills)
    return math.min(1, Skills.HUNT_BASE + Skills.HUNT_PER_POINT * ((skills and skills.scrappy) or 0))
end

-- How many pieces one pick of grass or berries (sightful) or one shake of a
-- tree (grit) yields: 1, plus one for each whole point.
function Skills.yield(points)
    return 1 + math.floor((points or 0) + 1e-9)
end

return Skills
