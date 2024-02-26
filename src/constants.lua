
LEFT = 0
RIGHT = 1
GRAVITY = 1600
TILE_SIZE = 32

WORKER_WIDTH = 32
WORKER_HEIGHT = 32
WORKER_SPEED = 8000
MAX_WORKER_SPEED = 100
WORKER_SCALE = 1

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
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. PrettyPrint(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end
