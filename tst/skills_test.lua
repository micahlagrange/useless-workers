-- Skill stats: scrappy, sightful and grit (epic skills).
local lu = require('libs.luaunit')
package.path = "./?.lua;./?/init.lua;" .. package.path
local Skills = require('src.skills')

TestSkills = {}

function TestSkills:test_everyone_starts_at_zero()
    lu.assertEquals(Skills.new(), { scrappy = 0, sightful = 0, grit = 0 })
end

function TestSkills:test_hunt_chance_is_thirty_percent_plus_five_per_point()
    lu.assertAlmostEquals(Skills.huntChance({ scrappy = 0 }), 0.30, 1e-9)
    lu.assertAlmostEquals(Skills.huntChance({ scrappy = 4 }), 0.50, 1e-9)
    lu.assertEquals(Skills.huntChance({ scrappy = 100 }), 1)
end

function TestSkills:test_yield_gains_one_per_whole_point()
    lu.assertEquals(Skills.yield(0), 1)
    lu.assertEquals(Skills.yield(0.95), 1)
    lu.assertEquals(Skills.yield(2), 3)
end

function TestSkills:test_twenty_digs_make_one_scrappy_point()
    local s = Skills.new()
    for _ = 1, 20 do Skills.add(s, 'scrappy', Skills.GAIN_DIG) end
    lu.assertEquals(Skills.huntChance(s) > 0.34, true)
    lu.assertEquals(math.floor(s.scrappy + 1e-9), 1)
end

os.exit(lu.LuaUnit.run())
