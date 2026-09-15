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
HUNGER_STARVING        = 12     -- a starving carrier eats its food or drops its cargo
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

-- Player tools (section 6)
ABILITY_SELECT  = 'select'
ABILITY_DIG     = 'dig'
ABILITY_EXPLODE = 'explode'
ABILITY_LINE    = 'line'
ABILITY_MEMO    = 'memo'
ABILITY_ORDER   = { ABILITY_SELECT, ABILITY_DIG, ABILITY_EXPLODE, ABILITY_LINE, ABILITY_MEMO }
ABILITY_COST    = { select = 0, dig = 1, explode = 4, line = 1, memo = 2 }
ABILITY_LABEL   = { select = 'SELECT', dig = 'DIG', explode = 'EXPLODE', line = 'BRIDGE', memo = 'MEMO' }
EXPLODE_RADIUS  = 1             -- 1 means a 3 by 3 blast
MEMO_RADIUS     = 5
LINE_MAX_LENGTH = 12

-- Economy and scoring (section 7)
QUARTER_SECONDS     = 90
QUARTERS_PER_GAME   = 4
BUDGET_PER_QUARTER  = 10
BUDGET_START        = 10
HIRE_OUTPUT_DIVISOR = 5
QUIT_PENALTY        = 3
FED_SAMPLE_SECONDS  = 1
ENDLESS_DRAIN_STEP  = 0.1
GRADE_THRESHOLDS    = { { 'S', 16 }, { 'A', 11 }, { 'B', 6 }, { 'C', 2 } } -- below the last one is an F

DIFFICULTIES = {
    { name = 'Intern',        drain = 0.9, workers = 5, multiplier = 0.5 },
    { name = 'Manager',       drain = 1.2, workers = 4, multiplier = 1.0 },
    { name = 'Director',      drain = 1.6, workers = 3, multiplier = 1.5 },
    { name = 'Unlimited PTO', drain = 2.0, workers = 2, multiplier = 2.0 },
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
