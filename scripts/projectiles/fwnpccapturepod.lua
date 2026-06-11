function init()
  self.captureHealthFraction = projectile.getParameter("captureHealthFraction", 0.50)
  self.searchRadius = projectile.getParameter("searchRadius", 1.75)
  self.finished = false
  self.checkTimer = 0
  self.pendingCapture = nil
  self.pendingNpcId = nil
end

function update(dt)
  if self.finished then return end

  if self.pendingCapture then
    pollPendingCapture()
    return
  end

  self.checkTimer = self.checkTimer - dt
  if self.checkTimer <= 0 then
    self.checkTimer = 0.05
    if tryCapture() then
      return
    end
  end

  if projectile.collision() then
    finish("fwnpccapturepod", {})
  end
end

function uninit()
  if not self.finished then
    world.spawnItem("fwnpccapturepod", mcontroller.position(), 1, {}, nil, 0.25)
  end
end

function tryCapture()
  local pos = mcontroller.position()
  local npcs = world.npcQuery(pos, self.searchRadius, {
    boundMode = "collisionarea",
    order = "nearest"
  })

  for _, npcId in ipairs(npcs) do
    if canCapture(npcId) then
      requestNpcSnapshot(npcId)
      return true
    end
  end

  return false
end

function requestNpcSnapshot(npcId)
  if not world.entityExists(npcId) then
    return false
  end

  self.pendingNpcId = npcId
  self.pendingCapture = world.sendEntityMessage(npcId, "fwnpcpods_captureData")
  return true
end

function pollPendingCapture()
  local promise = self.pendingCapture
  if not promise:finished() then
    return
  end

  local npcId = self.pendingNpcId
  self.pendingCapture = nil
  self.pendingNpcId = nil

  if not promise:succeeded() then
    sb.logWarn("[FW NPC Pods] NPC capture message failed: %s", promise:error())
    finish("fwnpccapturepod", {})
    return
  end

  local data = promise:result()

  if not hasValidNpcSnapshot(data) then
    sb.logWarn("[FW NPC Pods] NPC capture returned invalid data; refusing capture: %s", sb.printJson(data, 1))
    finish("fwnpccapturepod", {})
    return
  end

  captureNpcWithData(npcId, data)
end

function canCapture(npcId)
  if not world.entityExists(npcId) then return false end

  -- Do not capture quest/story/persistent named entities.
  if world.entityUniqueId(npcId) then return false end

  local hp = world.entityHealth(npcId)
  if not hp or not hp[1] or not hp[2] or hp[2] <= 0 then return false end

  local healthFraction = hp[1] / hp[2]
  if healthFraction > self.captureHealthFraction then return false end

  local species = world.entitySpecies(npcId)
  local npcType = world.npcType(npcId)

  if not species or not npcType then return false end

  return true
end

function captureNpcWithData(npcId, data)
  sb.logInfo("[FW NPC Pods] Captured valid NPC snapshot: %s", sb.printJson(data, 1))

  removeOriginalNpc(npcId)

  local linkId = "fwnpc_" .. sb.makeUuid()
  local podParams = {
    shortdescription = "Filled NPC Pod: " .. (data.name or "Unknown"),
    description = "Contains " .. (data.name or "an NPC") .. ".",
    npcData = data,
    originalNpcData = copyTable(data),
    linkId = linkId,
    released = false,
    releasedUniqueId = ""
  }

  finish("fwnpcfilledpod", podParams)
end

function hasValidNpcSnapshot(data)
  return type(data) == "table"
    and type(data.species) == "string"
    and type(data.npcType) == "string"
    and data.seed ~= nil
    and type(data.identity) == "table"
end

function finish(itemName, params)
  self.finished = true
  world.spawnItem(itemName, mcontroller.position(), 1, params or {}, nil, 0.25)
  projectile.die()
end

function removeOriginalNpc(npcId)
  if not world.entityExists(npcId) then return end

  local pos = world.entityPosition(npcId)
  if not pos then return end

  world.spawnProjectile(
    "fwnpccapturekill",
    pos,
    projectile.sourceEntity(),
    {1, 0},
    false,
    {
      power = 1,
      damageTeam = {
        type = "indiscriminate",
        team = 0
      }
    }
  )
end

function copyTable(value)
  if type(value) ~= "table" then return value end

  local result = {}
  for k, v in pairs(value) do
    result[k] = copyTable(v)
  end

  return result
end