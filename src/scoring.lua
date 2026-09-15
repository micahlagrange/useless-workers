require('src.constants')

local Scoring = {}
Scoring.__index = Scoring

function Scoring.new(difficultyIndex)
    local self = setmetatable({}, Scoring)
    self.difficultyIndex = difficultyIndex or DEFAULT_DIFFICULTY
    self.difficulty = DIFFICULTIES[self.difficultyIndex]
    self.drain = self.difficulty.drain
    self.quarter = 1
    self.quarterTimer = QUARTER_SECONDS
    self.output = 0
    self.delivered = { food = 0, logs = 0, gold = 0 }
    self.lifetimeDelivered = { food = 0, logs = 0, gold = 0 }
    self.complaints = 0
    self.quits = 0
    self.fedSum = 0
    self.fedCount = 0
    self.fedTimer = 0
    self.budget = BUDGET_START
    self.lifetimeOutput = 0
    self.totalComplaints = 0
    self.totalQuits = 0
    self.reports = {}
    self.endless = false
    return self
end

function Scoring:addOutput()
    self.output = self.output + 1
    self.lifetimeOutput = self.lifetimeOutput + 1
end

function Scoring:addDelivery(kind)
    self:addOutput()
    self.delivered[kind] = (self.delivered[kind] or 0) + 1
    self.lifetimeDelivered[kind] = (self.lifetimeDelivered[kind] or 0) + 1
end

-- Deliveries weighted by CARGO_VALUE
function Scoring:lifetimeValue()
    local v = 0
    for kind, n in pairs(self.lifetimeDelivered) do
        v = v + n * (CARGO_VALUE[kind] or 1)
    end
    return v
end

function Scoring:addComplaint()
    self.complaints = self.complaints + 1
    self.totalComplaints = self.totalComplaints + 1
end

function Scoring:addQuit()
    self.quits = self.quits + 1
    self.totalQuits = self.totalQuits + 1
end

function Scoring:canAfford(cost)
    return self.budget >= cost
end

function Scoring:spend(cost)
    if not self:canAfford(cost) then return false end
    self.budget = self.budget - cost
    return true
end

-- Call once per second with the average hunger of working staff.
function Scoring:sampleFed(averageHunger)
    self.fedSum = self.fedSum + averageHunger
    self.fedCount = self.fedCount + 1
end

function Scoring:fedPercent()
    if self.fedCount == 0 then return 100 end
    return math.floor(self.fedSum / self.fedCount + 0.5)
end

-- Advances the quarter clock and fed sampling. Returns true when a quarter ends.
function Scoring:update(dt, averageHunger)
    self.fedTimer = self.fedTimer + dt
    if self.fedTimer >= FED_SAMPLE_SECONDS then
        self.fedTimer = self.fedTimer - FED_SAMPLE_SECONDS
        if averageHunger then self:sampleFed(averageHunger) end
    end
    self.quarterTimer = self.quarterTimer - dt
    return self.quarterTimer <= 0
end

function Scoring.grade(output, complaints, attrition)
    local score = output - complaints - QUIT_PENALTY * attrition
    for _, g in ipairs(GRADE_THRESHOLDS) do
        if score >= g[2] then return g[1] end
    end
    return 'F'
end

function Scoring:hiresFor(output, quits, workerCount)
    local hires = math.floor(output / HIRE_OUTPUT_DIVISOR)
    if hires == 0 and quits == 0 then hires = 1 end
    local room = MAX_WORKERS - workerCount
    if hires > room then hires = room end
    if hires < 0 then hires = 0 end
    return hires
end

function Scoring:closeQuarter(workerCount)
    local report = {
        quarter = self.quarter,
        output = self.output,
        food = self.delivered.food,
        logs = self.delivered.logs,
        gold = self.delivered.gold,
        fedPct = self:fedPercent(),
        complaints = self.complaints,
        attrition = self.quits,
        grade = Scoring.grade(self.output, self.complaints, self.quits),
        hires = self:hiresFor(self.output, self.quits, workerCount),
        budgetAdded = BUDGET_PER_QUARTER + self.output,
    }
    self.reports[#self.reports + 1] = report
    self.budget = self.budget + report.budgetAdded
    self.output = 0
    self.delivered = { food = 0, logs = 0, gold = 0 }
    self.complaints = 0
    self.quits = 0
    self.fedSum, self.fedCount, self.fedTimer = 0, 0, 0
    self.quarter = self.quarter + 1
    self.quarterTimer = QUARTER_SECONDS
    if self.endless then
        self.drain = self.drain + ENDLESS_DRAIN_STEP
    end
    return report
end

function Scoring:yearComplete()
    return not self.endless and self.quarter > QUARTERS_PER_GAME
end

function Scoring:startEndless()
    self.endless = true
end

function Scoring:finalScore()
    local raw = (self:lifetimeValue() - QUIT_PENALTY * self.totalQuits) * self.difficulty.multiplier
    return math.max(0, math.floor(raw))
end

return Scoring
