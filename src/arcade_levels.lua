-- Six arcade levels. Nobody gets hungry; every morphi just wants one meal,
-- and the level is won when they have all had it. Each level adds one more
-- thing they insist on before they will eat, and the maps are drawn so the
-- obvious build works and a sharper eye spends far less: a narrow crossing,
-- a wall of stone a miner can open for free, a nook that needs two walls
-- and a door instead of fourteen.
--
-- Grid letters: '.' grass  '#' stone  '~' water  'B' camp (2x2)
-- 'k' steak  'f' fish  'c' cheese  'h' chili  'y' candy (any food will do here)
--
-- needs: what has to be true before anyone eats, see ARCADE_NEED_ORDER.
-- obvious / clever: designations a test lays down to prove both solutions
-- feed everyone. bridge = {x1, y1, x2, y2}, mine = {x1, y1, x2, y2},
-- floor / bin / wall / door = {x, y}.
--
-- points: logs to start with per difficulty (see ARCADE_DIFFICULTIES).
-- par: a little above the cheapest build, so it can be beaten.
require('src.constants')

local Levels = {}

Levels[1] = {
    name = 'The meadow',
    blurb = 'Pupper wants a meal. The steak is right there.',
    intro = 'Pupper only wants to eat once. Nothing is in the way. Watch, and see how a morphi gets on when nothing is asked of you.',
    morphis = { 'pupper' },
    points = { easy = 4, normal = 2, hard = 0 }, par = 0,
    needs = {},
    grid = {
        '......................',
        '.......k..............',
        '..BB..........k.......',
        '..BB..................',
        '..........k......c....',
        '......................',
        '......f.........k.....',
        '......................',
    },
    obvious = {},
    clever = {},
}

Levels[2] = {
    name = 'The river',
    blurb = 'Twins joins. The food is across the river; only Twins builds.',
    intro = 'Twins is the builder: only Twins builds anything. BRIDGE the river and both of them will go and eat. The river is not the same width everywhere.',
    morphis = { 'pupper', 'twins' },
    points = { easy = 14, normal = 8, hard = 4 }, par = 2,
    needs = {},
    grid = {
        '..........~~~.........',
        '..........~~~....f....',
        '..BB......~~~...k.....',
        '..BB......~~~.........',
        '..........~~~.....c...',
        '...........~..........',
        '..........~~~...k.....',
        '..........~~~.......h.',
    },
    obvious = { bridge = { { 11, 3, 13, 3 } } },
    clever = { bridge = { { 12, 6, 12, 6 } } },
}

Levels[3] = {
    name = 'Picky',
    blurb = 'Woofoof joins. From now on they only eat out of a BIN.',
    intro = 'They have grown picky: nobody eats off a bush any more. Place a BIN (1 log); the foragers fill it and everyone eats from it. Look at what grows on your own bank before you build a bridge.',
    morphis = { 'pupper', 'woofoof', 'twins' },
    points = { easy = 14, normal = 8, hard = 4 }, par = 2,
    needs = { bins = true },
    grid = {
        '..........~~..........',
        '....k.....~~....f.....',
        '..BB......~~..........',
        '..BB......~~.....c....',
        '...f......~~..........',
        '.......h..~~....k.....',
        '......c...~~..........',
        '..k.......~~.....y....',
    },
    obvious = { bridge = { { 11, 4, 12, 4 } }, bin = { { 6, 3 } } },
    clever = { bin = { { 6, 3 } } },
}

Levels[4] = {
    name = 'Home',
    blurb = 'Cwab joins and mines. Now they want a FLOOR tile each to live on.',
    intro = 'A morphi needs somewhere to live: a FLOOR tile for each of them, anywhere, free. Cwab can MINE stone for nothing. The food is behind stone and across water; one of those is free to open.',
    morphis = { 'pupper', 'woofoof', 'twins', 'cwab' },
    points = { easy = 16, normal = 9, hard = 5 }, par = 2,
    needs = { bins = true, floors = true },
    grid = {
        '#########.....~~~.....',
        '#..k.c..#.....~~~..f..',
        '#.f...h.#.....~~~..k..',
        '#########.....~~~.....',
        '..............~~~.f...',
        '..BB..........~~~.....',
        '..BB..........~~~..c..',
        '..............~~~....h',
        '..............~~~.y...',
    },
    obvious = { bridge = { { 15, 5, 17, 5 } }, bin = { { 7, 7 } }, floor = { { 6, 5 }, { 7, 5 }, { 8, 5 }, { 9, 5 } } },
    clever = { mine = { { 5, 4, 5, 4 } }, bin = { { 7, 7 } }, floor = { { 6, 5 }, { 7, 5 }, { 8, 5 }, { 9, 5 } } },
}

Levels[5] = {
    name = 'Walls',
    blurb = 'Blob joins. The floors must be walled in, with a DOOR to get in.',
    intro = 'Living space now means a house: WALLS all the way round the floors and a DOOR so they can get in. Stone and water count as walls. A wall or a door is 1 log. There is a nook in the stone.',
    morphis = { 'pupper', 'woofoof', 'twins', 'cwab', 'blue' },
    points = { easy = 36, normal = 24, hard = 17 }, par = 6,
    needs = { bins = true, floors = true, enclosed = true },
    grid = {
        '..........................',
        '..#####.........f.........',
        '..#...#.........k.........',
        '..#...#...............h...',
        '..#...#....BB....c....f...',
        '...........BB.............',
        '............h.......y.....',
        '......k...................',
        '.....................c....',
        '..........................',
    },
    obvious = {
        floor = { { 16, 7 }, { 17, 7 }, { 18, 7 }, { 16, 8 }, { 17, 8 } },
        bin = { { 18, 8 } },
        wall = { { 15, 6 }, { 16, 6 }, { 17, 6 }, { 18, 6 }, { 19, 6 }, { 15, 7 }, { 19, 7 }, { 15, 8 }, { 19, 8 }, { 15, 9 }, { 16, 9 }, { 18, 9 }, { 19, 9 } },
        door = { { 17, 9 } },
    },
    clever = {
        floor = { { 4, 3 }, { 5, 3 }, { 6, 3 }, { 4, 4 }, { 5, 4 } },
        bin = { { 10, 8 } },
        wall = { { 4, 6 }, { 6, 6 } },
        door = { { 5, 6 } },
    },
}

Levels[6] = {
    name = 'Inside',
    blurb = 'Everyone. The bins have to be inside the walls too.',
    intro = 'The last straw: every BIN must stand inside the house with the floors. Stone and water still count as walls. The old stone room has a gap in it.',
    morphis = { 'pupper', 'woofoof', 'twins', 'cwab', 'blue' },
    points = { easy = 36, normal = 24, hard = 17 }, par = 5,
    needs = { bins = true, floors = true, enclosed = true, binsInside = true },
    grid = {
        '..........................',
        '..######.......f..........',
        '..#....#.......k..........',
        '..#....#..............h...',
        '..#....#...BB....c....f...',
        '..##..##...BB.............',
        '............h.......y.....',
        '......k...................',
        '.....................c....',
        '..........................',
    },
    obvious = {
        floor = { { 16, 7 }, { 17, 7 }, { 18, 7 }, { 16, 8 }, { 17, 8 } },
        bin = { { 18, 8 } },
        wall = { { 15, 6 }, { 16, 6 }, { 17, 6 }, { 18, 6 }, { 19, 6 }, { 15, 7 }, { 19, 7 }, { 15, 8 }, { 19, 8 }, { 15, 9 }, { 16, 9 }, { 18, 9 }, { 19, 9 } },
        door = { { 17, 9 } },
    },
    clever = {
        floor = { { 4, 3 }, { 5, 3 }, { 6, 3 }, { 7, 3 }, { 4, 4 } },
        bin = { { 7, 5 } },
        wall = { { 5, 6 } },
        door = { { 6, 6 } },
    },
}

return Levels
