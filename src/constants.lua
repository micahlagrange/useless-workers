
LEFT = 0
RIGHT = 1
GRAVITY = 200
TILE_SIZE = 16

WORKER_WIDTH = 16
WORKER_HEIGHT = 16
WORKER_SPEED = 8000
MAX_WORKER_SPEED = 100
WORKER_SCALE = 0.5

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
