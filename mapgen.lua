
require('constants')

function GenerateMapObjects(objType, collisionClass, opts)
  opts.collisionIgnore = opts.collisionIgnore or COLLISION_GHOST
  opts.colliderType = opts.colliderType or 'static'

  if GameMap.layers[objType] then
    local mapObjects = {}
    for _, obj in pairs(GameMap.layers[objType].objects) do
      local mo = World:newRectangleCollider(obj.x, obj.y, obj.width, obj.height)

      mo:setCollisionClass(collisionClass, { ignore = opts.collisionIgnore })

      if opts.colliderType then
        mo:setType(opts.colliderType)
      end
      if opts.gravityDisabled == true then
        mo:setGravityScale(0)
      end
      table.insert(mapObjects, mo)
    end
  end
end
