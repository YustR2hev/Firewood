function init()
  storage.pod = storage.pod
  storage.occupantName = storage.occupantName
  storage.poseName = storage.poseName or config.getParameter("defaultPose", "holdingcell_idle")
  storage.poseState = storage.poseState or config.getParameter("defaultPoseState", "idle")

  self.uiConfig = config.getParameter("uiConfig")
  self.acceptedPodItem = config.getParameter("acceptedPodItem", "fwnpcfilledpod")
  self.spawnNpcOnInsert = false
  self.poseRegistryPath = config.getParameter("poseRegistry", "/firewood/poses/fwnpcposes.config")
  self.poseRegistry = root.assetJson(self.poseRegistryPath)
  self.hairIndex = root.assetJson("/firewood/hair/fwhairindex.config")
  self.poseTimer = 0
  self.currentOccupancyState = nil
  self.currentPoseAnimationState = nil
  self.loggedIdentityForLink = nil

  object.setInteractive(true)

  message.setHandler("fwnpcteststation_getState", function(_, _)
    return getState()
  end)

  message.setHandler("fwnpcteststation_putPod", function(_, _, pod)
    return putPod(pod)
  end)

  message.setHandler("fwnpcteststation_takePod", function(_, _)
    return takePod()
  end)

  message.setHandler("fwnpcteststation_setPose", function(_, _, poseName, poseState)
    return setPose(poseName, poseState)
  end)

  refreshAnimation(true)
end

function update(dt)
  syncInventoryBridgeSlot()
  updatePose(dt)
  refreshAnimation(false)
end

function die(smash)
  if storage.pod then
    world.spawnItem(storage.pod, entity.position())
    storage.pod = nil
    storage.occupantName = nil
  end
end

function getState()
  local pose = getCurrentPose()
  local poseState = getCurrentPoseState()
  local npcData = getNpcDataFromPod(storage.pod)
  local hairType = nil

  if npcData and npcData.identity then
    hairType = resolveHairType(npcData.identity)
  end

  return {
    hasPod = storage.pod ~= nil,
    pod = storage.pod,
    occupantName = storage.occupantName,
    poseName = storage.poseName,
    poseState = storage.poseState,
    poseFriendlyName = pose and pose.friendlyName or storage.poseName,
    poseStatusText = poseState and poseState.statusText or nil,
    renderMode = "layeredPodIdentityPoseWithHair",
    liveNpcSpawned = false,
    renderSpecies = npcData and npcData.species or nil,
    renderGender = npcData and npcData.gender or nil,
    renderHairType = hairType
  }
end

function putPod(pod)
  if storage.pod then
    return { ok = false, reason = "stationAlreadyHasPod" }
  end

  local valid, reason = isValidFilledPod(pod)
  if not valid then
    return { ok = false, reason = reason }
  end

  storage.pod = copyTable(pod)
  local npcData = getNpcDataFromPod(storage.pod)
  storage.occupantName = getNpcDisplayName(npcData)
  storage.poseName = config.getParameter("defaultPose", "holdingcell_idle")
  storage.poseState = config.getParameter("defaultPoseState", "idle")
  self.poseTimer = 0
  self.loggedIdentityForLink = nil

  refreshAnimation(true)

  sb.logInfo(
    "[Firewood Test Station] Inserted pod for %s; hair style/color renderer active, no live NPC spawned",
    storage.occupantName or "unknown NPC"
  )

  logNpcRenderDebug(npcData)

  return { ok = true, state = getState() }
end

function takePod()
  if not storage.pod then
    return { ok = false, reason = "stationEmpty" }
  end

  local pod = storage.pod
  storage.pod = nil
  storage.occupantName = nil
  storage.poseState = config.getParameter("defaultPoseState", "idle")
  self.poseTimer = 0
  self.loggedIdentityForLink = nil

  refreshAnimation(true)

  sb.logInfo("[Firewood Test Station] Removed pod from hair renderer")

  return {
    ok = true,
    pod = pod,
    state = getState()
  }
end

function setPose(poseName, poseState)
  if not storage.pod then
    return { ok = false, reason = "stationEmpty" }
  end

  local pose = self.poseRegistry and self.poseRegistry[poseName]
  if not pose then
    return { ok = false, reason = "unknownPose" }
  end

  local nextState = poseState or pose.defaultState or "idle"
  if not pose.states or not pose.states[nextState] then
    return { ok = false, reason = "unknownPoseState" }
  end

  storage.poseName = poseName
  storage.poseState = nextState
  self.poseTimer = 0
  refreshAnimation(true)

  return { ok = true, state = getState() }
end

function updatePose(dt)
  if not storage.pod then return end

  self.poseTimer = (self.poseTimer or 0) + dt

  if storage.poseState == "idle" and self.poseTimer >= 7.0 then
    storage.poseState = "struggle"
    self.poseTimer = 0
  elseif storage.poseState == "struggle" and self.poseTimer >= 2.0 then
    storage.poseState = "idle"
    self.poseTimer = 0
  end
end

function refreshAnimation(forceRestart)
  if not storage.pod then
    setOccupancyState("empty", forceRestart)
    setPoseAnimationState("hidden", forceRestart)
    return
  end

  setOccupancyState("occupied", forceRestart)

  local npcData = getNpcDataFromPod(storage.pod)
  applyNpcRender(npcData)

  local poseState = getCurrentPoseState()
  local nextPoseState = (poseState and poseState.animationState) or storage.poseState or "idle"
  setPoseAnimationState(nextPoseState, forceRestart)
end

function setOccupancyState(stateName, forceRestart)
  if forceRestart or self.currentOccupancyState ~= stateName then
    animator.setAnimationState("occupancy", stateName, true)
    self.currentOccupancyState = stateName
  end
end

function setPoseAnimationState(stateName, forceRestart)
  if forceRestart or self.currentPoseAnimationState ~= stateName then
    animator.setAnimationState("pose", stateName, true)
    self.currentPoseAnimationState = stateName
  end
end

function applyNpcRender(npcData)
  if not npcData then return end

  local species = safeKey(npcData.species, "generic")
  local gender = safeKey(npcData.gender, "neutral")
  local identity = npcData.identity or {}

  local basePath = resolveHumanoidBasePath(species, gender)

  animator.setPartTag("actorBackArm", "fwBackArmImage", basePath .. "/backarm.png")
  animator.setPartTag("actorBody", "fwBodyImage", basePath .. "/body.png")
  animator.setPartTag("actorHead", "fwHeadImage", basePath .. "/head.png")
  animator.setPartTag("actorFrontArm", "fwFrontArmImage", basePath .. "/frontarm.png")

  animator.setPartTag("actorHair", "fwHairImage", resolveHairPath(npcData))

  animator.setGlobalTag("fwBodyDirectives", resolveBodyDirectives(identity))
  animator.setGlobalTag("fwHeadDirectives", resolveHeadDirectives(identity))
  animator.setGlobalTag("fwHairDirectives", resolveHairDirectives(identity))
end

function resolveHumanoidBasePath(species, gender)
  local rootPath = getCurrentActorAssetRoot()

  species = safeKey(species, "generic")
  gender = safeKey(gender, "neutral")

  -- Do not dynamically probe guessed asset paths here. Missing probes spam the log.
  local supportedSpecies = {
    generic = true,
    human = true,
    apex = true,
    avian = true,
    floran = true,
    hylotl = true,
    glitch = true,
    novakid = true
  }

  if not supportedSpecies[species] then
    species = "generic"
  end

  if species == "generic" then
    gender = "neutral"
  elseif gender ~= "male" and gender ~= "female" then
    return rootPath .. "/generic/neutral"
  end

  return string.format("%s/%s/%s", rootPath, species, gender)
end

function resolveHairPath(npcData)
  local identity = npcData.identity or {}
  local species = safeKey(npcData.species, "generic")
  local gender = safeKey(npcData.gender, "neutral")
  local hairType = resolveHairType(identity)

  if not hairType then
    return "/objects/fwnpcstations/actors/blank_pose.png"
  end

  local mappedStyle = lookupHairStyle(species, gender, hairType)
  if mappedStyle then
    return string.format(
      "/objects/fwnpcstations/actors/hair/%s/%s/%s.png",
      mappedStyle.species,
      mappedStyle.gender,
      mappedStyle.style
    )
  end

  return "/objects/fwnpcstations/actors/hair/generic/neutral/default.png"
end

function resolveHairType(identity)
  local raw = firstString(identity, {
    "hairType",
    "hair",
    "hairStyle",
    "hairStyleName"
  }, nil)

  if not raw or raw == "" then return nil end
  return safeKey(raw, nil)
end

function lookupHairStyle(species, gender, hairType)
  if not self.hairIndex then return nil end

  local speciesTable = self.hairIndex[species]
  local genderTable = speciesTable and speciesTable[gender]
  local style = genderTable and genderTable[hairType]

  if style then
    return { species = species, gender = gender, style = style }
  end

  local neutralTable = speciesTable and speciesTable.neutral
  style = neutralTable and neutralTable[hairType]
  if style then
    return { species = species, gender = "neutral", style = style }
  end

  local genericGender = self.hairIndex.generic and self.hairIndex.generic[gender]
  style = genericGender and genericGender[hairType]
  if style then
    return { species = "generic", gender = gender, style = style }
  end

  local genericNeutral = self.hairIndex.generic and self.hairIndex.generic.neutral
  style = genericNeutral and genericNeutral[hairType]
  if style then
    return { species = "generic", gender = "neutral", style = style }
  end

  return nil
end

function getCurrentActorAssetRoot()
  local pose = getCurrentPose()
  if pose and pose.actorAssetRoot then
    return pose.actorAssetRoot
  end
  return "/objects/fwnpcstations/actors/humanoid"
end

function resolveBodyDirectives(identity)
  return firstDirective(identity, {
    "bodyDirectives",
    "bodyColorDirectives",
    "skinDirectives",
    "skinColorDirectives"
  }, "")
end

function resolveHeadDirectives(identity)
  return firstDirective(identity, {
    "headDirectives",
    "bodyDirectives",
    "bodyColorDirectives",
    "skinDirectives",
    "skinColorDirectives"
  }, "")
end

function resolveHairDirectives(identity)
  return firstDirective(identity, {
    "hairDirectives",
    "hairColorDirectives",
    "hairColor"
  }, "")
end

function firstString(t, keys, default)
  if type(t) ~= "table" then return default end

  for _, key in ipairs(keys) do
    if type(t[key]) == "string" then
      return t[key]
    end
  end

  return default
end

function firstDirective(t, keys, default)
  if type(t) ~= "table" then return default end

  for _, key in ipairs(keys) do
    local directive = directiveFromValue(t[key])
    if directive ~= nil then return directive end
  end

  return default
end

function directiveFromValue(value)
  if type(value) == "string" then
    if value == "" then return "" end
    return value
  end

  if type(value) == "table" then
    local r = value.r or value.red or value[1]
    local g = value.g or value.green or value[2]
    local b = value.b or value.blue or value[3]

    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
      return string.format("?multiply=%02x%02x%02x", clamp255(r), clamp255(g), clamp255(b))
    end

    if type(value.directives) == "string" then
      return value.directives
    end
  end

  return nil
end

function clamp255(value)
  if value < 0 then return 0 end
  if value > 255 then return 255 end
  return math.floor(value + 0.5)
end

function safeKey(value, default)
  if type(value) ~= "string" or value == "" then return default end
  return string.gsub(value, "[^%w_%-]", "")
end

function logNpcRenderDebug(npcData)
  if not npcData then return end

  local linkId = nil
  if storage.pod and storage.pod.parameters then
    linkId = storage.pod.parameters.linkId
  end

  if self.loggedIdentityForLink == linkId then return end
  self.loggedIdentityForLink = linkId

  local identity = npcData.identity or {}

  sb.logInfo(
    "[Firewood Render Debug] species=%s gender=%s npcType=%s name=%s hairType=%s hairDirectives=%s",
    tostring(npcData.species),
    tostring(npcData.gender),
    tostring(npcData.npcType),
    tostring(getNpcDisplayName(npcData)),
    tostring(resolveHairType(identity)),
    tostring(resolveHairDirectives(identity))
  )

  sb.logInfo("[Firewood Render Debug] identity=%s", sb.printJson(identity, 1))
  sb.logInfo("[Firewood Render Debug] equipment=%s", sb.printJson(npcData.equipment or {}, 1))
end

function getCurrentPose()
  if not self.poseRegistry then return nil end
  return self.poseRegistry[storage.poseName or config.getParameter("defaultPose", "holdingcell_idle")]
end

function getCurrentPoseState()
  local pose = getCurrentPose()
  if not pose or not pose.states then return nil end

  local stateName = storage.poseState or pose.defaultState or "idle"
  return pose.states[stateName]
end

function containerCallback()
  syncInventoryBridgeSlot()
end

function syncInventoryBridgeSlot()
  if not world.containerItemAt then return end

  local item = world.containerItemAt(entity.id(), 0)
  if not item then return end

  local valid = isValidFilledPod(item)

  if valid and not storage.pod then
    storage.pod = copyTable(item)
    local npcData = getNpcDataFromPod(storage.pod)
    storage.occupantName = getNpcDisplayName(npcData)
    storage.poseName = config.getParameter("defaultPose", "holdingcell_idle")
    storage.poseState = config.getParameter("defaultPoseState", "idle")
    self.poseTimer = 0
    self.loggedIdentityForLink = nil

    world.containerConsumeAt(entity.id(), 0, item.count or 1)
    refreshAnimation(true)

    sb.logInfo(
      "[Firewood Test Station] Loaded pod from inventory bridge slot for %s; hair style/color renderer active",
      storage.occupantName or "unknown NPC"
    )
    logNpcRenderDebug(npcData)
    return
  end

  local removed = nil
  if world.containerTakeAt then
    removed = world.containerTakeAt(entity.id(), 0)
  else
    removed = item
    world.containerConsumeAt(entity.id(), 0, item.count or 1)
  end

  if removed then
    world.spawnItem(removed, entity.position())
    sb.logWarn(
      "[Firewood Test Station] Ejected invalid or excess item from inventory bridge slot: %s",
      sb.printJson(removed)
    )
  end
end

function isValidFilledPod(pod)
  if type(pod) ~= "table" then
    return false, "notItemDescriptor"
  end

  if pod.name ~= self.acceptedPodItem then
    return false, "wrongItem"
  end

  if pod.count ~= nil and pod.count ~= 1 then
    return false, "badCount"
  end

  local params = pod.parameters or {}

  if params.released then
    return false, "podReleased"
  end

  local npcData = params.npcData or params.originalNpcData

  if type(npcData) ~= "table" then
    return false, "missingNpcData"
  end

  if type(npcData.species) ~= "string" then
    return false, "missingSpecies"
  end

  if type(npcData.npcType) ~= "string" then
    return false, "missingNpcType"
  end

  if npcData.seed == nil then
    return false, "missingSeed"
  end

  if type(npcData.identity) ~= "table" then
    return false, "missingIdentity"
  end

  return true
end

function getNpcDataFromPod(pod)
  if not pod then return nil end
  local params = pod.parameters or {}
  return params.npcData or params.originalNpcData
end

function getNpcDisplayName(npcData)
  if not npcData then return "Unknown NPC" end
  if npcData.name then return npcData.name end
  if npcData.identity and npcData.identity.name then return npcData.identity.name end
  return "Unknown NPC"
end

function copyTable(value)
  if type(value) ~= "table" then return value end

  local result = {}
  for k, v in pairs(value) do
    result[k] = copyTable(v)
  end

  return result
end
