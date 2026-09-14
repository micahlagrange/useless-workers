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

-- Trees
TREES_INITIAL          = 12
TREES_PER_QUARTER      = 3
MAX_TREES              = 24
TREE_ENCLOSED_FRACTION = 0.34   -- share of trees planted in pockets the workers cannot reach yet
TREE_RIPEN_SECONDS     = 20
TREE_FIRST_RIPEN_MIN   = 2
TREE_FIRST_RIPEN_MAX   = 10
TREE_MIN_SPACING       = 3

-- Workers (section 5)
HUNGER_MAX             = 100
HUNGER_EAT_THRESHOLD   = 30
HUNGER_STARVING        = 12     -- a carrier this hungry eats the fruit instead of delivering it
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

WORKER_NAMES = {
    'Dave', 'Priya', 'Kenji', 'Marisol', 'Tobias', 'Ngozi', 'Hank', 'Lupe',
    'Sven', 'Aiko', 'Bartholomew', 'Deb', 'Gus', 'Fatima', 'Rex', 'Wanda',
}
WORKER_TINTS = {
    '#7fb3e6', '#f0a35e', '#8fd18f', '#e68ac2', '#f2e07a', '#b39ddb',
    '#ff8a80', '#80deea', '#c5e1a5', '#ffcc80', '#bcaaa4', '#eeeeee',
}
WORKER_TINT_NAMES = {
    'blue', 'orange', 'green', 'pink', 'yellow', 'purple',
    'red', 'teal', 'lime', 'peach', 'brown', 'white',
}
