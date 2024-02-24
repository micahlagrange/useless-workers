
LEFT = 0
RIGHT = 1
GRAVITY = 1600
TILE_SIZE = 32
PLAYER_SCALE = 1.9

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


function PrettyPrint(tabl)
  for k, v in pairs(tabl) do
    print(k ': ', v)
  end
end