-- Five hand built levels. Each adds one morphi and the one food it eats.
-- The maps are drawn so the obvious fix (bridge straight across) always
-- works, and a sharper eye spends far fewer points: a narrow crossing, a
-- thin wall a miner can open for free, logs from a nearby grove.
--
-- Grid letters: '.' grass  '#' stone  '~' water  'B' camp (2x2)  'T' tree
-- 'G' gold ore in stone  'k' steak  'f' fish  'c' cheese  'h' chili  'y' candy
--
-- obvious / clever: designations a test lays down to prove both solutions
-- keep everyone alive for the whole level. bridge = {x1, y1, x2, y2},
-- floor = {x, y}, mine = {x1, y1, x2, y2}.
require('src.constants')

local Levels = {}

Levels[1] = {
    name = 'The forest',
    blurb = 'Pupper eats steak. The steak is across the river.',
    intro = 'Pupper only eats steak, and the steak grows across the river. BRIDGE it. The river is not the same width everywhere.',
    morphis = { 'pupper' },
    points = 6, par = 1, seconds = 90, drain = 0.6, hunger = 40,
    grid = {
        '..T..........~~~.......T........',
        '..............~.............T...',
        'T............~~~......T.........',
        '.........T...~~~................',
        '.............~~~...k............',
        '..BB.........~~~..........T.....',
        '..BB.T.......~~~.......k........',
        '.............~~~....T...........',
        '....T........~~~..........k.....',
        '.............~~~................',
        '......T......~~~.....T..........',
        '.............~~~................',
        '..T..........~~~..........T.....',
        '.............~~~................',
    },
    obvious = { bridge = { { 14, 7, 16, 7 } }, floor = { { 5, 6 }, { 5, 7 } } },
    clever = { bridge = { { 15, 2, 15, 2 } } },
}

Levels[2] = {
    name = 'Two rivers',
    blurb = 'Woofoof joins and only eats fish. Two rivers, two diets.',
    intro = 'Woofoof eats fish and nothing else. Steak lies past the first river, fish past the second. Each river has a narrow spot.',
    morphis = { 'pupper', 'woofoof' },
    points = 8, par = 2, seconds = 90, drain = 0.65, hunger = 55,
    grid = {
        '............~~~...........~.....',
        '.T..........~~~..k.......~~.....',
        '............~~~..........~~...f.',
        '............~~~....k.....~~.....',
        '..BB........~~~..........~~.....',
        '..BB........~~~.......T..~~..f..',
        '............~~~..........~~.....',
        '....T.......~~~.k........~~.....',
        '............~~~..........~~...f.',
        '............~~~..........~~.....',
        '............~~~....T.....~~.....',
        '.............~...........~~.....',
        '............~~~..k.......~~..f..',
        '............~~~..........~~.....',
    },
    obvious = { bridge = { { 13, 5, 15, 5 }, { 26, 5, 27, 5 } }, floor = { { 5, 5 }, { 5, 6 } } },
    clever = { bridge = { { 14, 12, 14, 12 }, { 27, 1, 27, 1 } } },
}

Levels[3] = {
    name = 'Timber',
    blurb = 'Twins joins and only eats cheese. Few points, but trees near camp.',
    intro = 'Twins eats cheese and cuts trees into logs, and logs are points. You start with 4. The river is thin in one place.',
    morphis = { 'pupper', 'woofoof', 'twins' },
    points = 4, par = 1, seconds = 100, drain = 0.7, hunger = 48,
    grid = {
        '...k.......f........c.......k...',
        '........c.......k........f......',
        '....f.........c..........c......',
        '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
        '~~~~~~~~~~~~~~~~~~~~~~~~~~~.~~~~',
        '................................',
        '...T.....T......................',
        '.....BB.........T...............',
        '..T..BB.............T...........',
        '.......T........................',
        '....T...........................',
        '................................',
    },
    obvious = { bridge = { { 6, 4, 6, 5 } }, floor = { { 8, 8 }, { 8, 9 } } },
    clever = { bridge = { { 28, 4, 28, 4 } }, floor = { { 8, 8 } } },
}

Levels[4] = {
    name = 'Stone',
    blurb = 'Cwab joins, eats chili, and mines. Stone is free to dig.',
    intro = 'Cwab eats chili and can MINE stone. Marked stone costs nothing but time. The walls are thinner than they look.',
    morphis = { 'pupper', 'woofoof', 'twins', 'cwab' },
    points = 6, par = 0, seconds = 100, drain = 0.75, hunger = 45,
    grid = {
        '############...............~~~~~',
        '#k..h..c...#...............~~~~~',
        '#..........#...............~~~~~',
        '#.f...k....#...............~~~~~',
        '#..h....f..#.......T.......~~~~~',
        '####.#######...............~~~~~',
        '####G#######...............~~~~~',
        '####.#######....BB.........~~~~~',
        '############....BB....T....~~~~~',
        '............................~~~~',
        '......T.....................~~~~',
        '...............T............~~~~',
        '..........................h.~~~~',
        '......................h..k..~~~~',
        '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
        '.c....f.....c...h....f....c....y',
    },
    obvious = { bridge = { { 20, 15, 20, 15 } }, floor = { { 15, 8 }, { 15, 9 } } },
    clever = { mine = { { 5, 6, 5, 9 } } },
}

Levels[5] = {
    name = 'The wilds',
    blurb = 'Blob joins and only eats candy. Everything at once.',
    intro = 'Blob eats candy. Five mouths, five foods, rivers and stone in the way. Bridges cost, mining is free, trees are points.',
    morphis = { 'pupper', 'woofoof', 'twins', 'cwab', 'blue' },
    points = 8, par = 3, seconds = 120, drain = 0.8, hunger = 45,
    grid = {
        'y.........~~~.......................##############',
        '.....y....~~~..........k............#......c.....#',
        '..y.......~.~......k................#..c.........#',
        '..........~~~...........k...........#.......c....#',
        '~~~~~~~~~~~~~.......................#............#',
        '~~~~~~~~~~~~~.......T...............##############',
        '..................................................',
        '..........................BB.....T................',
        '........T.................BB......................',
        '....................T.............................',
        '..................................................',
        '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.~~~~~~~~~~~~~~~~~~',
        '~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~',
        '......f.........f.............h.......h...........',
        '...f..........f..........h.........h..............',
        '..........f...................h...................',
    },
    obvious = { bridge = { { 11, 2, 13, 2 }, { 27, 12, 27, 13 } }, floor = { { 25, 8 }, { 25, 9 }, { 30, 8 } }, mine = { { 42, 6, 42, 6 } } },
    clever = { bridge = { { 11, 3, 11, 3 }, { 13, 3, 13, 3 }, { 32, 13, 32, 13 } }, mine = { { 42, 6, 42, 6 } }, floor = { { 25, 8 } } },
}

return Levels
