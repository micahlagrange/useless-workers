local pubsub = require('src.system.pub-sub')

CAMERA_ZOOM_LEVEL = 5

EVENTS = {
   Jobs = {},
   Timer = {},
   Hunger = {}
}

EVENTS.Jobs.ADDED_JOB = 'ADDED_JOB'
EVENTS.Timer.TIMER_EXPIRED = 'TIMER_EXPIRED'
EVENTS.Hunger.HUNGER_DEGRADED = 'HUNGER_DEGRADED'
EVENTS.Hunger.MORPHI_HUNGRY = 'MORPHI_HUNGRY'

pubsub:register_events(EVENTS.Timer)
pubsub:register_events(EVENTS.Jobs)

LEFT                     = 0
RIGHT                    = 1
GRAVITY                  = 99
TILE_SIZE                = 16

MORPHI_WIDTH             = 16
MORPHI_HEIGHT            = 16
MORPHI_SPEED             = 100
MAX_WORKER_SPEED         = 20
MORPHI_SCALE             = .9
MORPHOTYPE_DEFAULT       = 'blue'

Colliders                = {}
Colliders.MORPHI         = 'Morphi'
Colliders.GROUND         = 'Ground'
Colliders.MOUSE_POINTER  = 'MousePointer'
Colliders.CONSUMABLE     = 'Consumable'
Colliders.GHOST          = 'Ghost'
Colliders.UI_ELEMENT     = 'UiElement'

OBJECT_LAYER_WALLS       = 'Wall'
OBJECT_LAYER_PLATFORMS   = 'Platform'

LAYER_BG                 = 'Background'
LAYER_PLAYER             = 'Player'

WASTE_LAND               = -9999

INPUT                    = {}
INPUT.Mouse              = {}
INPUT.Mouse.LMB          = 1
INPUT.Mouse.RMB          = 2
INPUT.Mouse.MIDDLE_CLICK = 3
INPUT.Mouse.ARROW_DOWN   = 4
INPUT.Mouse.ARROW_UP     = 5


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
