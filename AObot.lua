-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
Game = Game or nil
InAction = InAction or false

Logs = Logs or {}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
-- Function to calculate the distance between two points.
function calculateDistance(x1, y1, x2, y2)
  return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

-- Function to determine the best direction based on the positions of the weakest and strongest players.
function decideDirection(player, weakestTarget, mostEnergyTarget, gameState)
  local bestDirection = "Stay"
  local maxDistance = -1

  -- Define possible directions to move.
  local directions = {
    Up = {x = 0, y = -1},
    Down = {x = 0, y = 1},
    Left = {x = -1, y = 0},
    Right = {x = 1, y = 0},
    UpRight = {x = 1, y = -1},
    UpLeft = {x = -1, y = -1},
    DownRight = {x = 1, y = 1},
    DownLeft = {x = -1, y = 1},
    Stay = {x = 0, y = 0}
  }

  -- Evaluate each direction.
  for dirName, dirVector in pairs(directions) do
    local newX = (player.x + dirVector.x + gameState.Width) % gameState.Width
    local newY = (player.y + dirVector.y + gameState.Height) % gameState.Height

    -- Calculate distance to the weakest and strongest players from the new position.
    local distanceToWeakest = calculateDistance(newX, newY, weakestTarget.x, weakestTarget.y)
    local distanceToStrongest = calculateDistance(newX, newY, mostEnergyTarget.x, mostEnergyTarget.y)

    -- Decide the best direction: move towards the weakest or away from the strongest.
    local distanceDifference = distanceToWeakest - distanceToStrongest
    if distanceDifference > maxDistance then
      maxDistance = distanceDifference
      bestDirection = dirName
    end
  end

  return bestDirection
end

-- Main function to decide the next action.
function decideNextAction()
  local player = LatestGameState.Players[ao.id]
  local targetInRange, weakestTarget, mostEnergyTarget = false, nil, nil
  local minHealth = math.huge
  local maxEnergy = 0

  -- Find targets within range and identify the weakest and the one with the most energy.
  for target, state in pairs(LatestGameState.Players) do
    if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, Range) then
      targetInRange = true
      if state.health < minHealth then
        minHealth = state.health
        weakestTarget = state
      end
      if state.energy > maxEnergy then
        maxEnergy = state.energy
        mostEnergyTarget = state
      end
    end
  end

  -- Decide whether to attack or move based on strategic considerations.
  if player.energy > 5 and targetInRange then
    -- Attack the weakest player in range to maximize the chance of eliminating a player.
    if weakestTarget then
      print(colors.red .. "Weakest player in range. Attacking." .. colors.reset)
      ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(player.energy), TargetPlayer = weakestTarget.id})
    -- If no weak player is found, consider attacking the player with the most energy.
    elseif mostEnergyTarget then
      print(colors.red .. "Player with most energy in range. Attacking." .. colors.reset)
      ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(player.energy), TargetPlayer = mostEnergyTarget.id})
    end
  else
    -- Move towards the weakest player or away from the strongest player.
    local direction = decideDirection(player, weakestTarget, mostEnergyTarget, LatestGameState)
    print(colors.red .. "Strategic move: " .. direction .. colors.reset)
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = direction})
  end
  InAction = false
end
-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true
      -- print("Getting game state...")
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      InAction = true
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)
-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then 
      InAction = false
      return 
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)
-- Handler to automatically attack when hit by another player.
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then
      InAction = true
      local player = LatestGameState.Players[ao.id]
      local playerEnergy = player.energy
      local playerHealth = player.health

      -- Check if the player's energy is undefined or zero.
      if playerEnergy == nil then
        print(colors.red .. "Unable to read energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print(colors.red .. "Player has insufficient energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        -- If the player's health is low, consider taking a defensive action instead of counterattacking.
        if playerHealth <= (100 / AverageMaxStrengthHitsToKill) then
          print(colors.red .. "Health is low. Taking defensive action." .. colors.reset)
          -- Placeholder for defensive action, e.g., moving to a safer location.
        else
          print(colors.red .. "Returning attack." .. colors.reset)
          ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy)})
        end
      end
      InAction = false
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)
