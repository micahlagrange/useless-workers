-- Free play jobs. Every morphi in the wilds has three of the four jobs:
-- a MAIN job it does whenever there is work of that kind, a NEUTRAL job it
-- falls back to (the player may leave it empty), and a DISLIKED job it does
-- only when nothing else is left. The player sets main and neutral; the
-- disliked job is a personality trait, dealt once and never changed.
--
-- The deal (Micah's decisions 7 and 8): the starting morphis get UNIQUE main
-- jobs and UNIQUE disliked jobs (as unique as the four jobs allow, for a band
-- of more than four), neutral jobs that may repeat, three different jobs
-- each, and the draw is redone until every one of the four jobs is somebody's
-- main, neutral or disliked job. Immigrants are dealt by the same rules,
-- favouring jobs nobody in the band has yet. The deal rolls its own random
-- stream (JobSets.rngFor), never the game's, so a seed's map, growth and
-- morphis' timing are what they were before jobs were dealt.
--
-- Arcade levels and the retired survival levels keep one fixed job each
-- (Worker's role) and never come here.
require('src.constants')
local Rng = require('src.rng')

local JobSets = {}

JobSets.JOBS = { ROLE_FORAGER, ROLE_LUMBERJACK, ROLE_MINER, ROLE_BUILDER }
JobSets.SLOTS = { 'main', 'neutral', 'disliked' }
-- how many times the start is redealt before giving up on covering all four
-- (only a band of one cannot cover them: a morphi has three jobs)
JobSets.MAX_DEALS = 200

-- The job queue types a job takes, in the order given. A lumberjack chops
-- and builds beds (woodwork); a builder builds floors, bins, bridges and beds.
function JobSets.jobTypes(job)
    local info = ROLES[job]
    if not info then return {} end
    local types = { info.jobType }
    for _, extra in ipairs(info.alsoTakes or {}) do types[#types + 1] = extra end
    return types
end

-- The job a queue type belongs to first (for whose action time a node or a
-- site takes): forage to forager, chop to lumberjack, mine to miner, build
-- and woodwork to builder.
JobSets.JOB_FOR_TYPE = { forage = ROLE_FORAGER, chop = ROLE_LUMBERJACK, mine = ROLE_MINER, build = ROLE_BUILDER, woodwork = ROLE_BUILDER }

-- A random stream of its own for the deal, from the game's seed.
function JobSets.rngFor(seedNumber)
    return Rng.new((tonumber(seedNumber) or 1) * 7 + 12345)
end

local function copy(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

local function contains(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

local function without(list, drop)
    local out = {}
    for _, v in ipairs(list) do
        if not contains(drop, v) then out[#out + 1] = v end
    end
    return out
end

-- Every one of the four jobs is somebody's main, neutral or disliked job.
function JobSets.covered(sets)
    local seen = {}
    for _, s in ipairs(sets) do
        if s.main then seen[s.main] = true end
        if s.neutral then seen[s.neutral] = true end
        if s.disliked then seen[s.disliked] = true end
    end
    for _, job in ipairs(JobSets.JOBS) do
        if not seen[job] then return false, job end
    end
    return true
end

-- The jobs of the four nobody in the band has in any slot.
function JobSets.missing(sets)
    local seen = {}
    for _, s in ipairs(sets) do
        for _, slot in ipairs(JobSets.SLOTS) do
            if s[slot] then seen[s[slot]] = true end
        end
    end
    local out = {}
    for _, job in ipairs(JobSets.JOBS) do
        if not seen[job] then out[#out + 1] = job end
    end
    return out
end

-- n jobs, each block of four a fresh shuffle of the four: unique for a band
-- of up to four, and no job more than once per four beyond that.
local function dealUnique(rng, n)
    local out = {}
    while #out < n do
        local deck = rng:shuffle(copy(JobSets.JOBS))
        for _, job in ipairs(deck) do
            if #out < n then out[#out + 1] = job end
        end
    end
    return out
end

-- One try at the start: mains and dislikes unique, a morphi's own three
-- different. Returns nil when a morphi's main and dislike collide.
local function tryStart(rng, n)
    local mains = dealUnique(rng, n)
    local dislikes = dealUnique(rng, n)
    local sets = {}
    for i = 1, n do
        if mains[i] == dislikes[i] then return nil end
        local left = without(JobSets.JOBS, { mains[i], dislikes[i] })
        sets[i] = { main = mains[i], neutral = left[rng:int(1, #left)], disliked = dislikes[i] }
    end
    return sets
end

-- The starting band's jobs: a list of n {main, neutral, disliked}. Redealt
-- until all four jobs are covered (a band of one never can be; it keeps its
-- last deal). Works for any n >= 1.
function JobSets.dealStart(rng, n)
    local last
    for _ = 1, JobSets.MAX_DEALS do
        local sets = tryStart(rng, n)
        if sets then
            last = sets
            if JobSets.covered(sets) then return sets end
        end
    end
    return last or {}
end

local function pick(rng, list)
    if #list == 0 then return nil end
    return list[rng:int(1, #list)]
end

-- An immigrant's jobs, given the band it joins (a list of job sets). Its
-- main is a job nobody has yet if there is one, else one nobody has as main
-- (mains stay unique while the band is small enough), else any. Its neutral
-- also goes to a job the band lacks when one is left. Its disliked job is
-- one nobody else dislikes if it can be, and never one the band lacks.
function JobSets.dealOne(rng, band)
    band = band or {}
    local missing = JobSets.missing(band)
    local mains, dislikes = {}, {}
    for _, s in ipairs(band) do
        if s.main then mains[#mains + 1] = s.main end
        if s.disliked then dislikes[#dislikes + 1] = s.disliked end
    end
    local main = pick(rng, missing) or pick(rng, without(JobSets.JOBS, mains)) or pick(rng, JobSets.JOBS)
    local rest = without(JobSets.JOBS, { main })
    -- the dislike: not a job the band lacks, and not one somebody already dislikes, if it can
    local disliked = pick(rng, without(rest, missing))
    local fresh = without(without(rest, missing), dislikes)
    if #fresh > 0 then disliked = pick(rng, fresh) end
    disliked = disliked or pick(rng, rest)
    local left = without(rest, { disliked })
    local neutral = pick(rng, without(left, without(left, missing))) or pick(rng, left)
    return { main = main, neutral = neutral, disliked = disliked }
end

-- Can this morphi's slot take this job? main and neutral only; never the
-- disliked job; the main never empty. Returns ok and, if not, why.
function JobSets.canSet(set, slot, job)
    if slot == 'disliked' then return false, 'the disliked job is part of who it is' end
    if slot ~= 'main' and slot ~= 'neutral' then return false, 'no such job slot' end
    if job == nil then
        if slot == 'main' then return false, 'a morphi always has a main job' end
        return true
    end
    if not ROLES[job] or not contains(JobSets.JOBS, job) then return false, 'no such job' end
    if job == set.disliked then return false, 'it dislikes ' .. ROLES[job].label:lower() .. ' work' end
    if slot == 'neutral' and job == set.main then return false, 'that is already its main job' end
    return true
end

-- Set a slot. Making the neutral job the main one swaps the two, so the old
-- main becomes the fallback. Returns ok, why.
function JobSets.set(set, slot, job)
    local ok, why = JobSets.canSet(set, slot, job)
    if not ok then return false, why end
    if slot == 'main' then
        if job == set.main then return true end
        if job == set.neutral then set.neutral = set.main end
        set.main = job
    else
        set.neutral = job
    end
    return true
end

-- The jobs in the order a morphi tries them: main, neutral (if set), disliked.
function JobSets.order(set)
    local out = { { job = set.main, slot = 'main' } }
    if set.neutral then out[#out + 1] = { job = set.neutral, slot = 'neutral' } end
    if set.disliked then out[#out + 1] = { job = set.disliked, slot = 'disliked' } end
    return out
end

function JobSets.label(job)
    return job and ROLES[job] and ROLES[job].label:lower() or 'none'
end

return JobSets
