-- A morphi. In free play it has three jobs (src/jobsets.lua): a main job it
-- does whenever there is work of that kind, a neutral one it falls back to,
-- and a disliked one it does only when nothing else is left; the player sets
-- the first two. Arcade (and the retired survival levels) give it one job,
-- its role. It gets hungry, takes jobs off the shared queue, complains when
-- it cannot reach them,
-- carries a work item in slot 1 and a personal snack in slot 2, and takes a
-- break in the break room after enough work. Nothing interrupts a job:
-- eating, fetching a snack and taking a break are all chosen while idle.
--
-- Arcade (world.arcade): no hunger, morale or breaks. Every morphi wants to
-- eat once, any food, but only once the level's needs are met; picky levels
-- eat only out of a bin. Building is the builder's job alone.
require('src.constants')
local Util = require('src.util')
local Pathfinder = require('src.pathfinder')
local JobSets = require('src.jobsets')

local Worker = {}
Worker.__index = Worker
local nextId = 1

function Worker.new(world, jobs, scoring, rng, opts)
    opts = opts or {}
    local self = setmetatable({}, Worker)
    self.id = nextId
    nextId = nextId + 1
    self.world, self.jobs, self.scoring, self.rng = world, jobs, scoring, rng
    -- free play: main, neutral and disliked jobs (role mirrors the main one);
    -- elsewhere one job, the role. doing is the job of the task in hand.
    self.stage = opts.stage -- 'egg', 'baby', or nil for a grown-up
    self.nest = opts.nest   -- an egg's or a baby's nest: {x, y}
    self.parents = opts.parents
    if self.stage == 'egg' then
        self.role = 'baby'
        self.hatchTimer = EGG_HATCH_SECONDS
    end
    if self.stage == 'baby' then
        self.role = 'baby'
        self.age = 0
        self.needs = { fun = 100, clean = 100, sleep = 100 }
        self.careSum, self.careTime = 0, 0
    elseif opts.jobs then
        self.jobSet = { main = opts.jobs.main, neutral = opts.jobs.neutral, disliked = opts.jobs.disliked }
        self.role = self.jobSet.main
    else
        self.role = opts.role or ROLE_FORAGER
    end
    self.roleInfo = ROLES[self.role]
    self.doing = nil
    self.band = opts.band -- the game's list of morphis, for 'nobody has builder set'
    self.sheet = opts.sheet or self.roleInfo.sheets[1]
    self.species = MORPHI_SHEET_NAMES[self.sheet] or self.sheet
    self.diet = opts.diet or MORPHI_DIET[self.sheet] or FOOD_KINDS[1]
    -- free play: tastes instead of one food (loves the diet, hates one, eats
    -- the rest), boredom, and gold to trade for happy thoughts
    self.wilds = opts.wilds == true
    self.hates = self.wilds and MORPHI_HATES[self.sheet] or nil
    self.name = opts.name or ('Morphi ' .. self.id)
    local c = Util.tileCenter(opts.x or 1, opts.y or 1)
    self.x, self.y = c.x, c.y
    self.arcade = world.arcade == true
    self.ate = false
    self.hunger = self.arcade and HUNGER_MAX or (opts.hunger or HUNGER_MAX)
    self.drain = opts.drain or 0.7
    self.speed = opts.speed or WORKER_SPEED
    self.state = 'idle'
    self.stateTimer = 0
    self.decideTimer = rng and rng:random() * DECIDE_INTERVAL or 0
    self.path, self.pathIndex = nil, 1
    self.goal = nil
    self.job = nil
    self.targetNode = nil
    self.targetSite = nil
    self.targetArea = nil
    self.areaTilesDone = 0
    self.mineLimit = opts.mineLimit or MINE_TILES_PER_TRIP
    self.targetItem = nil
    self.targetTile = nil
    self.slots = {}           -- [SLOT_WORK] = {kind, food}, [SLOT_PERSONAL] = {kind, food}
    self.eatingSlot = nil
    self.workTime = 0         -- accumulated work since the last break
    self.breakAfter = self.arcade and math.huge or BREAK_AFTER_SECONDS
    self.wantsBreak = false
    self.restSpot = nil
    self.breaksTaken = 0
    self.walkTime = 0
    self.icks = {}
    self.facing = 'right'
    self.moving = false
    self.bubble = nil
    self.clock = 0
    self.animTime = 0
    self.alive = true
    self.delivered = 0
    self.complaintCount = 0
    self.morale = MORALE_MAX
    self.warnedLowMorale = false
    self.onComplain = opts.onComplain
    self.onEvent = opts.onEvent
    return self
end

-- Inventory -------------------------------------------------------------

function Worker:carrying()
    return self.slots[SLOT_WORK]
end

-- Would I eat this food? Arcade: anything. Free play: anything but the
-- food I hate, and even that when starving. Survival levels: my own only.
function Worker:willEat(food)
    if self.arcade then return true end
    if self.wilds then return food ~= self.hates or self.hunger < HUNGER_STARVING end
    return food == self.diet
end

-- How much I like it: 'loved', 'fine' or 'hated'.
function Worker:taste(food)
    if not self.wilds or food == self.diet then return 'loved' end
    if food == self.hates then return 'hated' end
    return 'fine'
end

-- Something I would actually eat.
function Worker:edible(item)
    return item ~= nil and (item.kind == ITEM_FOOD or item.kind == CARGO_FOOD) and self:willEat(item.food)
end

-- Does this bush grow something I eat?
function Worker:eatsFrom(node)
    return node.kind == NODE_BUSH and self:willEat(node.food)
end

-- A meal: hunger by taste, and a better or worse mood for it.
function Worker:mealOf(food)
    local taste = self:taste(food)
    self.hunger = math.min(HUNGER_MAX, self.hunger + (self.wilds and FOOD_VALUE[taste] or FRUIT_HUNGER_VALUE))
    if self.wilds and self.morale then
        if taste == 'loved' then self.morale = math.min(MORALE_MAX, self.morale + MORALE_LOVED_MEAL)
        elseif taste == 'hated' then self.morale = math.max(0, self.morale - MORALE_HATED_MEAL); self:say('yuck', 1.2) end
    end
end

function Worker:snackInPocket()
    return self:edible(self.slots[SLOT_PERSONAL])
end

function Worker:hasFoodInSlot(i)
    local s = self.slots[i]
    return s ~= nil and s.kind == ITEM_FOOD and self:willEat(s.food)
end

-- Arcade: still waiting for my one meal?
function Worker:wantsMeal()
    return self.arcade and not self.ate
end

-- 'satiated', 'fed', 'hungry' or 'starving', for the HUD.
function Worker:hungerStatus()
    if self.hunger <= 0 then return 'starving' end
    if self.hunger < HUNGER_EAT_THRESHOLD then return 'hungry' end
    if self.hunger > HUNGER_SATIATED then return 'satiated' end
    return 'fed'
end

function Worker:tile()
    return Util.worldToTile(self.x, self.y)
end

function Worker:isWorking()
    return self.alive and self.state ~= 'quitting' and self.stage == nil
end

-- Babies ---------------------------------------------------------------------

function Worker:isBaby()
    return self.stage == 'baby'
end

function Worker:isEgg()
    return self.stage == 'egg'
end

-- Out of the egg: a baby now, in the same nest.
function Worker:hatch()
    self.stage = 'baby'
    self.age = 0
    self.needs = { fun = 100, clean = 100, sleep = 100 }
    self.careSum, self.careTime = 0, 0
    self.hunger = HUNGER_MAX
    self:emit('hatched')
end

-- How well it is looked after right now, 0-100: the mean of its needs.
function Worker:careNow()
    local n = self.needs
    return (self.hunger + n.fun + n.clean + n.sleep) / 4
end

-- Its care score so far: the mean of careNow over its babyhood.
function Worker:careScore()
    if (self.careTime or 0) <= 0 then return self:careNow() end
    return self.careSum / self.careTime
end

-- Gone: a little flower marks the spot (world.graves).
function Worker:die(cause)
    if self.trade then self:endTrade(false) end
    if self.play then self:endPlay(false) end
    self:dropJob()
    self.slots = {}
    self.scoring:addQuit()
    self.alive = false
    self.state = 'gone'
    local t = self:tile()
    self.world.graves = self.world.graves or {}
    self.world.graves[#self.world.graves + 1] = { x = t.x, y = t.y, name = self.name }
    self:emit('died', { cause = cause, stage = self.stage or 'grown-up' })
end

function Worker:updateBaby(dt)
    self.age = self.age + dt
    -- danger: an empty belly, or every need empty, for long enough
    local n = self.needs
    if self.hunger <= 0 then self.emptyTime = (self.emptyTime or 0) + dt else self.emptyTime = 0 end
    if self.hunger <= 0 and n.fun <= 0 and n.clean <= 0 and n.sleep <= 0 then
        self.neglectTime = (self.neglectTime or 0) + dt
    else
        self.neglectTime = 0
    end
    if self.emptyTime >= BABY_STARVE_SECONDS then self:die('hunger') return end
    if self.neglectTime >= BABY_NEGLECT_SECONDS then self:die('neglect') return end
    if self.emptyTime >= BABY_STARVE_SECONDS / 2 and not self.warnedHungry then
        self.warnedHungry = true
        self:emit('babyWarning', 'hungry')
    elseif self.emptyTime == 0 then
        self.warnedHungry = nil
    end
    if self.neglectTime >= BABY_NEGLECT_SECONDS / 2 and not self.warnedNeglect then
        self.warnedNeglect = true
        self:emit('babyWarning', 'neglected')
    elseif self.neglectTime == 0 then
        self.warnedNeglect = nil
    end
    local n = self.needs
    for k, rate in pairs(BABY_NEED_DRAIN) do n[k] = math.max(0, n[k] - rate * dt) end
    if self.state == 'breaking' then n.sleep = math.min(100, n.sleep + BABY_NAP_RATE * dt) end
    self.careSum = self.careSum + self:careNow() * dt
    self.careTime = self.careTime + dt
    if self.age >= BABY_SECONDS then self:emit('grewUp') end
end

-- Grown up: dealt its jobs (by the game), its mood from how it was cared for.
function Worker:growUp(jobs)
    self.morale = math.max(BABY_MORALE_MIN, math.min(MORALE_MAX, self:careScore()))
    self.stage = nil
    self.needs = nil
    self.jobSet = { main = jobs.main, neutral = jobs.neutral, disliked = jobs.disliked }
    self.role = self.jobSet.main
    self.roleInfo = ROLES[self.role]
    self.workTime = 0
end

-- A baby's needs in a line for the strip: 'fun 80 clean 70 sleep 90, grows up in 4:10'.
function Worker:babySummary()
    local n = self.needs
    local left = math.max(0, math.ceil(BABY_SECONDS - self.age))
    return string.format('fun %d clean %d sleep %d, grows up in %d:%02d', math.floor(n.fun + 0.5), math.floor(n.clean + 0.5), math.floor(n.sleep + 0.5), math.floor(left / 60), left % 60)
end

-- Somebody in the bunch has caretaker as main or neutral job.
function Worker:hasCaretaker()
    for _, w in ipairs(self.band or {}) do
        if w.jobSet and w:isWorking() and (w.jobSet.main == ROLE_CARETAKER or w.jobSet.neutral == ROLE_CARETAKER) then return true end
    end
    return false
end

-- Tamagotchi mode: the player tends this baby, on the colony's real numbers.
-- tendInfo(action, world) says what a button does, what it costs, what the
-- colony has to pay with and whether it can be done now; tend() does it and
-- returns a line saying what happened.

local FOOD_NAME = function(food) return (FOOD_WORDS and FOOD_WORDS[food]) or food end
Worker.foodName = FOOD_NAME

-- The stored meals this baby will eat, best liked first: { {food, n, taste} }
function Worker:mealsFor(world)
    local by = {}
    for _, item in ipairs(world.items) do
        if item.kind == ITEM_FOOD and self:willEat(item.food) then by[item.food] = (by[item.food] or 0) + 1 end
    end
    local out = {}
    for food, n in pairs(by) do out[#out + 1] = { food = food, n = n, taste = self:taste(food) } end
    local rank = { loved = 1, fine = 2, hated = 3 }
    table.sort(out, function(a, b)
        if rank[a.taste] ~= rank[b.taste] then return rank[a.taste] < rank[b.taste] end
        return a.food < b.food
    end)
    return out
end

-- How a baby takes to a food put down in front of it: 'love' (it knows
-- and loves it: jumps right on it), 'hate' (knows it and hates it: yuck),
-- 'ok' (knows it, it will do), or 'curious' (never seen it: creeps up,
-- sniffs, nibbles, and then finds out). knownFoods remembers what it tried.
function Worker:reactTo(food)
    self.knownFoods = self.knownFoods or {}
    local taste = self:taste(food)
    if not self.knownFoods[food] then return 'curious', taste end
    if taste == 'loved' then return 'love', taste end
    if taste == 'hated' then return 'hate', taste end
    return 'ok', taste
end

-- It tried the food: it knows it now, and eats it unless it hates it (and
-- is not starving). Returns true if it ate.
function Worker:tryFood(food)
    self.knownFoods = self.knownFoods or {}
    self.knownFoods[food] = true
    if self:taste(food) == 'hated' and self.hunger >= HUNGER_STARVING then return false end
    self:mealOf(food)
    return true
end

-- What this baby thinks of a food, for the food bag: a word, and the
-- tummy a meal of it gives ('loves it' +70, 'likes it' +35, 'hates it',
-- 'never tried').
function Worker:opinionOf(food)
    self.knownFoods = self.knownFoods or {}
    local taste = self:taste(food)
    if not self.knownFoods[food] then return 'never tried', FOOD_VALUE[taste], taste end
    if taste == 'loved' then return 'loves it', FOOD_VALUE.loved, taste end
    if taste == 'hated' then return 'hates it', 0, taste end
    return 'likes it', FOOD_VALUE.fine, taste
end

-- Every food in the stashes, kind by kind: { {food, n} }, most first.
function Worker.pantry(world)
    local by, out = {}, {}
    for _, item in ipairs(world.items) do
        if item.kind == ITEM_FOOD then by[item.food] = (by[item.food] or 0) + 1 end
    end
    for food, n in pairs(by) do out[#out + 1] = { food = food, n = n } end
    table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.food < b.food end)
    return out
end

function Worker:tendInfo(action, world)
    local n = self.needs
    if action == 'feed' then
        local meals = self:mealsFor(world)
        local total = 0
        local parts = {}
        for _, m in ipairs(meals) do
            total = total + m.n
            parts[#parts + 1] = m.n .. ' ' .. FOOD_NAME(m.food)
        end
        local best = meals[1]
        local gain = best and FOOD_VALUE[best.taste] or FOOD_VALUE.fine
        return {
            ok = total > 0,
            does = '+' .. gain .. ' tummy' .. (best and best.taste == 'loved' and ', loved: a happier baby' or ''),
            cost = '1 stored meal',
            have = total > 0 and ('stashes: ' .. table.concat(parts, ', ')) or 'none in the stashes',
        }
    elseif action == 'clean' then
        local grass = world.stock.grass or 0
        return {
            ok = grass >= 1,
            does = '+' .. TAMA_CLEAN .. ' clean',
            cost = '1 grass',
            have = grass >= 1 and ('you have ' .. grass .. ' grass') or 'no grass yet',
        }
    elseif action == 'play' then
        return {
            ok = true,
            does = '+' .. TAMA_FUN .. ' fun, -' .. TAMA_PLAY_COST .. ' clean & sleep',
            cost = 'free',
            have = 'tiring and messy',
        }
    elseif action == 'nap' then
        local sleepy = n.sleep < TAMA_SLEEPY_BELOW
        return {
            ok = sleepy,
            does = 'sleep to 100, if not woken',
            cost = TAMA_NAP_SECONDS .. ' s asleep',
            have = sleepy and 'ready for a nap' or 'not sleepy yet',
        }
    end
    return { ok = false, does = '', cost = '', have = '' }
end

function Worker:tend(action, world)
    local n = self.needs
    if action == 'feed' then
        -- the best-liked meal leaves the stash; the baby eats it on screen
        -- (or not), see Worker:reactTo and tryFood
        local best = self:mealsFor(world)[1]
        if not best then return nil end
        for _, item in ipairs(world.items) do
            if item.kind == ITEM_FOOD and item.food == best.food then
                world:takeItem(item.x, item.y, item)
                return 'Put some ' .. FOOD_NAME(best.food) .. ' down for ' .. self.name .. '.', best.food
            end
        end
        return nil
    elseif action == 'clean' then
        if (world.stock.grass or 0) < 1 then return nil end
        local before = n.clean
        world.stock.grass = world.stock.grass - 1
        n.clean = math.min(100, n.clean + TAMA_CLEAN)
        self:say('squeaky', 1.5)
        return string.format('A wash with a tuft of grass: clean %d -> %d. %d grass left.', math.floor(before + 0.5), math.floor(n.clean + 0.5), world.stock.grass)
    elseif action == 'play' then
        local f = n.fun
        n.fun = math.min(100, n.fun + TAMA_FUN)
        n.clean = math.max(0, n.clean - TAMA_PLAY_COST)
        n.sleep = math.max(0, n.sleep - TAMA_PLAY_COST)
        self:say('hee hee', 1.5)
        return string.format('Played together: fun %d -> %d, a little grubbier and sleepier.', math.floor(f + 0.5), math.floor(n.fun + 0.5))
    end
    return nil
end

-- How a need reads, in a word: 'full', 'peckish', 'hungry', 'starving'...
local NEED_WORDS = {
    hunger = { 'starving', 'hungry', 'peckish', 'full' },
    fun = { 'miserable', 'bored', 'content', 'delighted' },
    clean = { 'filthy', 'grubby', 'fine', 'spotless' },
    sleep = { 'exhausted', 'sleepy', 'awake', 'rested' },
}
function Worker.needWord(kind, v)
    local w = NEED_WORDS[kind]
    if v < 15 then return w[1] elseif v < 45 then return w[2] elseif v < 75 then return w[3] end
    return w[4]
end

-- A caretaker's visit: play, clean, feed when hungry, tuck in when sleepy.
function Worker:careFor(b)
    local n = b.needs
    n.fun = math.min(100, n.fun + CARE_FUN)
    local stock = self.world.stock
    if (stock.grass or 0) >= 1 then
        stock.grass = stock.grass - 1
        n.clean = math.min(100, n.clean + CARE_CLEAN)
    else
        n.clean = math.min(100, n.clean + CARE_CLEAN / 3)
    end
    if b.hunger < CARE_FEED_BELOW then
        for _, item in ipairs(self.world.items) do
            if item.kind == ITEM_FOOD and b:willEat(item.food) then
                self.world:takeItem(item.x, item.y, item)
                b:mealOf(item.food)
                break
            end
        end
    end
    if n.sleep < CARE_TUCK_BELOW then b.tuckedIn = true end
    b:say('<3', 1.5)
    self:emit('cared', b)
end

function Worker:releaseBaby()
    if self.targetBaby and self.targetBaby.caredBy == self then self.targetBaby.caredBy = nil end
    self.targetBaby = nil
end

-- A baby's day: eat when hungry, nap when sleepy, toddle about near home.
function Worker:decideBaby()
    local cared = self:hasCaretaker()
    if self.hunger < (cared and BABY_SELF_FEED_BELOW or HUNGER_EAT_THRESHOLD) then
        if self:eatSomething() then return end
    end
    if self.needs.sleep < BABY_NAP_BELOW or self.tuckedIn then
        self.tuckedIn = nil
        if self:startBreak() then return end
    end
    local home = self.nest or self.world.breakroom
    local t = self:tile()
    local cx, cy = home and home.x or t.x, home and home.y or t.y
    local target = self.rng and self.world:randomNearbyPassable(self.rng, cx, cy, BABY_WANDER)
    if target then
        local path = self:pathTo(target.x, target.y)
        if path then
            self:setPath(path, 'wander')
            return
        end
    end
    self.decideTimer = DECIDE_INTERVAL * 3
end

function Worker:title()
    return self.name .. ' the ' .. self.species .. ' (' .. self.roleInfo.label:lower() .. ')'
end

-- Jobs ----------------------------------------------------------------------

-- The jobs this morphi tries, in order: { {job, slot}, ... }. Free play:
-- main, neutral, disliked. Elsewhere: its one role.
function Worker:jobOrder()
    if self.jobSet then return JobSets.order(self.jobSet) end
    return { { job = self.role, slot = 'main' } }
end

-- Free play: set the main or neutral job (nil empties the neutral one). The
-- disliked job never changes. Whatever is in hand is finished first: the
-- next job it picks follows the new order. Returns ok, why.
function Worker:setJob(slot, job)
    if not self.jobSet then return false, 'this morphi has one fixed job' end
    local ok, why = JobSets.set(self.jobSet, slot, job)
    if ok then
        self.role = self.jobSet.main
        self.roleInfo = ROLES[self.role]
    end
    return ok, why
end

-- The job of the task in hand (or the main job when there is none).
function Worker:doingInfo()
    return ROLES[self.doing or self.role] or self.roleInfo
end

-- Which slot a job is in for this morphi: 'main', 'neutral', 'disliked' or nil.
function Worker:slotOf(job)
    if not self.jobSet then return job == self.role and 'main' or nil end
    for _, slot in ipairs(JobSets.SLOTS) do
        if self.jobSet[slot] == job then return slot end
    end
    return nil
end

function Worker:emit(name, data)
    if self.onEvent then self.onEvent(self, name, data) end
end

function Worker:say(text, ttl)
    self.bubble = { text = text, ttl = ttl or 2.5 }
end

function Worker:isIcked(x, y)
    local expires = self.icks[Util.key(x, y)]
    return expires ~= nil and expires > self.clock
end

function Worker:ick(x, y)
    self.icks[Util.key(x, y)] = self.clock + ICK_SECONDS
end

function Worker:recentlyReported(node)
    return node.complainedAt ~= nil and (self.clock - node.complainedAt) < COMPLAINT_COOLDOWN
end

function Worker:face(dx, dy)
    if dx < 0 then
        self.facing = 'left'
    elseif dx > 0 then
        self.facing = 'right'
    end
end

function Worker:releaseNode()
    if self.targetNode and self.targetNode.claimedBy == self then
        self.targetNode.claimedBy = nil
    end
    self.targetNode = nil
end

function Worker:releaseSite()
    if self.targetSite and self.targetSite.claimedBy == self then
        self.targetSite.claimedBy = nil
    end
    self.targetSite = nil
end

-- Let go of a mine area; whatever is left goes back on the queue.
function Worker:releaseArea()
    local area = self.targetArea
    if not area then return end
    if area.claimedBy == self then area.claimedBy = nil end
    self.targetArea = nil
    if #area.sites > 0 then self.jobs:postArea(area) end
end

function Worker:releaseItem()
    if self.targetItem and self.targetItem.claimedBy == self then
        self.targetItem.claimedBy = nil
    end
    self.targetItem = nil
end

function Worker:releaseTile()
    if self.targetTile then
        self.world:releaseReservations(self)
        self.targetTile = nil
    end
end

-- Put the current job back on the queue and forget the path.
function Worker:dropJob()
    if self.job then
        local job = self.job
        self.job = nil
        if (job.node and job.node.ready) or (job.site and not job.site.done) then self.jobs:post(job) end
    end
    self:releaseNode()
    self:releaseSite()
    self:releaseBaby()
    self:releaseArea()
    self:releaseItem()
    if self.restSpot then
        self.world:releaseRestSpot(self)
        self.restSpot = nil
    end
    self:releaseTile()
    self.path = nil
    self.goal = nil
end

-- Trades ------------------------------------------------------------------

function Worker:atCamp()
    local br = self.world.breakroom
    if not br then return false end
    local t = self:tile()
    return math.abs(t.x - br.x) <= 3 and math.abs(t.y - br.y) <= 3
end

-- Offer a trade and wait at camp for somebody to take it up.
function Worker:offerTrade()
    if self.world.openTrade or self.world.stock.gold < 1 then return false end
    self.trade = { a = self, timer = TRADE_WAIT_SECONDS }
    self.world.openTrade = self.trade
    self.state = 'trading'
    self:say('swap?', 3)
    return true
end

-- A stored meal for this morphi, claimed: its loved food if there is any (a
-- gift, as far as the trade goes), else anything it will eat.
local function claimMeal(world, w)
    local br = world.breakroom
    local item = world:nearestStoredItem(ITEM_FOOD, br.x, br.y, w.diet)
    local gift = item ~= nil
    item = item or world:nearestStoredItem(ITEM_FOOD, br.x, br.y, function(food) return w:willEat(food) end)
    if item then item.claimedBy = w end
    return item, gift
end

-- Take up the trade waiting at camp: only with the gold to stake and a meal
-- for each of them in storage.
function Worker:joinTrade()
    local tr = self.world.openTrade
    if not tr or tr.a == self or not tr.a.alive or tr.b or self.world.stock.gold < 1 then return false end
    local mealA, giftA = claimMeal(self.world, tr.a)
    local mealB, giftB = claimMeal(self.world, self)
    if not (mealA and mealB) then
        if mealA then mealA.claimedBy = nil end
        if mealB then mealB.claimedBy = nil end
        return false
    end
    self.world.openTrade = nil
    self.world.stock.gold = self.world.stock.gold - 1
    self:dropJob()
    tr.b, tr.timer, tr.chat = self, TRADE_SECONDS, 0
    tr.meals = { [tr.a] = mealA, [self] = mealB }
    tr.gifts = (giftA and 1 or 0) + (giftB and 1 or 0)
    tr.lines = 0
    self.trade = tr
    self.state = 'trading'
    self.moving = false
    -- turn to face each other
    self:face(tr.a.x - self.x, 0)
    tr.a:face(self.x - tr.a.x, 0)
    self:say('swap!', 2)
    return true
end

-- Run the trade (called on the one who offered it): wait for a taker, then
-- chat, eat together halfway, and close the deal.
function Worker:updateTrade(dt)
    local tr = self.trade
    tr.timer = tr.timer - dt
    if not tr.b then
        if tr.timer <= 0 then self:endTrade(false) end
        return
    end
    local a, b = tr.a, tr.b
    if not (a.alive and b.alive) then self:endTrade(false) return end
    local elapsed = TRADE_SECONDS - tr.timer
    -- a line every few seconds, turn about, for anyone watching
    tr.chat = tr.chat - dt
    if tr.chat <= 0 and tr.timer > 2 then
        tr.lines = tr.lines + 1
        local speaker = (tr.lines % 2 == 1) and a or b
        local i = ((tr.lines - 1) + (a.id or 0)) % #TRADE_CHAT + 1
        speaker:say(TRADE_CHAT[i], 2.6)
        tr.chat = 3.4
    end
    -- halfway: they eat together
    if not tr.ate and elapsed >= TRADE_SECONDS / 2 then
        tr.ate = true
        for _, w in ipairs({ a, b }) do
            local item = tr.meals[w]
            if item and self.world:tileHasItem(item.x, item.y, item) then
                self.world:takeItem(item.x, item.y, item)
                w:mealOf(item.food)
            end
        end
        a:say(tr.gifts > 0 and 'brought your fave!' or 'snack time', 2.4)
        tr.chat = 3
    end
    if tr.timer <= 0 then self:endTrade(true) end
end

-- A deal: happy thoughts for both, more for every gift. Otherwise the gold
-- goes back and the meals are let go.
function Worker:endTrade(deal)
    local tr = self.trade
    if not tr then return end
    if self.world.openTrade == tr then self.world.openTrade = nil end
    if tr.b and not deal then self.world.stock.gold = self.world.stock.gold + 1 end
    for _, item in pairs(tr.meals or {}) do
        if item.claimedBy then item.claimedBy = nil end
    end
    local who = { tr.a }
    if tr.b then who[2] = tr.b end
    for _, w in ipairs(who) do
        if deal then
            w.morale = math.min(MORALE_MAX, w.morale + MORALE_TRADE_BASE + MORALE_GIFT * tr.gifts)
            w:say('yay!', 2.5)
        end
        w.trade = nil
        if w.state == 'trading' then w.state = 'idle'; w.decideTimer = 0 end
    end
    if tr.b and deal then tr.a:emit('trade', { partner = tr.b, gifts = tr.gifts }) end
end

-- Play --------------------------------------------------------------------
-- Fun together, free play only: once a season a morphi may play with
-- another. One offers at camp and waits (world.openPlay, apart from the
-- trade's offer), the next free one walks over and joins, and they talk a
-- script out of PLAY_CHAT, a line each, turn about. No gold, no meals. At
-- the end both cheer up by MORALE_PLAY. The one who offered (play.a) runs it.

-- Fun comes at random: each morphi is due about once a season (a gap of
-- half to one and a half PLAY_MEAN_SECONDS, drawn with the game's rng), and
-- takes it at the next natural break at the home nest. Not required.
function Worker:nextFunGap()
    local r = self.rng and self.rng:random() or 0.5
    return PLAY_MEAN_SECONDS * (0.5 + r)
end

function Worker:hasPlayChance()
    if not self.wilds then return false end
    if not self.funAt then self.funAt = self.clock + self:nextFunGap() end
    return self.clock >= self.funAt
end

-- Free to play: here, fed enough to last the talk, hands empty, and not
-- busy with a trade or another play.
function Worker:freeToPlay()
    return self.wilds and self:isWorking() and self.trade == nil and self.play == nil
        and self.hunger >= PLAY_MIN_HUNGER and not self:carrying()
end

function Worker:isPlaying()
    return self.play ~= nil and (self.state == 'playing' or (self.state == 'walking' and self.goal == 'play'))
end

-- Offer to play and wait at camp for somebody to join.
function Worker:offerPlay()
    if self.world.openPlay or not (self:hasPlayChance() and self:freeToPlay() and self:atCamp()) then return false end
    if self.playRetryAt and self.clock < self.playRetryAt then return false end
    self:dropJob()
    self.play = { a = self, wait = PLAY_WAIT_SECONDS }
    self.world.openPlay = self.play
    self.state = 'playing'
    self.moving = false
    self:say('play?', 3)
    return true
end

-- Join the offer waiting at camp, if it is near enough to walk to.
function Worker:joinPlay()
    local pl = self.world.openPlay
    if not pl or pl.a == self or pl.b or not pl.a:isWorking() then return false end
    if not (self:hasPlayChance() and self:freeToPlay()) then return false end
    local at, here = pl.a:tile(), self:tile()
    if Util.manhattan(at.x, at.y, here.x, here.y) > PLAY_JOIN_TILES then return false end
    self.world.openPlay = nil
    Worker.beginPlay(pl.a, self, pl)
    return true
end

-- A tile next to (x, y) to stand on and talk: a free one if there is one
-- (not the pantry, a bed or somebody's rest spot), else any open one.
local function besideSpot(world, x, y)
    local spot = world:freeNeighbour(x, y)
    if spot then return spot end
    for _, c in ipairs({ { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 } }) do
        if world:isPassable(c[1], c[2]) then return { x = c[1], y = c[2] } end
    end
    return nil
end

-- a and b play. Spends this season's chance for both, unless dev (the
-- tester's PLAY NOW) says otherwise. A talk is picked with the game's rng,
-- and b walks to stand beside a; the talk starts when b gets there.
function Worker.beginPlay(a, b, pl, dev, category, convo)
    pl = pl or { a = a }
    for _, w in ipairs({ a, b }) do
        -- a site being worked on is let go, so cancelling it refunds as usual
        if w.targetSite and w.targetSite.claimedBy == w then w.targetSite.working = nil end
        w:dropJob()
        w.eatingSlot = nil
        w.play = pl
        w.state = 'playing'
        w.moving = false
        w.idleSince = nil
        if not dev then w.funAt = w.clock + w:nextFunGap() end
    end
    pl.b = b
    pl.dev = dev
    local rng = a.rng or b.rng
    pl.category = category or (rng and rng:pick(PLAY_CATEGORIES) or PLAY_CATEGORIES[1])
    local list = PLAY_CHAT[pl.category]
    pl.convo = convo or (rng and rng:pick(list) or list[1])
    pl.lines, pl.chat, pl.started = 0, 0, false
    pl.walk = PLAY_WALK_SECONDS
    b:say('sure!', 2)
    local at, bt = a:tile(), b:tile()
    local beside = math.abs(at.x - bt.x) <= 1 and math.abs(at.y - bt.y) <= 1 and not (at.x == bt.x and at.y == bt.y)
    local spot = not beside and besideSpot(a.world, at.x, at.y)
    local path = spot and b:pathTo(spot.x, spot.y)
    if path then
        b:setPath(path, 'play') -- arrive() starts the talk
    else
        Worker.startTalk(pl)
    end
    return pl
end

-- b is beside a (or gave up getting there): face each other and begin.
function Worker.startTalk(pl)
    if pl.started then return end
    pl.started = true
    local a, b = pl.a, pl.b
    b:face(a.x - b.x, 0)
    a:face(b.x - a.x, 0)
end

-- Still in it: here, fed, and playing (or walking over to).
local function stillPlaying(w, pl)
    return w.alive and w.state ~= 'quitting' and w.play == pl and w.hunger >= HUNGER_EAT_THRESHOLD
        and (w.state == 'playing' or (w.state == 'walking' and w.goal == 'play'))
end

-- Run the play (called on the one who offered it): wait for a partner,
-- wait for it to walk over, then a line every PLAY_LINE_SECONDS, A then B,
-- and the lift once the last line has been said.
function Worker:updatePlay(dt)
    local pl = self.play
    local a, b = pl.a, pl.b
    if not stillPlaying(a, pl) then self:endPlay(false) return end
    if not b then
        pl.wait = pl.wait - dt
        if pl.wait <= 0 then self:endPlay(false) end
        return
    end
    if not stillPlaying(b, pl) then self:endPlay(false) return end
    if not pl.started then
        pl.walk = pl.walk - dt
        if pl.walk > 0 then return end
        Worker.startTalk(pl)
    end
    pl.chat = pl.chat - dt
    if pl.chat <= 0 then
        if pl.lines >= #pl.convo then self:endPlay(true) return end
        pl.lines = pl.lines + 1
        local speaker = (pl.lines % 2 == 1) and a or b
        speaker:say(pl.convo[pl.lines], PLAY_BUBBLE_SECONDS)
        -- added on, not set, so the lines keep time whatever the frame rate
        pl.chat = pl.chat + PLAY_LINE_SECONDS
    end
end

-- Over, on either morphi. done: the talk was had, and both cheer up.
-- Otherwise somebody dropped out (or nobody came): no lift for anyone, and
-- whoever is still standing there gets back to work.
function Worker:endPlay(done)
    local pl = self.play
    if not pl then return end
    if self.world.openPlay == pl then self.world.openPlay = nil end
    local who = { pl.a }
    if pl.b then who[2] = pl.b end
    for _, w in ipairs(who) do
        if w.play == pl then
            local wasIn = stillPlaying(w, pl)
            w.play = nil
            if done then
                w.morale = math.min(MORALE_MAX, w.morale + MORALE_PLAY)
                w.idleSince = nil
            end
            if w.state == 'playing' or (w.state == 'walking' and w.goal == 'play') then
                w.state = 'idle'
                w.goal = nil
                w.path = nil
                w.moving = false
                w.decideTimer = 0
            end
            if not done and pl.b and wasIn then w:say('oh. bye', 1.5) end
        end
    end
    if not pl.b then pl.a.playRetryAt = pl.a.clock + PLAY_RETRY_SECONDS end
    if done then
        pl.a:emit('play', { partner = pl.b, category = pl.category, title = pl.convo.title, dev = pl.dev })
    end
end

-- The tester's PLAY NOW: the two free morphis nearest each other start
-- playing straight away, this season's chance or not. Free here means in
-- the wilds, still here, not hungry and not already trading or playing.
-- Returns the play, or nil when there are not two such morphis.
function Worker.playNow(workers, category)
    local free = {}
    for _, w in ipairs(workers) do
        if w.wilds and w:isWorking() and w.trade == nil and w.play == nil and w.hunger >= HUNGER_EAT_THRESHOLD then
            free[#free + 1] = w
        end
    end
    local best, bestD = nil, math.huge
    for i = 1, #free do
        for j = i + 1, #free do
            local d = Util.dist(free[i].x, free[i].y, free[j].x, free[j].y)
            if d < bestD then best, bestD = { free[i], free[j] }, d end
        end
    end
    if not best then return nil end
    return Worker.beginPlay(best[1], best[2], nil, true, category)
end

-- Free for a tester to pair up: in the wilds, here, not hungry, and not
-- trading or playing. (The DEV screen lists these.)
function Worker:canBePaired()
    return self.wilds and self:isWorking() and self.trade == nil and self.play == nil
        and self.hunger >= HUNGER_EAT_THRESHOLD
end

-- The tester's pick: a and b play category at once, whatever else they were
-- doing and whenever they last had fun. Returns the play, or nil.
function Worker.playPair(a, b, category)
    if not (a and b and a ~= b and a:canBePaired() and b:canBePaired()) then return nil end
    return Worker.beginPlay(a, b, nil, true, category)
end

-- Why a job has nothing for this morphi right now: { job, slot, why, at }.
-- why is 'storage' (foraging, with nowhere to put food), 'water' (the
-- nearest work of that job is across water: bridge it), 'walled' (behind
-- rock or otherwise cut off: dig to it), 'taken' (what there is, others
-- are already doing) or 'none' (no work of that kind
-- anywhere: nothing ripe, nothing marked). at is the work out of reach.
local SITE_JOB = { mine = 'mine', storage = 'build', bin = 'build', bridge = 'build', wall = 'build', door = 'build', bed = 'nestwork' }
local NODE_JOB = { bush = 'forage', tree = 'gather', ore = 'mine', grass = 'gather', leaves = 'gather', critter = 'hunt' }

function Worker:whyNoWork(job, slot)
    local t = self:tile()
    local types = {}
    for _, ty in ipairs(JobSets.jobTypes(job)) do types[ty] = true end
    if (types.forage or types.hunt) and self.world:nearestFreeStorageTile(self) == nil then
        return { job = job, slot = slot, why = 'storage' }
    end
    local best, bestD = nil, math.huge
    for _, node in ipairs(self.world.nodes) do
        if node.ready and types[NODE_JOB[node.kind]] and not self.world:nodeReachable(node) then
            local d = Util.manhattan(node.x, node.y, t.x, t.y)
            if d < bestD then best, bestD = node, d end
        end
    end
    for _, site in ipairs(self.world.sites) do
        if not site.done and types[SITE_JOB[site.kind]] and not self.world:siteReachable(site) then
            local d = Util.manhattan(site.x, site.y, t.x, t.y)
            if d < bestD then best, bestD = site, d end
        end
    end
    if not best then
        -- reachable work all in other hands, or none at all
        for _, node in ipairs(self.world.nodes) do
            if node.ready and types[NODE_JOB[node.kind]] and self.world:nodeReachable(node) then
                return { job = job, slot = slot, why = 'taken' }
            end
        end
        for _, site in ipairs(self.world.sites) do
            if not site.done and types[SITE_JOB[site.kind]] and self.world:siteReachable(site) then
                return { job = job, slot = slot, why = 'taken' }
            end
        end
        return { job = job, slot = slot, why = 'none' }
    end
    local reach = self.world:reachableFromBreakroom()
    local water = self.world:acrossWater(best.x, best.y, reach)
    if not water then
        for _, c in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local x, y = best.x + c[1], best.y + c[2]
            if self.world:isPassable(x, y) and self.world:acrossWater(x, y, reach) then water = true break end
        end
    end
    return { job = job, slot = slot, why = water and 'water' or 'walled', at = best }
end

-- Every one of my jobs, in order, with why it has nothing for me.
function Worker:idleReasons()
    local out = {}
    for _, o in ipairs(self:jobOrder()) do out[#out + 1] = self:whyNoWork(o.job, o.slot) end
    return out
end

-- A job somebody could do now (reachable work waiting on the queue) that
-- nobody in the band has as main or neutral job. Nil if there is none.
function Worker:unstaffedJob()
    if not (self.jobSet and self.band) then return nil end
    local staffed = {}
    for _, w in ipairs(self.band) do
        if w.jobSet and w:isWorking() then
            staffed[w.jobSet.main] = true
            if w.jobSet.neutral then staffed[w.jobSet.neutral] = true end
        end
    end
    for _, job in ipairs(JobSets.JOBS) do
        if not staffed[job] then
            local types = {}
            for _, ty in ipairs(JobSets.jobTypes(job)) do types[ty] = true end
            for _, j in ipairs(self.jobs.items) do
                if types[j.type] and ((j.node and j.node.ready and self.world:nodeReachable(j.node))
                    or (j.site and not j.site.done and self.world:siteReachable(j.site))
                    or (j.area and self.world:areaReachable(j.area))
                    or (j.baby and j.baby.alive and j.baby:isBaby())) then
                    return job
                end
            end
        end
    end
    return nil
end

local WHY_TEXT = {
    storage = 'nowhere to put berries (lay a STASH or a BASKET)',
    water = 'the nearest is across water (BRIDGE it)',
    walled = 'the nearest is cut off (DIG a way)',
    taken = 'others have it all in hand',
    none = 'none to do',
}
local NONE_TEXT = {
    forager = 'no ripe bushes', lumberjack = 'no trees, grass or leaves', miner = 'no clay marked to dig', builder = 'nothing marked to build', hunter = 'no critters about', caretaker = 'no baby needs anything',
}

-- The idle reason as a line for the player, naming the jobs.
function Worker.idleText(reasons, noNeutral, unstaffed)
    local parts = {}
    for i, r in ipairs(reasons) do
        local what = r.why == 'none' and (NONE_TEXT[r.job] or WHY_TEXT.none) or WHY_TEXT[r.why]
        if r.at and r.why ~= 'none' then what = what .. ' at ' .. r.at.x .. ',' .. r.at.y end
        local who = (i == 1 and '' or (r.slot .. ' ')) .. JobSets.label(r.job)
        parts[#parts + 1] = who .. ': ' .. what
        if i == 1 and noNeutral then parts[#parts + 1] = 'no neutral job set' end
    end
    local text = table.concat(parts, '; ')
    if unstaffed then text = text .. '. ' .. JobSets.label(unstaffed) .. ' work is waiting and no one has ' .. JobSets.label(unstaffed) .. ' set' end
    return text
end

-- Idle, in a few words for the strip and the units list: the main job's
-- reason (looked at again at most once a second).
local SHORT_WHY = { storage = 'nowhere to put berries', water = 'work across water', walled = 'work cut off', taken = 'all taken' }
function Worker:idleSummary()
    if not self.jobSet then return nil end
    if not self.idleLook or self.clock - self.idleLook.at >= 1 or self.idleLook.main ~= self.jobSet.main or self.idleLook.neutral ~= self.jobSet.neutral then
        local r = self:whyNoWork(self.jobSet.main, 'main')
        local text = JobSets.label(r.job) .. ': ' .. (SHORT_WHY[r.why] or NONE_TEXT[r.job] or 'nothing to do')
        if not self.jobSet.neutral then text = text .. ', no fallback' end
        self.idleLook = { at = self.clock, main = self.jobSet.main, neutral = self.jobSet.neutral, text = text }
    end
    return self.idleLook.text
end

-- Nothing to do: a hardship. Remembers why, job by job, and points at the
-- nearest work of the main job that is out of reach, if any.
function Worker:bored()
    local reasons = self:idleReasons()
    self.idleWhy = reasons
    self.unstaffed = self:unstaffedJob()
    local first = reasons[1]
    self.boredReason = first and (first.why == 'storage' and 'storage' or 'reach') or 'reach'
    local node = nil
    for _, r in ipairs(reasons) do
        if r.at then node = r.at break end
    end
    self:complain('bored', node)
end

function Worker:complain(reason, node)
    if node then node.complainedAt = self.clock end
    self.scoring:addComplaint()
    self.complaintCount = self.complaintCount + 1
    if not self.arcade then self.morale = self.morale - (reason == 'bored' and MORALE_BORED_HIT or MORALE_COMPLAINT_HIT) end
    self:say('!!')
    if node then self:ick(node.x, node.y) end
    if self.onComplain then self.onComplain(self, reason, node) end
    self:emit('complain', reason)
    self:dropJob()
    if self.morale <= 0 then
        self.morale = 0
        self:quit('morale')
        return
    end
    self.state = 'sulking'
    self.stateTimer = WORKER_SULK_SECONDS
end

function Worker:quit(reason)
    if self.trade then self:endTrade(false) end
    if self.play then self:endPlay(false) end
    self:dropJob()
    self.slots = {}
    self.scoring:addQuit()
    self:say('bye bye', 6)
    self:emit('quit', reason or 'starved')
    self.state = 'quitting'
    local t = self:tile()
    local choices = {
        { dx = -1, dy = 0, d = t.x },
        { dx = 1, dy = 0, d = self.world.w - t.x },
        { dx = 0, dy = -1, d = t.y },
        { dx = 0, dy = 1, d = self.world.h - t.y },
    }
    table.sort(choices, function(a, b) return a.d < b.d end)
    self.exitDir = choices[1]
end

-- Movement --------------------------------------------------------------

function Worker:setPath(path, goal)
    self.path = path
    self.pathIndex = 1
    self.goal = goal
    self.walkTime = 0
    self.state = 'walking'
    local t = self:tile()
    if path[1] and path[1].x == t.x and path[1].y == t.y then
        self.pathIndex = 2
    end
    if self.pathIndex > #path then self:arrive() end
end

function Worker:pathTo(x, y)
    local t = self:tile()
    return Pathfinder.find(self.world, t.x, t.y, x, y)
end

function Worker:pathToBreakroom()
    local t = self:tile()
    local br = self.world:nearestBreakroomTile(t.x, t.y)
    return br and self:pathTo(br.x, br.y)
end

-- After idling on top of a stored item or the furniture, move one tile over.
function Worker:stepOff()
    local t = self:tile()
    local tile = self.world:get(t.x, t.y)
    if not tile or (#tile.items == 0 and tile.storage == 0 and not tile.bed and tile.type ~= TILE_BREAKROOM) then return false end
    local spot = self.world:freeNeighbour(t.x, t.y)
    if not spot then return false end
    local path = self:pathTo(spot.x, spot.y)
    if not path then return false end
    self:setPath(path, 'wander')
    return true
end

-- Eating ----------------------------------------------------------------

-- Eat from a slot. Only ever chosen while idle, like any other job.
function Worker:snack(slot)
    if not self:hasFoodInSlot(slot) then return false end
    self.eatingSlot = slot
    self.state = 'eating'
    self.stateTimer = EAT_SECONDS
    self.moving = false
    return true
end

function Worker:finishEating()
    if self.eatingSlot then
        if self:hasFoodInSlot(self.eatingSlot) then
            local food = self.slots[self.eatingSlot].food
            self.slots[self.eatingSlot] = nil
            self:mealOf(food)
            self.ate = true
            self:emit('eat')
        end
        self.eatingSlot = nil
    elseif self.targetNode and self.targetNode.ready then
        -- eating straight off a bush
        self:mealOf(self.targetNode.food)
        self.world:harvestNode(self.targetNode)
        self.ate = true
        self:emit('eat')
        self:releaseNode()
    end
    self.goal = nil
    self.state = 'idle'
    self.decideTimer = 0
end

-- Nearest ripe, unclaimed, not icked bush the morphi can reach. Second return
-- value is the nearest such bush that is walled off, if any.
function Worker:nearestRipeBush()
    local best, bestD = nil, math.huge
    local blocked, blockedD = nil, math.huge
    for _, node in ipairs(self.world.nodes) do
        if self:eatsFrom(node) and node.ready and node.claimedBy == nil and not self:isIcked(node.x, node.y) then
            local c = Util.tileCenter(node.x, node.y)
            local d = Util.dist(self.x, self.y, c.x, c.y)
            if self.wilds and node.food == self.diet then d = d * 0.5 end -- worth the walk
            if self.world:isReachable(node.x, node.y) then
                if d < bestD then best, bestD = node, d end
            elseif d < blockedD and not self:recentlyReported(node) then
                blocked, blockedD = node, d
            end
        end
    end
    return best, blocked
end

-- Walk to a stored food item and put it in the personal slot.
function Worker:fetchFood()
    if self.slots[SLOT_PERSONAL] then return false end
    local t = self:tile()
    local item = self:storedMeal(t)
    if not item then return false end
    local path = self:pathTo(item.x, item.y)
    if not path then return false end
    item.claimedBy = self
    self.targetItem = item
    self:setPath(path, 'fetch')
    return true
end

-- Is there a meal this morphi could walk to right now? Stored food it can
-- reach counts. On a picky (bins) level with nothing stored yet, a
-- reachable bin plus a reachable ripe bush counts too, since a forager can
-- fill it. Otherwise a reachable ripe bush. Used by the stuck check.
-- The stored food I would go for: the loved kind if there is any, else
-- anything I will eat.
function Worker:storedMeal(t)
    if self.arcade then return self.world:nearestStoredItem(ITEM_FOOD, t.x, t.y) end
    local loved = self.world:nearestStoredItem(ITEM_FOOD, t.x, t.y, self.diet)
    if loved or not self.wilds then return loved end
    return self.world:nearestStoredItem(ITEM_FOOD, t.x, t.y, function(food) return self:willEat(food) end)
end

function Worker:canReachFood()
    local t = self:tile()
    if self:storedMeal(t) then return true end
    local bush = self:nearestRipeBush()
    if self.arcade and self.world.arcadeNeeds and self.world.arcadeNeeds.bins then
        if not bush then return false end
        for _, s in ipairs(self.world:storageTiles()) do
            if s.capacity > STORAGE_FLOOR_CAPACITY and self.world:isReachable(s.x, s.y) then return true end
        end
        return false
    end
    return bush ~= nil
end

function Worker:eatSomething()
    if self:snackInPocket() then return self:snack(SLOT_PERSONAL) end
    if self:fetchFood() then return true end
    -- picky arcade morphis eat out of a bin or not at all; the rest of
    -- arcade waits quietly, no grumbling, when the bush is out of reach
    if self.arcade and self.world.arcadeNeeds.bins then return false end
    local bush, blocked = self:nearestRipeBush()
    if self.arcade then blocked = nil end
    if bush then
        local path = self:pathTo(bush.x, bush.y)
        if path then
            bush.claimedBy = self
            self.targetNode = bush
            self:setPath(path, 'eat')
            return true
        end
    elseif blocked then
        -- one grumble per cooldown, however many bushes are out of reach:
        -- waiting on a bridge should not cost a morphi its whole morale
        if self.lastHungryComplaint == nil or self.clock - self.lastHungryComplaint >= COMPLAINT_COOLDOWN then
            self.lastHungryComplaint = self.clock
            self:complain('hungry', blocked)
            return true
        end
    end
    return false
end

-- Head for the break room, grabbing a snack from storage on the way if the
-- pocket is empty.
function Worker:startBreak()
    self.wantsBreak = true
    if not self.slots[SLOT_PERSONAL] and self:fetchFood() then return true end
    return self:goRest()
end

-- Claim a rest spot of my own and walk there.
function Worker:goRest()
    local t = self:tile()
    local spot = self.world:claimRestSpot(self, t.x, t.y)
    local path = spot and self:pathTo(spot.x, spot.y)
    if path then
        self.restSpot = spot
        self:setPath(path, 'break')
        return true
    end
    self.world:releaseRestSpot(self)
    self.restSpot = nil
    self.wantsBreak = false
    self.workTime = 0
    return false
end

-- Decisions ---------------------------------------------------------------

function Worker:decide()
    if self.stage == 'baby' then return self:decideBaby() end
    -- 0. Somebody at camp wants to trade and I could use cheering up
    if self.wilds and self.morale < MORALE_MAX - 10 and self.world.openTrade and self:atCamp() and self:joinTrade() then return end
    -- 1. Survival beats output. In arcade: the one meal, once the level's
    --    needs are met.
    if self.hunger < HUNGER_EAT_THRESHOLD or (self:wantsMeal() and self.world:arcadeReady()) then
        if self:eatSomething() then return end
    end
    -- 2. Earned a break
    if self.workTime >= self.breakAfter or self.wantsBreak then
        if self:startBreak() then return end
    end
    -- 3. Still holding something? Get it home first.
    if self:carrying() then
        if self:goDeliver() then return end
        if self:edible(self:carrying()) and self.hunger < HUNGER_EAT_THRESHOLD then
            self.slots[SLOT_WORK].kind = ITEM_FOOD
            self:snack(SLOT_WORK)
            return
        end
        self.decideTimer = DECIDE_INTERVAL * 4
        return
    end
    -- 4. The nearest job I can do and can actually walk to, main job first,
    --    then neutral, then disliked (free play). Jobs nobody can reach stay
    --    on the queue untouched. Foraging waits for somewhere to put the
    --    food. The claim happens inside takeNearest, in the same step the job
    --    leaves the queue, so it cannot be shared.
    local function usable(j)
        if j.baby then
            return j.baby.alive and j.baby:isBaby() and j.baby.caredBy == nil
        end
        if j.node then
            return j.node.ready and j.node.claimedBy == nil and not self:isIcked(j.x, j.y) and self.world:nodeReachable(j.node)
        end
        if j.area then
            return j.area.claimedBy == nil and #j.area.sites > 0 and self.world:areaReachable(j.area)
        end
        return not j.site.done and j.site.claimedBy == nil and self.world:siteReachable(j.site)
    end
    local here = self:tile()
    local claimedPath = nil
    local function claim(j)
        if j.area then
            j.area.claimedBy = self
            return true
        end
        if j.baby then
            local t = j.baby:tile()
            local path = self:pathTo(t.x, t.y)
            if not path then return false end
            claimedPath = path
            j.baby.caredBy = self
            return true
        end
        local spot = j.node and self.world:approachTile(j.node) or self.world:siteApproachTile(j.site)
        if not spot then return false end
        local path = self:pathTo(spot.x, spot.y)
        if not path then return false end
        claimedPath = path
        local target = j.node or j.site
        target.claimedBy = self
        return true
    end
    local job
    for _, tier in ipairs(self:jobTiers()) do
        if #tier.types > 0 then
            job = self.jobs:takeNearest(tier.types, here.x, here.y, usable, claim, JOB_PATH_TRIES)
            if job then
                self.doing = tier.job
                break
            end
        end
    end
    if job then self.idleSince = nil end
    if job and job.area then
        self.job = nil -- the area is the job; it is reposted if anything is left
        self.targetArea = job.area
        self.areaTilesDone = 0
        if not self:continueArea() then self:releaseArea(); self.state = 'idle' end
        return
    end
    if job then
        self.job = job
        self.targetNode = job.node
        self.targetSite = job.site
        self.targetBaby = job.baby
        self:setPath(claimedPath, 'work')
        return
    end
    -- 4. Nothing to do. In the wilds that wears on a specialist.
    if self.wilds then
        self.idleSince = self.idleSince or self.clock
        if self.clock - self.idleSince >= BORED_SECONDS then
            self.idleSince = self.clock
            self:bored()
            return
        end
        -- due for some fun: join somebody who wants to play, or offer at the
        -- home nest. Waiting for a partner is still standing about; only
        -- playing itself is fun.
        if self:joinPlay() or self:offerPlay() then return end
    end
    -- 4. Do not loiter on the pantry
    if self:stepOff() then return end
    -- 5. Wander
    local t = self:tile()
    local target = self.rng and self.world:randomNearbyPassable(self.rng, t.x, t.y, WANDER_RADIUS)
    if target then
        local path = self:pathTo(target.x, target.y)
        if path then
            self:setPath(path, 'wander')
            return
        end
    end
    self.decideTimer = DECIDE_INTERVAL * 2
end

-- The job queue types to look at, tier by tier: { {job, slot, types}, ... }.
-- Free play: main, neutral, disliked, each with its own types. Arcade: the
-- one role's types. The retired survival levels: the role's types and
-- 'build', which anyone took there. Foraging only with storage to put food.
function Worker:jobTiers()
    local room
    local function typesOf(job)
        local out = {}
        for _, t in ipairs(JobSets.jobTypes(job)) do
            if t == 'forage' or t == 'hunt' then
                if room == nil then room = self.world:nearestFreeStorageTile(self) ~= nil end
                if room then out[#out + 1] = t end
            else
                out[#out + 1] = t
            end
        end
        return out
    end
    local tiers = {}
    for _, o in ipairs(self:jobOrder()) do
        tiers[#tiers + 1] = { job = o.job, slot = o.slot, types = typesOf(o.job) }
    end
    if not self.jobSet and not self.arcade then
        local t = tiers[1].types
        t[#t + 1] = 'build'
    end
    return tiers
end

-- Next tile of the claimed mine area. Returns false when nothing reachable
-- is left or when the morphi should stop for food or a break.
function Worker:continueArea()
    local area = self.targetArea
    if not area then return false end
    if #area.sites == 0 then
        self:releaseArea()
        return false
    end
    if self.hunger < HUNGER_EAT_THRESHOLD or self.workTime >= self.breakAfter then
        self:releaseArea()
        return false
    end
    if self.areaTilesDone >= self.mineLimit then
        -- enough for one trip; the rest goes back on the queue for whoever is free
        self:releaseArea()
        return false
    end
    local t = self:tile()
    local site, spot = self.world:nextSiteInArea(area, t.x, t.y)
    if not site then
        self:releaseArea()
        return false
    end
    local path = self:pathTo(spot.x, spot.y)
    if not path then
        self:releaseArea()
        return false
    end
    site.claimedBy = self
    self.targetSite = site
    self:setPath(path, 'work')
    return true
end

function Worker:followPath(dt)
    if (self.goal == 'work' or self.goal == 'eat') and self.targetNode and not self.targetNode.ready then
        self:releaseNode()
        self.job = nil
        self.path = nil
        self.goal = nil
        self.state = 'idle'
        return
    end
    if self.goal == 'work' and self.targetBaby and not (self.targetBaby.alive and self.targetBaby:isBaby()) then
        self:releaseBaby()
        self.job = nil
        self.path = nil
        self.goal = nil
        self.state = 'idle'
        return
    end
    if self.goal == 'work' and self.targetSite and (self.targetSite.done or self.targetSite.claimedBy ~= self) then
        self:releaseSite()
        self.job = nil
        self.path = nil
        self.goal = nil
        self.state = 'idle'
        return
    end
    if self.goal == 'fetch' and self.targetItem and not self.world:tileHasItem(self.targetItem.x, self.targetItem.y, self.targetItem) then
        self:releaseItem()
        self.path = nil
        self.goal = nil
        self.state = 'idle'
        self.decideTimer = 0
        return
    end
    self.walkTime = self.walkTime + dt
    -- a morphi walks as far as it takes and never gives up on a long walk
    -- (Micah, 2026-10-21). Only a way that has been shut since it set off
    -- (a wall built across it) sends it back to think again, quietly.
    local node = self.path and self.path[self.pathIndex]
    if node and not self.world:isPassable(node.x, node.y) then
        self:dropJob()
        self.path = nil
        self.goal = nil
        self.state = 'idle'
        self.decideTimer = 0
        return
    end
    if not node then
        self:arrive()
        return
    end
    local c = Util.tileCenter(node.x, node.y)
    local dx, dy = c.x - self.x, c.y - self.y
    local d = math.sqrt(dx * dx + dy * dy)
    local step = self.speed * dt
    self.moving = true
    if d <= step then
        self.x, self.y = c.x, c.y
        self.pathIndex = self.pathIndex + 1
        if self.pathIndex > #self.path then self:arrive() end
    else
        self.x = self.x + dx / d * step
        self.y = self.y + dy / d * step
        self:face(dx, dy)
    end
end

-- Carry the work item home: food goes onto a storage tile, logs and gold
-- are handed in at the break room.
function Worker:goDeliver()
    local cargo = self:carrying()
    if not cargo then return false end
    local path
    if cargo.kind == CARGO_FOOD then
        local spot = self.world:nearestFreeStorageTile(self)
        if not spot then
            self:say('no stash', 1.5)
            return false
        end
        self.world:reserveTile(spot.x, spot.y, self)
        self.targetTile = spot
        path = self:pathTo(spot.x, spot.y)
    else
        path = self:pathToBreakroom()
    end
    if path then
        self:setPath(path, 'deliver')
        return true
    end
    self:releaseTile()
    return false
end

function Worker:deliverHere()
    local cargo = self:carrying()
    if not cargo then return end
    local t = self:tile()
    if cargo.kind == CARGO_FOOD then
        if not self.world:hasRoom(t.x, t.y) then
            -- somebody filled it first, find another tile
            self:releaseTile()
            if self:goDeliver() then return end
            return
        end
        self.world:storeItem(ITEM_FOOD, t.x, t.y, cargo.food)
        self:releaseTile()
    end
    if cargo.kind ~= CARGO_FOOD then
        self.world:addStock(cargo.kind, 1)
    end
    self.slots[SLOT_WORK] = nil
    self.scoring:addDelivery(cargo.kind)
    self.delivered = self.delivered + 1
    self:emit('deliver', cargo.kind)
    self.goal = nil
    self.state = 'idle'
    self.decideTimer = 0
    if self.targetArea and self:continueArea() then return end
    -- a natural break: play, if somebody is waiting or I am at the nest and due
    if self.wilds and (self:joinPlay() or self:offerPlay()) then return end
    if cargo.kind == CARGO_FOOD then self:stepOff() end
end

function Worker:arrive()
    self.path = nil
    self.moving = false
    if self.goal == 'eat' then
        self.state = 'eating'
        self.stateTimer = EAT_SECONDS
    elseif self.goal == 'fetch' then
        local t = self:tile()
        local tile = self.world:get(t.x, t.y)
        if self.world:tileHasItem(t.x, t.y, self.targetItem) then
            local item = self.world:takeItem(t.x, t.y, self.targetItem)
            self.slots[SLOT_PERSONAL] = { kind = item.kind, food = item.food }
            self:emit('pickup', item.kind)
        end
        self:releaseItem()
        self.goal = nil
        self.state = 'idle'
        self.decideTimer = 0
        if (self.hunger < HUNGER_EAT_THRESHOLD or self:wantsMeal()) and self:snackInPocket() then
            self:snack(SLOT_PERSONAL)
        elseif self.wantsBreak then
            self:goRest()
        end
    elseif self.goal == 'break' then
        local t = self:tile()
        local tile = self.world:get(t.x, t.y)
        if tile.restingBy ~= nil and tile.restingBy ~= self then
            -- somebody took my spot, find another
            if self:goRest() then return end
        end
        tile.restingBy = self
        self.state = 'breaking'
        local inBed = self.restSpot ~= nil and self.restSpot.bed
        self.stateTimer = inBed and BREAK_SECONDS_BED or BREAK_SECONDS
        self:say(inBed and 'zzz' or 'break', 2)
    elseif self.goal == 'work' then
        self.state = 'working'
        -- turn to the work, not the way the last step went: the tool is
        -- held on the facing side
        local work = self.targetSite or self.targetNode
        if work and work.x then
            local c = Util.tileCenter(work.x, work.y)
            self:face(c.x - self.x, 0)
        end
        if self.targetSite then self.targetSite.working = true end
        if self.targetSite and self.targetSite.kind ~= SITE_MINE then
            self.stateTimer = BUILD_SECONDS
        else
            self.stateTimer = self:doingInfo().actionSeconds
        end
    elseif self.goal == 'deliver' then
        self:deliverHere()
    elseif self.goal == 'play' then
        -- walked over to play: the talk starts
        self.goal = nil
        if self.play then
            self.state = 'playing'
            Worker.startTalk(self.play)
        else
            self.state = 'idle'
        end
    else
        self.goal = nil
        self.state = 'idle'
    end
end

function Worker:finishAction()
    if self.state == 'eating' then
        self:finishEating()
    elseif self.state == 'breaking' then
        local inBed = self.restSpot ~= nil and self.restSpot.bed
        self.workTime = 0
        self.breakAfter = BREAK_AFTER_SECONDS * (inBed and BED_REST_BONUS or 1)
        self.wantsBreak = false
        self.breaksTaken = self.breaksTaken + 1
        self.morale = math.min(MORALE_MAX, self.morale + (inBed and MORALE_BED_BONUS or MORALE_BREAK_BONUS))
        self.world:releaseRestSpot(self)
        self.restSpot = nil
        -- feeling low with gold in the pile: talk somebody into a trade
        if self.wilds and self.morale < TRADE_BELOW and (self:joinTrade() or self:offerTrade()) then
            self:emit('break', inBed and 'bed' or 'floor')
            return
        end
        -- rested, at the nest: a good moment to play
        if self.wilds and (self:joinPlay() or self:offerPlay()) then
            self:emit('break', inBed and 'bed' or 'floor')
            return
        end
        self:emit('break', inBed and 'bed' or 'floor')
        self.state = 'idle'
        self.decideTimer = 0
        self:stepOff()
    elseif self.state == 'working' then
        local cargo = nil
        if self.targetSite and not self.targetSite.done then
            local site = self.targetSite
            local kind = self.world:completeSite(site)
            if kind then cargo = { kind = kind } end
            if kind == CARGO_GOLD and site.kind == SITE_MINE then self:emit('shiny', { x = site.x, y = site.y }) end
            if site.kind == SITE_MINE then self.areaTilesDone = self.areaTilesDone + 1 end
            self:emit(site.kind == SITE_MINE and 'mined' or 'built', site.kind)
        elseif self.targetNode and self.targetNode.ready then
            local node = self.targetNode
            local kind = self.world:harvestNode(node)
            cargo = { kind = kind, food = node.food }
            self:emit('work', node.kind)
        elseif self.targetBaby and self.targetBaby.alive and self.targetBaby:isBaby() then
            self:careFor(self.targetBaby)
        end
        self:releaseNode()
        self:releaseSite()
        self:releaseBaby()
        self.job = nil
        if cargo then
            -- nowhere to take it yet: keep hold of it (decide tries again,
            -- or eats it when hungry) rather than drop it into thin air
            self.slots[SLOT_WORK] = cargo
            if self:goDeliver() then return end
            self:releaseArea()
            self.goal = nil
            self.state = 'idle'
            self.decideTimer = DECIDE_INTERVAL * 4
            return
        end
        if self.targetArea and self:continueArea() then return end
        self.goal = nil
        self.state = 'idle'
        self.decideTimer = 0
    end
end

function Worker:accumulateWork(dt)
    if self.state == 'working' or (self.state == 'walking' and (self.goal == 'work' or self.goal == 'deliver')) then
        self.workTime = self.workTime + dt
    end
end

-- Hunger grinds morale down, a full belly slowly restores it. Returns true
-- if the morphi has had enough and quit.
function Worker:updateMorale(dt)
    if self.hunger < HUNGER_EAT_THRESHOLD then
        self.morale = self.morale - MORALE_HUNGRY_DRAIN * dt
    elseif self.morale > 0 then
        -- a fed morphi cheers up, unless it has been standing about with nothing to do
        local idle = self.wilds and self.idleSince ~= nil and self.clock - self.idleSince > WORKER_SULK_SECONDS * 2
        if not idle then self.morale = math.min(MORALE_MAX, self.morale + MORALE_RECOVER * dt) end
    end
    if self.morale <= 0 then
        self.morale = 0
        self:quit('morale')
        return true
    end
    if self.morale < MORALE_LOW then
        if not self.warnedLowMorale then
            self.warnedLowMorale = true
            self:say('ugh', 3)
            self:emit('lowmorale')
        end
    elseif self.morale > MORALE_LOW + 15 then
        self.warnedLowMorale = false
    end
    return false
end

-- What is in the morphi's hand while it heads to or does tool work:
-- 'axe' for trees, 'pickaxe' for ore and mine marks, 'saw' for a bed,
-- 'log' for floor spots, bins and bridges. Nil for foraging and the rest.
function Worker:toolInHand()
    if not (self.state == 'working' or (self.state == 'walking' and self.goal == 'work')) then return nil end
    -- little blobs, no axes or pickaxes: a twig bundle for sticks and
    -- building, a little spade for digging, a leaf for weaving a nest
    if self.targetNode then
        if self.targetNode.kind == NODE_TREE then return 'twigs' end
        if self.targetNode.kind == NODE_ORE then return 'spade' end
        return nil
    end
    local site = self.targetSite
    if not site then return nil end
    if site.kind == SITE_MINE then return 'spade' end
    if site.kind == SITE_BED then return 'leaf' end
    return 'twigs'
end

function Worker:mood()
    if self.morale < MORALE_LOW then return 'very grumpy' end
    if self.morale < 65 then return 'grumpy' end
    return 'fine'
end

-- A wall went up under my feet: step onto the nearest open tile, towards
-- camp if there is a choice, and think again. Nothing can path from inside
-- a wall, so without this the morphi would stand there for ever.
function Worker:unstick(x, y)
    local best = nil
    for _, c in ipairs({ { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 }, { x + 1, y + 1 }, { x - 1, y - 1 }, { x + 1, y - 1 }, { x - 1, y + 1 } }) do
        if self.world:isPassable(c[1], c[2]) then
            best = best or c
            if self.world:isReachable(c[1], c[2]) then best = c; break end
        end
    end
    if not best then return false end
    local c = Util.tileCenter(best[1], best[2])
    self.x, self.y = c.x, c.y
    self:dropJob()
    self.eatingSlot = nil
    self.state = 'idle'
    self.decideTimer = 0
    return true
end

function Worker:update(dt, clock)
    self.clock = clock or (self.clock + dt)
    self.animTime = self.animTime + dt
    if self.bubble then
        self.bubble.ttl = self.bubble.ttl - dt
        if self.bubble.ttl <= 0 then self.bubble = nil end
    end
    if not self.alive then return end
    -- an egg just sits in its nest until it hatches
    if self.stage == 'egg' then
        self.hatchTimer = self.hatchTimer - dt
        if self.hatchTimer <= 0 then self:hatch() end
        return
    end
    if self.state ~= 'quitting' then
        local here = self:tile()
        if not self.world:isPassable(here.x, here.y) then self:unstick(here.x, here.y) end
    end
    if self.state == 'quitting' then
        local d = self.exitDir
        self.x = self.x + d.dx * self.speed * dt
        self.y = self.y + d.dy * self.speed * dt
        self:face(d.dx, d.dy)
        self.moving = true
        local t = self:tile()
        if not self.world:inBounds(t.x, t.y) then self.alive = false end
        return
    end
    if not self.arcade and self.state ~= 'trading' then
        self.hunger = self.hunger - self.drain * dt
        if self.hunger <= 0 then
            -- starving: it holds out as long again as a full belly lasts
            self.hunger = 0
            if self.stage ~= 'baby' then
                self.starveTimer = (self.starveTimer or HUNGER_MAX / math.max(self.drain, 0.01)) - dt
                if self.starveTimer <= 0 then
                    if self.wilds then self:die('hunger') else self:quit('starved') end
                    return
                end
            end
        else
            self.starveTimer = nil
        end
        if self:updateMorale(dt) then return end
    end
    if self.stage == 'baby' then
        self:updateBaby(dt)
        if not self.alive then return end
    end
    self:accumulateWork(dt)
    self.moving = false
    if self.state == 'idle' then
        self.decideTimer = self.decideTimer - dt
        if self.decideTimer <= 0 then
            self.decideTimer = DECIDE_INTERVAL
            self:decide()
        end
    elseif self.state == 'sulking' then
        self.stateTimer = self.stateTimer - dt
        if self.stateTimer <= 0 then self.state = 'idle' end
    elseif self.state == 'walking' then
        self:followPath(dt)
    elseif self.state == 'eating' or self.state == 'working' or self.state == 'breaking' then
        self.stateTimer = self.stateTimer - dt
        if self.stateTimer <= 0 then self:finishAction() end
    elseif self.state == 'trading' then
        -- the one who offered runs the trade for both
        if self.trade and self.trade.a == self then self:updateTrade(dt) end
    end
    -- the one who offered a play runs it for both, whatever it is doing
    if self.play and self.play.a == self then self:updatePlay(dt) end
end

-- What things are called on screen (the keys stay as they were).
local CARGO_WORDS = { food = 'food', logs = 'sticks', gold = 'a shiny', grass = 'grass', leaves = 'leaves' }
local SITE_WORDS = { storage = 'a stash', bin = 'a basket', bed = 'a nest', bridge = 'a bridge', wall = 'a wall', door = 'a door' }
local function siteWord(kind) return SITE_WORDS[kind] or kind end

function Worker:describeState()
    if self.state == 'quitting' then return 'Toddling off' end
    if self.arcade and self.state == 'idle' and self:wantsMeal() and not self.world:arcadeReady() then return 'Waiting to eat' end
    if self.state == 'sulking' then return 'Grumbling' end
    if self.state == 'trading' and self.trade then
        local tr = self.trade
        if not tr.b then return 'Waiting at the home nest to swap' end
        return 'Swapping snacks with ' .. (tr.a == self and tr.b or tr.a).name
    end
    if self.play and self:isPlaying() then
        local pl = self.play
        if not pl.b then return 'Waiting at the home nest to play' end
        local other = (pl.a == self and pl.b or pl.a).name
        if self.state == 'walking' then return 'Going over to play with ' .. other end
        return (PLAY_DOING[pl.category] or 'Playing with ') .. other
    end
    if self.state == 'eating' then return 'Eating' end
    if self.state == 'breaking' then return (self.restSpot and self.restSpot.bed) and 'Napping in a nest' or 'Resting at the home nest' end
    if self.state == 'working' then
        if self.targetSite and self.targetSite.kind ~= SITE_MINE then return 'Building ' .. siteWord(self.targetSite.kind) .. self:slotNote() end
        local verb = self:doingInfo().verb
        return verb:sub(1, 1):upper() .. verb:sub(2) .. self:slotNote()
    end
    if self.state == 'walking' then
        if self.goal == 'deliver' then
            local c = self:carrying()
            return 'Carrying ' .. (c and (CARGO_WORDS[c.kind] or c.kind) or 'things') .. (c and c.kind == CARGO_FOOD and ' to a stash' or ' home')
        end
        if self.goal == 'eat' then return 'Going to eat' end
        if self.goal == 'fetch' then return 'Fetching a snack from a stash' end
        if self.goal == 'break' then return (self.restSpot and self.restSpot.bed) and 'Heading to a nest' or 'Heading home' end
        if self.goal == 'work' then
            if self.targetSite and self.targetSite.kind ~= SITE_MINE then return 'Going to build ' .. siteWord(self.targetSite.kind) .. self:slotNote() end
            return 'Going ' .. self:doingInfo().verb .. self:slotNote()
        end
        return self.stage == 'baby' and 'Toddling about' or 'Wandering'
    end
    local c = self:carrying()
    if c then
        return 'Holding ' .. (CARGO_WORDS[c.kind] or c.kind) .. (c.kind == CARGO_FOOD and ', no stash free' or ', no way home')
    end
    if self.wilds and self.jobSet and self.idleSince then return 'Idle - ' .. self:idleSummary() end
    if self.stage == 'baby' then return 'Toddling about' end
    if self.stage == 'egg' then return 'An egg, hatching in ' .. math.ceil(self.hatchTimer) .. 's' end
    return 'Idle'
end

-- Free play, at work on a job that is not its main one: says which.
function Worker:slotNote()
    if not self.jobSet or not self.doing then return '' end
    local slot = self:slotOf(self.doing)
    if slot == 'neutral' then return ' (neutral job)' end
    if slot == 'disliked' then return ' (disliked job)' end
    return ''
end

return Worker
