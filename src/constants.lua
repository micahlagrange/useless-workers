-- Morphis: every tunable number lives here.
-- Section numbers refer to docs/human-resources-design-doc.md

-- World (section 4)
TILE_SIZE       = 16
WORLD_W         = 96
WORLD_H         = 64

TILE_WATER      = 'water'
TILE_GRASS      = 'grass'
TILE_DIRT       = 'dirt'
TILE_STONE      = 'stone'
TILE_SNOW       = 'snow'
TILE_BRIDGE     = 'bridge'
TILE_BREAKROOM  = 'breakroom'
TILE_WALL       = 'wall'      -- built, blocks the way
TILE_DOOR       = 'door'      -- built, walkable, closes a wall for the enclosure check

PASSABLE        = { grass = true, dirt = true, bridge = true, breakroom = true, door = true }

-- Instead of fixed altitude bands the generator sorts every tile's altitude and
-- cuts the map into these fractions, so every seed has a playable mix.
WORLD_MIX       = { water = 0.12, grass = 0.55, stone = 0.30, snow = 0.03 }
NOISE_BASE_FREQUENCY = 1 / 11
NOISE_OCTAVES   = 3
-- Rivers run edge to edge and cut the land up, so the far banks need bridges.
RIVER_COUNT     = 2
RIVER_WIDTH_MIN = 2
RIVER_WIDTH_MAX = 3

-- Resource nodes: bushes grow food, trees give logs, ore in stone gives gold
NODE_BUSH = 'bush'
NODE_TREE = 'tree'
NODE_ORE  = 'ore'
-- the gatherer's other two: tufts of grass (they grow back) and leaf piles
-- (gone once gathered, more blow in each season, most in Autumn)
NODE_GRASS  = 'grass'
NODE_LEAVES = 'leaves'
-- little critters that hop about the meadow; a hunter catches one for meat
NODE_CRITTER = 'critter'
CRITTER_HOP_SECONDS = 2.5
HUNT_SECONDS = 3.0
NODE_KINDS = { NODE_BUSH, NODE_TREE, NODE_ORE, NODE_GRASS, NODE_LEAVES, NODE_CRITTER }
-- free play has no ore lying about: shinies are hidden in the clay
-- (SHINY_CHANCE) and found by digging. Hand built levels keep their ore.
NODES_INITIAL      = { bush = 8, tree = 8, ore = 0, grass = 10, leaves = 6, critter = 5 }
-- New growth each season. Tuned as 4 / 2 / 3 for 90 s seasons; times 300/90
-- for 300 s seasons, so as much grows per minute as before.
NODES_PER_QUARTER  = { bush = 13, tree = 7, ore = 0, grass = 6, leaves = 5, critter = 6 }
SHINY_CHANCE       = 0.08 -- share of clay and hard dirt tiles with a shiny hidden in them
LEAVES_AUTUMN      = 2    -- leaf piles blowing in at the start of Autumn, times this
GRASS_REGROW_SECONDS = 40
MAX_NODES_PER_KIND = 16
NODE_ENCLOSED_FRACTION = 0.4    -- share of nodes placed where morphis cannot reach yet
NODE_ENCLOSED_LATER    = 0.75   -- the share for nodes that grow after the start (free play)
NODE_ISLAND_FRACTION   = 0.7    -- of those, the share put across water so bridges matter
NODE_MIN_SPACING   = 3
BUSH_RIPEN_SECONDS = 20
BUSH_FIRST_RIPEN_MIN, BUSH_FIRST_RIPEN_MAX = 2, 10
TREE_REGROW_SECONDS = 45
-- ore never regrows; a mined tile turns to dirt and opens the tunnel further
CARGO_FOOD, CARGO_LOGS, CARGO_GOLD = 'food', 'logs', 'gold'
CARGO_GRASS, CARGO_LEAVES = 'grass', 'leaves'
CARGO_VALUE = { food = 1, logs = 2, gold = 3, grass = 1, leaves = 1 }   -- weight in the final score

-- Storage: delivered food is a real item on a built storage tile, one per
-- tile, closest to the break room first. Logs and gold go to the stockpile.
ITEM_FOOD        = 'food'

-- Inventory: slot 1 carries the work item (a pick, a log, a nugget),
-- slot 2 is personal (food picked up from storage). Two slots for now.
INVENTORY_SLOTS  = 2
SLOT_WORK, SLOT_PERSONAL = 1, 2

-- Breaks: after this much accumulated work a morphi heads to the break room
BREAK_AFTER_SECONDS = 45
BREAK_SECONDS       = 8        -- resting on a break room tile or the ground
BREAK_SECONDS_BED   = 4        -- resting in a bed
BED_REST_BONUS      = 1.5      -- a bed rest lasts longer before the next break is due
-- Floor spots, bins and bridges are 'build' jobs: the builder's, in free
-- play and arcade alike. A nest is 'nestwork': a gatherer or a builder.
-- Every resting morphi claims its own spot: a bed, a break room tile, or a
-- free tile next to the break room. Nobody naps on top of anybody.

-- Morphis and their roles
ROLE_FORAGER, ROLE_LUMBERJACK, ROLE_MINER = 'forager', 'lumberjack', 'miner'
ROLE_BUILDER = 'builder'
ROLE_HUNTER = 'hunter'
ROLE_CARETAKER = 'caretaker'
-- Caretakers visit a baby that needs something (CARE_POST_BELOW): a visit
-- of CARE_SECONDS plays with it, cleans it (with a tuft of grass, or not as
-- well without), feeds it a stored meal it will eat when it is hungry, and
-- tucks it in for a nap when it is sleepy. A baby feeds itself only when
-- nobody has caretaker set, or when it is very hungry.
CARE_SECONDS        = 4.0
CARE_POST_BELOW     = 75
CARE_FUN            = 45
CARE_CLEAN          = 45
CARE_FEED_BELOW     = 60
CARE_TUCK_BELOW     = 50
BABY_SELF_FEED_BELOW = 20
ROLES = {
    forager    = { label = 'Forager',    jobType = 'forage', nodeKind = NODE_BUSH, cargo = CARGO_FOOD, actionSeconds = 0.8, verb = 'picking',  sheets = { 'pupper', 'woofoof' } },
    lumberjack = { label = 'Gatherer',   jobType = 'gather', nodeKind = NODE_TREE, cargo = CARGO_LOGS, actionSeconds = 2.0, verb = 'gathering sticks', sheets = { 'twins', 'ribbit' }, alsoTakes = { 'nestwork' } },
    miner      = { label = 'Digger',     jobType = 'mine',   nodeKind = NODE_ORE,  cargo = CARGO_GOLD, actionSeconds = 2.5, verb = 'digging',   sheets = { 'cwab', 'blue' } },
    -- building is a job of its own (in free play since the player-jobs epic)
    caretaker  = { label = 'Caretaker',  jobType = 'care',   nodeKind = nil,       cargo = nil,        actionSeconds = CARE_SECONDS, verb = 'looking after a baby', sheets = { 'woofoof', 'ribbit' } },
    hunter     = { label = 'Hunter',     jobType = 'hunt',   nodeKind = NODE_CRITTER, cargo = CARGO_FOOD, actionSeconds = HUNT_SECONDS, verb = 'hunting', sheets = { 'pupper', 'woofoof' } },
    -- a baby has no job yet; this only names it on screen
    baby       = { label = 'Baby',       jobType = nil,      nodeKind = nil,       cargo = nil,        actionSeconds = 1.0, verb = 'playing', sheets = { 'pupper' } },
    builder    = { label = 'Builder',    jobType = 'build',  nodeKind = nil,       cargo = nil,        actionSeconds = 3.0, verb = 'building', sheets = { 'twins', 'ribbit' }, alsoTakes = { 'nestwork' } },
}
-- Arcade: one job each. Foragers fill bins, the builder builds, miners dig.
-- Nobody gathers: the points a level starts with are all the sticks there are.
ARCADE_ROLE = { pupper = 'forager', woofoof = 'forager', twins = 'builder', cwab = 'miner', blue = 'miner', ribbit = 'builder' }
-- The retired survival levels' hire order. Free play deals jobs instead
-- (src/jobsets.lua) and a morphi's look no longer decides its job: arrivals
-- come in this order of species, which is the order the old one-job hires
-- gave, so a seed's band looks and eats as before.
HIRE_ORDER = { ROLE_FORAGER, ROLE_LUMBERJACK, ROLE_MINER }
HIRE_SHEETS = { 'pupper', 'twins', 'cwab', 'woofoof', 'ribbit', 'blue' }
-- Every morphi eats one thing and nothing else. Food grows on bushes of
-- that kind; a forager picks any kind into storage, and everyone takes only
-- their own from it, or eats straight off a bush of their kind when hungry.
FOOD_KINDS  = { 'steak', 'fish', 'cheese', 'chili', 'candy', 'grapes' }
-- meat: the key stays 'steak'; in free play it comes only from hunting
MEAT = 'steak'
FOOD_WORDS = { steak = 'meat' }
FOOD_SPRITE = { steak = 'yp_ham.png', fish = 'yp_tuna.png', cheese = 'yp_cheese.png', chili = 'yp_chilipepper.png', candy = 'yp_candy1.png', grapes = 'yp_grapes.png' }
MORPHI_DIET = { pupper = 'steak', woofoof = 'fish', twins = 'cheese', cwab = 'chili', blue = 'candy', ribbit = 'grapes' }
MORPHI_ROLE = { pupper = 'forager', woofoof = 'forager', twins = 'lumberjack', cwab = 'miner', blue = 'miner', ribbit = 'lumberjack' }
-- grid letters for food bushes in hand built levels
FOOD_CHAR   = { k = 'steak', f = 'fish', c = 'cheese', h = 'chili', y = 'candy', g = 'grapes' }
-- Ribbit the frog is the sixth: a second builder in arcade, a lumberjack in the wilds.
MORPHI_SHEET_NAMES = { pupper = 'Pupper', woofoof = 'Woofoof', twins = 'Twins', cwab = 'Cwab', blue = 'Blob', ribbit = 'Ribbit' }

-- Workers (section 5)
HUNGER_MAX             = 100
STARTING_HUNGER        = 45     -- morphis arrive peckish, so the first thing they do is look for food
-- Hunger is shown as a status, not a bar: SATIATED above HUNGER_SATIATED,
-- FED down to HUNGER_EAT_THRESHOLD, HUNGRY below it (and looking for food,
-- and losing morale), STARVING at zero. A starving morphi eats anything,
-- even its hated food or its work item, and lasts as long again as a full
-- belly takes to empty before it starves.
HUNGER_SATIATED        = 80
HUNGER_EAT_THRESHOLD   = 20
HUNGER_STARVING        = 1
FRUIT_HUNGER_VALUE     = 55
WORKER_SPEED           = 72     -- pixels per second, 4.5 tiles per second
WORKER_SULK_SECONDS    = 3
ICK_SECONDS            = 30
COMPLAINT_COOLDOWN     = 40     -- seconds before anyone complains about the same tree again
-- Morale: hardships and hunger wear a morphi down; at zero it leaves the band.
-- Fed morphis recover slowly, and a break restores a chunk (more in a bed).
MORALE_MAX             = 100
MORALE_COMPLAINT_HIT   = 20
MORALE_HUNGRY_DRAIN    = 1.5    -- per second while hunger is below the eat threshold
MORALE_RECOVER         = 1.0    -- per second while fed
MORALE_BREAK_BONUS     = 10
MORALE_BED_BONUS       = 25
MORALE_LOW             = 30     -- below this the morphi grumbles and the HUD warns
DECIDE_INTERVAL        = 0.5
JOB_PATH_TRIES         = 8      -- nearest candidates a morphi will try to path to before giving up this tick
HARVEST_SECONDS        = 0.8
EAT_SECONDS            = 1.0
WANDER_RADIUS          = 3
MAX_WORKERS            = 12
-- Babies. Free play starts with one, Morphi, in the home nest. A baby does
-- no work: it eats, naps, toddles about near home and grows up after
-- BABY_SECONDS. Its needs (0-100) run down and only care fills fun and
-- clean; how well it was looked after (its care score) sets its mood when
-- it grows up.
START_BABIES       = 1
FIRST_BABY_NAME    = 'Morphi'
BABY_SECONDS       = 300
BABY_NEED_DRAIN    = { fun = 0.2, clean = 0.12, sleep = 0.25 }  -- per second
BABY_NAP_BELOW     = 40     -- sleep under this: off for a nap
BABY_NAP_RATE      = 6      -- sleep regained per second napping
BABY_WANDER        = 2      -- tiles from home a baby toddles
BABY_SCALE         = 0.6    -- drawn this big
BABY_MORALE_MIN    = 40     -- a neglected baby still grows up with this much morale

-- Player tools (section 6). The player designates work; morphis do it.
ABILITY_SELECT  = 'select'
ABILITY_MINE    = 'mine'      -- drag a rectangle over stone, miners dig it when they can reach it
ABILITY_STORAGE = 'storage'   -- place a free floor storage spot, holds one item
ABILITY_BIN     = 'bin'       -- place a bin site (costs logs), holds four items
ABILITY_BED     = 'bed'       -- place a bed site; a bed is a quicker, better break
ABILITY_BRIDGE  = 'bridge'    -- drag a line over water, any idle morphi builds it tile by tile
ABILITY_WALL    = 'wall'      -- place a wall site (costs a log); built, it blocks the way
ABILITY_DOOR    = 'door'      -- place a door site (costs a log); walkable, counts as wall for enclosure
-- each mode has its own tool bar; main sets ABILITY_ORDER when a game starts
TOOLS_SURVIVAL  = { ABILITY_SELECT, ABILITY_MINE, ABILITY_STORAGE, ABILITY_BIN, ABILITY_BED, ABILITY_BRIDGE }
TOOLS_ARCADE    = { ABILITY_SELECT, ABILITY_MINE, ABILITY_STORAGE, ABILITY_BIN, ABILITY_WALL, ABILITY_DOOR, ABILITY_BRIDGE }
ABILITY_ORDER   = TOOLS_ARCADE
-- the words on the tool buttons (the little-blob meadow voice: a STASH is a
-- leaf mat for one thing, a BASKET holds four, a NEST is where they nap)
ABILITY_LABEL   = { select = 'SELECT', mine = 'DIG', storage = 'STASH', bin = 'BASKET', bed = 'NEST', wall = 'WALL', door = 'DOOR', bridge = 'BRIDGE' }
-- Storage: a floor spot is free and holds one item. A bin costs logs and
-- holds four, shown in the order they came in, quadrant by quadrant.
STORAGE_FLOOR_CAPACITY = 1
STORAGE_BIN_CAPACITY   = 4
-- Building consumes the stockpile at the break room. Mining costs only time.
COSTS = {
    storage = { logs = 0 },
    bin     = { logs = 1 },
    wall    = { logs = 1 },
    door    = { logs = 1 },
    bed     = { logs = 2 },
    bridge  = { logs = 1 },   -- per water tile
}
-- Free play builds nests, not furniture: a NEST is woven from sticks, grass
-- and leaves, a BASKET from grass, a STASH is a free leaf mat, a bridge is
-- sticks. Hand built levels keep COSTS above, in points (sticks).
FREE_COSTS = {
    storage = {},
    bin     = { grass = 1 },
    bed     = { logs = 2, grass = 2, leaves = 1 },
    bridge  = { logs = 1 },   -- per water tile
    wall    = { logs = 1 },
    door    = { logs = 1 },
}
-- What a kind of site costs in this world.
function costOf(world, kind)
    local t = (world and world.wilds) and FREE_COSTS or COSTS
    return t[kind] or {}
end
-- A cost in words, most first: '2 sticks 2 grass 1 leaf'. Empty for free.
local MATERIAL_ORDER = { 'logs', 'grass', 'leaves', 'gold' }
local MATERIAL_WORDS = { logs = { 'stick', 'sticks' }, grass = { 'grass', 'grass' }, leaves = { 'leaf', 'leaves' }, gold = { 'shiny', 'shinies' } }
function costWords(cost, sep)
    local parts = {}
    for _, k in ipairs(MATERIAL_ORDER) do
        local n = cost[k] or 0
        if n > 0 then parts[#parts + 1] = n .. ' ' .. MATERIAL_WORDS[k][n == 1 and 1 or 2] end
    end
    return table.concat(parts, sep or ' ')
end
-- the site kinds by their new names (the keys stay 'bed', 'bin', 'storage')
SITE_NEST, ABILITY_NEST = 'bed', 'bed'
STARTING_STOCK  = { logs = 4, gold = 0, grass = 0, leaves = 0 }
BUILD_SECONDS   = 3.0
LINE_MAX_LENGTH = 12
MINE_MAX_TILES  = 60          -- per drag, keeps a wild rectangle from posting hundreds of jobs
MINE_TILES_PER_TRIP = 6       -- a miner lets go of an area after this many tiles and reconsiders

SITE_MINE, SITE_STORAGE, SITE_BIN, SITE_BRIDGE, SITE_BED = 'mine', 'storage', 'bin', 'bridge', 'bed'
SITE_WALL, SITE_DOOR = 'wall', 'door'
SITE_FOR_TOOL = { storage = SITE_STORAGE, bin = SITE_BIN, bed = SITE_BED, wall = SITE_WALL, door = SITE_DOOR }
SITE_CAPACITY = { storage = STORAGE_FLOOR_CAPACITY, bin = STORAGE_BIN_CAPACITY }
-- Arcade: no hunger, no morale, no breaks. Every morphi eats once and the
-- level is won when they all have. A level lists what has to be true before
-- anyone will eat: bins (picky, eat only from a bin), floors (one living
-- space tile per morphi), enclosed (walls all round the floors, a door to
-- get in), binsInside (every bin behind the walls).
ARCADE_NEED_ORDER = { 'bins', 'floors', 'enclosed', 'binsInside' }
-- Arcade budgets: each level lists points per difficulty. Easy pays for the
-- obvious build twice over, so a heap of mistakes still wins; hard pays for
-- it once with a log or two to spare. Par sits a little above the cheapest
-- build, so a sharp eye can come in under it.
ARCADE_DIFFICULTIES = {
    { key = 'easy',   name = 'Easy',   blurb = 'points to burn, build it twice if you like' },
    { key = 'normal', name = 'Normal', blurb = 'room for a few mistakes' },
    { key = 'hard',   name = 'Hard',   blurb = 'the obvious build and a stick or two to spare' },
}
DEFAULT_ARCADE_DIFFICULTY = 1

-- Seasons and the tally. A year is four seasons; the wilds grade each one.
-- Internally a season is still a 'quarter' and migrants are 'hires'.
-- A season is five minutes (it was 90 s). What happens per second (hunger,
-- morale, work, boredom, trades) is unchanged; what comes once a season
-- (new growth, migrants, the endless drain step, the grade) is rescaled
-- below so a season plays about as before, only longer.
QUARTER_SECONDS     = 300
QUARTERS_PER_GAME   = 4
SEASON_NAMES        = { 'Spring', 'Summer', 'Autumn', 'Winter' }
HIRE_OUTPUT_DIVISOR = 5
QUIT_PENALTY        = 3
FED_SAMPLE_SECONDS  = 1
-- After the first year hunger drains faster each season. 0.1 with 90 s
-- seasons; at 300 s a season holds 3.3 times the hunger, and 0.05 keeps the
-- year the bands begin to fall where it was (tools/bench.py).
ENDLESS_DRAIN_STEP  = 0.05
-- Season grades score output - complaints - 3 x quits, which pile up per
-- second: 16 / 11 / 6 / 2 for 90 s seasons, times 300/90.
GRADE_THRESHOLDS    = { { 'S', 53 }, { 'A', 37 }, { 'B', 20 }, { 'C', 7 } } -- below the last one is an F
-- The run's audit log (src/stats.lua): a day is a slice of a season, and
-- the player's note on an export is kept short. Milestones are never two
-- closer than MILESTONE_GAP_DAYS (three seasons), so about one a year.
DAYS_PER_SEASON     = 9
DAY_SECONDS         = QUARTER_SECONDS / DAYS_PER_SEASON
-- 2: every morphi in a day's band has main, neutral, disliked and job (what
-- it is working at), and a day row has idleByMain. A format 1 run has only
-- role, which is its main job.
STATS_FORMAT        = 2
STATS_BLURB_MAX     = 200
MILESTONE_GAP_DAYS  = DAYS_PER_SEASON * 3

-- startHunger: how fed a morphi arrives (a little less for each one after
-- the first, so the band does not all get hungry at the same moment).
-- Free play offers only the first for now (FREE_PLAY_DIFFICULTIES) while it
-- is being tuned; the rest are kept for when there are more hardships.
-- Free play starts with three, their jobs dealt at random (src/jobsets.lua); the
-- other wilds keep their numbers until the ladder is redone.
DIFFICULTIES = {
    { name = 'Sunny meadow', drain = 0.5, workers = 3, multiplier = 0.5, startHunger = 85 },
    { name = 'Breezy meadow', drain = 0.7, workers = 4, multiplier = 1.0, startHunger = 60 },
    { name = 'Chilly meadow', drain = 0.95, workers = 3, multiplier = 1.5, startHunger = 50 },
    { name = 'Stormy meadow', drain = 1.2, workers = 2, multiplier = 2.0, startHunger = 45 },
}
FREE_PLAY_DIFFICULTIES = 1
DEFAULT_DIFFICULTY = 1
-- Migrants are capped per season, by year: a rush of new mouths, each with
-- its own food, starved year one.
-- 2 / 3 / 4 with 90 s seasons; one more each at 300 s so a newcomer still
-- turns up every couple of minutes and a band that loses morphis over a
-- long season can make it up (more than this did not help, tools/bench.py).
MIGRANTS_PER_SEASON = { 3, 4, 5 }
-- Free play tastes. Every species loves one food (MORPHI_DIET), hates one,
-- and will eat the rest. A meal is worth more hunger the better it is
-- liked; a loved meal cheers a morphi up and a hated one, eaten only when
-- starving, gets it down.
MORPHI_HATES = { pupper = 'grapes', woofoof = 'chili', twins = 'candy', cwab = 'fish', blue = 'steak', ribbit = 'cheese' }
FOOD_VALUE   = { loved = 70, fine = 35, hated = 20 }
MORALE_LOVED_MEAL = 5
MORALE_HATED_MEAL = 10
-- Free play: a specialist with nothing it can get at to work on gets bored,
-- and that is a hardship. The game is opening the way for them.
BORED_SECONDS     = 20
MORALE_BORED_HIT  = 18
-- Free play: a bush gives this many pickings, then withers. New ones grow
-- mostly where nobody can get at them yet.
BUSH_PICKINGS     = 8
-- Gold buys happy thoughts, through a trade. A morphi finishing a rest at
-- camp with morale under TRADE_BELOW offers one and waits there up to
-- TRADE_WAIT_SECONDS; the next to rest or stand about at camp takes it up.
-- It only starts with a gold piece in the stockpile and a stored meal for
-- each: the other's loved food if there is any (a gift), else anything
-- they will eat. They chat at camp for TRADE_SECONDS, hunger on hold, and
-- eat together halfway. A deal is happy thoughts for both, more per gift.
TRADE_BELOW         = 70
TRADE_WAIT_SECONDS  = 20
TRADE_SECONDS       = 40
MORALE_TRADE_BASE   = 20
MORALE_GIFT         = 15
-- What two morphis say over a trade, a line every few seconds, turn about.
TRADE_CHAT = {
    'nice day', 'lovely pebble', 'hmm...', 'how much?', 'too much!', 'meet me halfway',
    'deal?', 'not yet', 'shiny...', 'go on then', 'and a hug', 'fine, fine',
}
DEFAULT_SEED       = 'PUPPER'

-- Colors, hex strings; the same palette as control-the-environment plus water and snow
GRASS_COLORS     = { '#a9c97a', '#9dbf6f', '#b3d185' }
DIRT_COLORS      = { '#d6bc8e', '#cdb184', '#dcc59b' }
STONE_COLORS     = { '#c98f6e', '#bf8566', '#d19a79', '#b87e60' }
WATER_COLORS     = { '#8cc4dc', '#82bbd6', '#96cbe1' }
SNOW_COLORS      = { '#a67c5b', '#9d7354', '#ae8562' }
BRIDGE_COLORS    = { '#b48a5c', '#a87f53', '#bf9566' }
BREAKROOM_COLORS = { '#e8d9a6', '#e0cf9a' }
WALL_COLORS      = { '#6b4f2a', '#5e4524' }
DOOR_COLORS      = { '#a6823f', '#9a7838' }
TILE_PALETTE     = {
    grass = GRASS_COLORS, dirt = DIRT_COLORS, stone = STONE_COLORS, water = WATER_COLORS,
    snow = SNOW_COLORS, bridge = BRIDGE_COLORS, breakroom = BREAKROOM_COLORS,
    wall = WALL_COLORS, door = DOOR_COLORS,
}

MORPHI_NAMES = {
    'Dave', 'Priya', 'Kenji', 'Marisol', 'Tobias', 'Ngozi', 'Hank', 'Lupe',
    'Sven', 'Aiko', 'Bartholomew', 'Deb', 'Gus', 'Fatima', 'Rex', 'Wanda',
}
