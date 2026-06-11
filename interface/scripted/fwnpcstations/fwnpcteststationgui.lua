function init()
  self.source = getPaneSourceEntity()
  self.pendingState = nil
  self.pendingAction = nil
  self.state = nil
  requestState()
end

function update(dt)
  processStateRequest()
  processActionRequest()
end

function getPaneSourceEntity()
  if pane.containerEntityId then return pane.containerEntityId() end
  if pane.sourceEntity then return pane.sourceEntity() end
  return nil
end

function close()
  pane.dismiss()
end

function podSlot(widgetName)
  if self.pendingAction then
    setStatus("Station bus busy.\nWait for current action.")
    return
  end

  if not self.state then
    setStatus("Station link still loading.")
    requestState()
    return
  end

  local held = player.swapSlotItem()

  if self.state.hasPod then
    takePodFromStation(held)
  else
    putPodIntoStation(held)
  end
end

function putPodIntoStation(held)
  if not held then
    setStatus("Hold a recalled filled pod, then click the slot.")
    return
  end

  local valid, reason = isValidFilledPod(held)
  if not valid then
    setStatus(reasonToText(reason))
    return
  end

  setStatus("Inserting pod...")

  self.pendingAction = {
    kind = "put",
    held = held,
    promise = world.sendEntityMessage(self.source, "fwnpcteststation_putPod", held)
  }
end

function takePodFromStation(held)
  if held then
    setStatus("Empty cursor required to retrieve pod.")
    return
  end

  setStatus("Retrieving pod...")

  self.pendingAction = {
    kind = "take",
    promise = world.sendEntityMessage(self.source, "fwnpcteststation_takePod")
  }
end

function requestState()
  if self.pendingState then return end

  if not self.source or not world.entityExists(self.source) then
    pane.dismiss()
    return
  end

  self.pendingState = world.sendEntityMessage(self.source, "fwnpcteststation_getState")
end

function processStateRequest()
  if not self.pendingState then return end
  if not self.pendingState:finished() then return end

  if self.pendingState:succeeded() then
    self.state = self.pendingState:result()
    updateWidgets()
  else
    setStatus("Could not read station: " .. tostring(self.pendingState:error()))
  end

  self.pendingState = nil
end

function processActionRequest()
  if not self.pendingAction then return end

  local action = self.pendingAction
  local promise = action.promise

  if not promise:finished() then return end

  self.pendingAction = nil

  if not promise:succeeded() then
    setStatus("Station action failed: " .. tostring(promise:error()))
    requestState()
    return
  end

  local result = promise:result()

  if not result or not result.ok then
    setStatus(reasonToText(result and result.reason or "unknown"))
    requestState()
    return
  end

  if action.kind == "put" then
    player.setSwapSlotItem(nil)
    setStatus("Pod locked.\nCustom pose renderer active.")
  elseif action.kind == "take" then
    if result.pod then
      player.setSwapSlotItem(result.pod)
      setStatus("Pod returned to cursor.")
    else
      setStatus("Station returned no pod.")
    end
  end

  requestState()
end

function updateWidgets()
  if not self.state then
    widget.setItemSlotItem("podSlot", nil)
    widget.setText("lblOccupant", "No signal")
    widget.setText("lblState", "Link pending")
    return
  end

  widget.setItemSlotItem("podSlot", self.state.pod)

  if self.state.hasPod then
    widget.setText("lblOccupant", tostring(self.state.occupantName or "Unknown NPC"))

    local poseText = self.state.poseStatusText
      or self.state.poseFriendlyName
      or self.state.poseState
      or "Custom pose renderer"

    widget.setText("lblState", tostring(poseText))
    widget.setText("lblSlotHint", "POD LOCKED")
    widget.setText("lblSlotHint2", "custom pose")
    setStatus("Pod locked.\nNo live NPC is spawned inside furniture.")
  else
    widget.setText("lblOccupant", "No occupant")
    widget.setText("lblState", "Awaiting pod")
    widget.setText("lblSlotHint", "RECALLED POD ONLY")
    widget.setText("lblSlotHint2", "drag from inventory")
    setStatus("Drag a recalled filled pod onto the slot.")
  end
end

function setStatus(text)
  widget.setText("lblStatus", "^#d68b43;> ^reset;" .. text)
end

function isValidFilledPod(item)
  if type(item) ~= "table" then return false, "notItem" end
  if item.name ~= "fwnpcfilledpod" then return false, "wrongItem" end
  if item.count ~= nil and item.count ~= 1 then return false, "badCount" end

  local params = item.parameters or {}
  if params.released then return false, "podReleased" end

  local npcData = params.npcData or params.originalNpcData
  if type(npcData) ~= "table" then return false, "missingNpcData" end
  if type(npcData.species) ~= "string" then return false, "missingSpecies" end
  if type(npcData.npcType) ~= "string" then return false, "missingNpcType" end
  if npcData.seed == nil then return false, "missingSeed" end
  if type(npcData.identity) ~= "table" then return false, "missingIdentity" end

  return true
end

function reasonToText(reason)
  if reason == "wrongItem" then
    return "Only recalled Filled NPC Pods can go here."
  elseif reason == "badCount" then
    return "Only one pod can be inserted."
  elseif reason == "podReleased" then
    return "Recall NPC before inserting pod."
  elseif reason == "missingNpcData" then
    return "This pod has no NPC data."
  elseif reason == "missingSpecies" then
    return "Pod missing NPC species data."
  elseif reason == "missingNpcType" then
    return "Pod missing NPC type data."
  elseif reason == "missingSeed" then
    return "Pod missing NPC seed data."
  elseif reason == "missingIdentity" then
    return "Pod missing NPC identity data."
  elseif reason == "stationAlreadyHasPod" then
    return "This station already has a pod."
  elseif reason == "stationEmpty" then
    return "This station is empty."
  elseif reason == "unknownPose" then
    return "Station pose is missing from the pose registry."
  elseif reason == "unknownPoseState" then
    return "Station pose state is missing from the pose registry."
  end

  return "Cannot use this item here."
end

function hiddenContainerSlot(widgetName)
end
