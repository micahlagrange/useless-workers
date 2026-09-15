-- Human Resources: every tunable number lives here.
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

PASSABLE        = { grass = true, dirt = true, bridge = true, breakroom = true }

-- Instead of fixed altitude bands the generator sorts every tile's altitude and
-- cuts the map into these fractions, so every seed has a playable mix.
WORLD_MIX       = { water = 0.12, grass = 0.55, stone = 0.30, snow = 0.03 }
NOISE_BASE_FREQUENCY = 1 / 11
NOISE_OCTAVES   = 3

-- Resource nodes: bushes grow food, trees give logs, ore in stone gives gold
NODE_BUSH = 'bush'
NODE_TREE = 'tree'
NODE_ORE  = 'ore'
NODE_KINDS = { NODE_BUSH, NODE_TREE, NODE_ORE }
NODES_INITIAL      = { bush = 8, tree = 8, ore = 6 }
NODES_PER_QUARTER  = { bush = 2, tree = 2, ore = 3 }
MAX_NODES_PER_KIND = 16
NODE_ENCLOSED_FRACTION = 0.34   -- share of nodes placed where morphis cannot reach yet
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
BREAK_SECONDS       = 8

-- Morphis and their roles
ROLE_FORAGER, ROLE_LUMBERJACK, ROLE_MINER = 'forager', 'lumberjack', 'miner'
ROLES = {
    forager    = { label = 'Forager',    jobType = 'forage', nodeKind = NODE_BUSH, cargo = CARGO_FOOD, actionSeconds = 0.8, verb = 'picking',  sheets = { 'pupper', 'woofoof' } },
    lumberjack = { label = 'Lumberjack', jobType = 'chop',   nodeKind = NODE_TREE, cargo = CARGO_LOGS, actionSeconds = 2.0, verb = 'chopping', sheets = { 'twins' } },
    miner      = { label = 'Miner',      jobType = 'mine',   nodeKind = NODE_ORE,  cargo = CARGO_GOLD, actionSeconds = 2.5, verb = 'mining',   sheets = { 'cwab', 'blue' } },
}
HIRE_ORDER = { ROLE_FORAGER, ROLE_LUMBERJACK, ROLE_MINER }
MORPHI_SHEET_NAMES = { pupper = 'Pupper', woofoof = 'Woofoof', twins = 'Twins', cwab = 'Cwab', blue = 'Blob' }

-- Workers (section 5)
HUNGER_MAX             = 100
HUNGER_EAT_THRESHOLD   = 30
HUNGER_STARVING        = 12     -- a starving morphi eats even its work item if it is food, or drops its cargo
FRUIT_HUNGER_VALUE     = 55
WORKER_SPEED           = 72     -- pixels per second, 4.5 tiles per second
WORKER_PATIENCE        = 24     -- seconds walking toward a tree before giving up
WORKER_SULK_SECONDS    = 3
ICK_SECONDS            = 30
COMPLAINT_COOLDOWN     = 40     -- seconds before anyone complains about the same tree again
DECIDE_INTERVAL        = 0.5
HARVEST_SECONDS        = 0.8
EAT_SECONDS            = 1.0
WANDER_RADIUS          = 3
MAX_WORKERS            = 12

-- Player tools (section 6). The player designates work; morphis do it.
ABILITY_SELECT  = 'select'
ABILITY_MINE    = 'mine'      -- drag a rectangle over stone, miners dig it when they can reach it
ABILITY_STORAGE = 'storage'   -- place a storage tile site, any idle morphi builds it
ABILITY_BRIDGE  = 'bridge'    -- drag a line over water, any idle morphi builds it tile by tile
ABILITY_MEMO    = 'memo'
ABILITY_ORDER   = { ABILITY_SELECT, ABILITY_MINE, ABILITY_STORAGE, ABILITY_BRIDGE, ABILITY_MEMO }
ABILITY_LABEL   = { select = 'SELECT', mine = 'MINE', storage = 'STORAGE', bridge = 'BRIDGE', memo = 'MEMO' }
-- Building consumes the stockpile at the break room. Mining costs only time.
COSTS = {
    storage = { logs = 2 },
    bridge  = { logs = 1 },   -- per water tile
    memo    = { gold = 1 },
}
STARTING_STOCK  = { logs = 4, gold = 0 }
BUILD_SECONDS   = 3.0
MEMO_RADIUS     = 5
LINE_MAX_LENGTH = 12
MINE_MAX_TILES  = 60          -- per drag, keeps a wild rectangle from posting hundreds of jobs

SITE_MINE, SITE_STORAGE, SITE_BRIDGE = 'mine', 'storage', 'bridge'

-- Economy and scoring (section 7)
QUARTER_SECONDS     = 90
QUARTERS_PER_GAME   = 4
HIRE_OUTPUT_DIVISOR = 5
QUIT_PENALTY        = 3
FED_SAMPLE_SECONDS  = 1
ENDLESS_DRAIN_STEP  = 0.1
GRADE_THRESHOLDS    = { { 'S', 16 }, { 'A', 11 }, { 'B', 6 }, { 'C', 2 } } -- below the last one is an F

DIFFICULTIES = {
    { name = 'Intern',        drain = 0.5, workers = 5, multiplier = 0.5 },
    { name = 'Manager',       drain = 0.7, workers = 4, multiplier = 1.0 },
    { name = 'Director',      drain = 0.95, workers = 3, multiplier = 1.5 },
    { name = 'Unlimited PTO', drain = 1.2, workers = 2, multiplier = 2.0 },
}
DEFAULT_DIFFICULTY = 2
DEFAULT_SEED       = '987'

-- Colors, hex strings; the same palette as control-the-environment plus water and snow
GRASS_COLORS     = { '#94a35b', '#849151', '#737f47' }
DIRT_COLORS      = { '#a38f5b', '#917f51', '#7f6f47' }
STONE_COLORS     = { '#3b3b3b', '#2f2f2f', '#232323', '#4f4f4f' }
WATER_COLORS     = { '#5f8fa8', '#5786a0', '#4f7d97' }
SNOW_COLORS      = { '#e9ecf0', '#dfe3e8', '#d3d8de' }
BRIDGE_COLORS    = { '#8a6f3f', '#7d6437', '#96773f' }
BREAKROOM_COLORS = { '#c9b27a', '#bfa870' }
TILE_PALETTE     = {
    grass = GRASS_COLORS, dirt = DIRT_COLORS, stone = STONE_COLORS, water = WATER_COLORS,
    snow = SNOW_COLORS, bridge = BRIDGE_COLORS, breakroom = BREAKROOM_COLORS,
}

MORPHI_NAMES = {
    'Dave', 'Priya', 'Kenji', 'Marisol', 'Tobias', 'Ngozi', 'Hank', 'Lupe',
    'Sven', 'Aiko', 'Bartholomew', 'Deb', 'Gus', 'Fatima', 'Rex', 'Wanda',
}
