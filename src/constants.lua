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
NODE_KINDS = { NODE_BUSH, NODE_TREE, NODE_ORE }
NODES_INITIAL      = { bush = 8, tree = 8, ore = 6 }
NODES_PER_QUARTER  = { bush = 4, tree = 2, ore = 3 }
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
CARGO_VALUE = { food = 1, logs = 2, gold = 3 }   -- weight in the final score

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
-- Floor spots, bins and bridges are 'build' jobs anyone takes. A bed is
-- 'woodwork': only a lumberjack builds it.
-- Every resting morphi claims its own spot: a bed, a break room tile, or a
-- free tile next to the break room. Nobody naps on top of anybody.

-- Morphis and their roles
ROLE_FORAGER, ROLE_LUMBERJACK, ROLE_MINER = 'forager', 'lumberjack', 'miner'
ROLE_BUILDER = 'builder'
ROLES = {
    forager    = { label = 'Forager',    jobType = 'forage', nodeKind = NODE_BUSH, cargo = CARGO_FOOD, actionSeconds = 0.8, verb = 'picking',  sheets = { 'pupper', 'woofoof' } },
    lumberjack = { label = 'Lumberjack', jobType = 'chop',   nodeKind = NODE_TREE, cargo = CARGO_LOGS, actionSeconds = 2.0, verb = 'chopping', sheets = { 'twins', 'ribbit' }, alsoTakes = { 'woodwork' } },
    miner      = { label = 'Miner',      jobType = 'mine',   nodeKind = NODE_ORE,  cargo = CARGO_GOLD, actionSeconds = 2.5, verb = 'mining',   sheets = { 'cwab', 'blue' } },
    -- arcade only: building is a job of its own
    builder    = { label = 'Builder',    jobType = 'build',  nodeKind = nil,       cargo = nil,        actionSeconds = 3.0, verb = 'building', sheets = { 'twins', 'ribbit' }, alsoTakes = { 'woodwork' } },
}
-- Arcade: one job each. Foragers fill bins, the builder builds, miners dig.
-- Nobody chops: the points a level starts with are all the logs there are.
ARCADE_ROLE = { pupper = 'forager', woofoof = 'forager', twins = 'builder', cwab = 'miner', blue = 'miner', ribbit = 'builder' }
HIRE_ORDER = { ROLE_FORAGER, ROLE_LUMBERJACK, ROLE_MINER }
-- Every morphi eats one thing and nothing else. Food grows on bushes of
-- that kind; a forager picks any kind into storage, and everyone takes only
-- their own from it, or eats straight off a bush of their kind when hungry.
FOOD_KINDS  = { 'steak', 'fish', 'cheese', 'chili', 'candy', 'grapes' }
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
WORKER_PATIENCE        = 24     -- seconds walking toward a tree before giving up
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
ABILITY_LABEL   = { select = 'SELECT', mine = 'MINE', storage = 'FLOOR', bin = 'BIN', bed = 'BED', wall = 'WALL', door = 'DOOR', bridge = 'BRIDGE' }
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
STARTING_STOCK  = { logs = 4, gold = 0 }
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
    { key = 'hard',   name = 'Hard',   blurb = 'the obvious build and a log or two to spare' },
}
DEFAULT_ARCADE_DIFFICULTY = 1

-- Seasons and the tally. A year is four seasons; the wilds grade each one.
-- Internally a season is still a 'quarter' and migrants are 'hires'.
QUARTER_SECONDS     = 90
QUARTERS_PER_GAME   = 4
SEASON_NAMES        = { 'Spring', 'Summer', 'Autumn', 'Winter' }
HIRE_OUTPUT_DIVISOR = 5
QUIT_PENALTY        = 3
FED_SAMPLE_SECONDS  = 1
ENDLESS_DRAIN_STEP  = 0.1
GRADE_THRESHOLDS    = { { 'S', 16 }, { 'A', 11 }, { 'B', 6 }, { 'C', 2 } } -- below the last one is an F
-- The run's audit log (src/stats.lua): a day is a slice of a season, and
-- the player's note on an export is kept short. Milestones are never two
-- closer than MILESTONE_GAP_DAYS (three seasons), so about one a year.
DAYS_PER_SEASON     = 9
DAY_SECONDS         = QUARTER_SECONDS / DAYS_PER_SEASON
STATS_FORMAT        = 1
STATS_BLURB_MAX     = 200
MILESTONE_GAP_DAYS  = DAYS_PER_SEASON * 3

-- startHunger: how fed a morphi arrives (a little less for each one after
-- the first, so the band does not all get hungry at the same moment).
-- Free play offers only the first for now (FREE_PLAY_DIFFICULTIES) while it
-- is being tuned; the rest are kept for when there are more hardships.
DIFFICULTIES = {
    { name = 'Mild wilds',   drain = 0.5, workers = 5, multiplier = 0.5, startHunger = 85 },
    { name = 'Harsh wilds',  drain = 0.7, workers = 4, multiplier = 1.0, startHunger = 60 },
    { name = 'Bitter wilds', drain = 0.95, workers = 3, multiplier = 1.5, startHunger = 50 },
    { name = 'Cruel wilds',  drain = 1.2, workers = 2, multiplier = 2.0, startHunger = 45 },
}
FREE_PLAY_DIFFICULTIES = 1
DEFAULT_DIFFICULTY = 1
-- Migrants are capped per season, by year: a rush of new mouths, each with
-- its own food, starved year one.
MIGRANTS_PER_SEASON = { 2, 3, 4 }
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
GRASS_COLORS     = { '#94a35b', '#849151', '#737f47' }
DIRT_COLORS      = { '#a38f5b', '#917f51', '#7f6f47' }
STONE_COLORS     = { '#6d6a64', '#625f5a', '#58554f', '#77746d' }
WATER_COLORS     = { '#5f8fa8', '#5786a0', '#4f7d97' }
SNOW_COLORS      = { '#e9ecf0', '#dfe3e8', '#d3d8de' }
BRIDGE_COLORS    = { '#8a6f3f', '#7d6437', '#96773f' }
BREAKROOM_COLORS = { '#c9b27a', '#bfa870' }
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
