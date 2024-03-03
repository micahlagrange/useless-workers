local pubsub = require('src.system.pub-sub')

EVENTS = { Jobs = {}, Timer = {} }

EVENTS.Jobs.ADDED_JOB = 'ADDED_JOB'
EVENTS.Timer.TIMER_EXPIRED = 'TIMER_EXPIRED'

pubsub:register_events(EVENTS.Timer)
pubsub:register_events(EVENTS.Jobs)

LEFT = 0
RIGHT = 1
GRAVITY = 99
TILE_SIZE = 16

WORKER_WIDTH = 16
WORKER_HEIGHT = 16
WORKER_SPEED = 100
MAX_WORKER_SPEED = 20
WORKER_SCALE = .9
MORPHOTYPE_DEFAULT = 'blue'

COLLISION_WORKER = 'Worker'
COLLISION_GROUND = 'Ground'
COLLISION_GHOST = 'Ghost'

OBJECT_LAYER_WALLS = 'Wall'
OBJECT_LAYER_PLATFORMS = 'Platform'

LAYER_BG = 'Background'
LAYER_PLAYER = 'Player'

function PrettyPrint(o)
   if type(o) == 'table' then
      local s = '{ '
      for k, v in pairs(o) do
         if type(k) ~= 'number' then k = '"' .. k .. '"' end
         s = s .. '[' .. k .. '] = ' .. PrettyPrint(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end
