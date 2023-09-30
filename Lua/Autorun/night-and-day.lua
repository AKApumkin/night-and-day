local NnD = {} -- night and day mod
NnD.Path = ...
NnD.currentSave = ''

local earthCycleTime = 1440 -- each day is 24 hours or 1440 seconds game time
local earthDayStart = 5 -- 5am sunrise
local earthNightStart = 21 -- 9pm sunset

local europanCycleTime = 5040 -- each Europan day is 3.5 times longer than earth, 84 hours or 5040 seconds game time
local europanDayStart = 5 -- sunrise 5am
local europanNightStart = 68 -- sunset Day 2 Hour 20

local sessionTime = 0
local checkDayChange = 'first'
local husksSpawned = false
local pauseMenuIsActive = false
local isEnded = false
local isOutpost

-- watch functions 
-- uses battery constantly, but slowly, will have a light componenet that is effected by the time of day with a hook 
-- also has a text output that reads the time, that will also be effected by a lua hook. 
-- A warning indicator that has 4 lights, each representing a 1/4 of the Europna day. on the 4th quater which
-- is the Europna night it shows the warning indicator.  


-- TIME loop calls every 1 second for recording game time only during a round
local period = 1000
NnD.startTimer = function()
    Hook.Add('think', 'thinkTimeLoop', function(instance, ptable)
        if not isEnded then
            Timer.Wait(NnD.startTimer, period) 
        end
        -- pause the loop if the menu is active
        if not pauseMenuIsActive then
            sessionTime = sessionTime + 1
            NnD.changeLight(NnD.checkDaylight())
            if not isOutpost then
                if NnD.checkEuropanTime() == 4  and husksSpawned == false then 
                    NnD.spawnHuskSwarms()
                    husksSpawned = true
                end
            end
        end
        Hook.Remove('think', 'thinkTimeLoop')
    end)
end

-- Check pause menu
NnD.CheckPause = function()
    Hook.Patch('Barotrauma.GUI', 'TogglePauseMenu',{}, function(instance, ptable) 
        if pauseMenuIsActive == true then
            pauseMenuIsActive = false
        else 
            pauseMenuIsActive = true
        end
        return
    end, Hook.HookMethodType.After)
end

-- Called at the start of the round 
Hook.Add('roundStart', 'roundStartTime', function(instance, ptable)
    isEnded = false
    NnD.campaignSave = Game.GameSession.SavePath
    NnD.currentSave = string.match(NnD.campaignSave, '[%w%s!-={-|]+[_%.]..+') -- get part of the campaign name for a txt save file 
    NnD.checkSaveFile()
    sessionTime = NnD.readCurrentTime()
    NnD.changeLight(NnD.checkDaylight())
    checkDayChange = NnD.checkDaylight()
    isOutpost = Level.Loaded.IsLoadedOutpost
    NnD.CheckPause()
    NnD.startTimer()
end)

-- called at the end of the round 
Hook.Add('roundEnd', 'roundStartEndTime', function(instance, ptable)
    isEnded = true
    husksSpawned = false
    Hook.Remove('Barotrauma.GUI', 'TogglePauseMenu')
    Hook.Remove('think', 'thinkTimeLoop')
    Hook.Remove('think', 'updateWatchLoop')
    NnD.writeCurrentTime(sessionTime)
end)

-- get the current day in the game
-- @param currentTime integer
-- @return integer
NnD.getDay = function(currentTime)
    local day = math.floor(currentTime / earthCycleTime)
    if day <= 0.99 then 
        day = 1 
    else
        day = day + 1 -- As you start on day 1
    end
    return day
end

-- gets the current human day, then subtracts the time for a full day
-- away from the current time and turns it into hours.
-- @param currentTime integer
-- @return integer
NnD.getHour = function(currentTime)
    local newTime = currentTime
    local currentDay = NnD.getDay(newTime)
    local hour
    if currentDay == 1 then
        hour = math.floor(newTime / 60)
    else 
        currentDay = currentDay - 1
        hour = math.floor((newTime - (currentDay*earthCycleTime)) / 60) 
    end 
    return hour
end

-- returns the current seconds in the game
-- @param currentTime integer
-- @return integer
NnD.getMinute = function(currentTime)
    local newcurrentTime = currentTime
    local currentHour = NnD.getHour(newcurrentTime)
    local getTimePeriod = math.floor(newcurrentTime / 60) 
    local minute = (newcurrentTime - (getTimePeriod* 60))
    return minute
end


-- gets the Europan day, this is 3.5 times a regualr earth day, 
-- each Europan day is is 84 hours or 5040 seconds game time
-- @param currentTime integer
-- @return integer
NnD.getEuropanDay = function(currentTime)
    local currentDay = NnD.getDay(currentTime)
    local europaDay = math.floor(currentDay / 3.5)
    if europaDay <= 0.99 then 
        europaDay = 1 
    else
        europaDay = europaDay + 1 -- As you start on day 1
    end
    return europaDay
end

-- gets the Europan hour for a 3.5 day cycle, with a maximum of 84 hours 
-- @param currentTime integer
-- @return integer
NnD.getEuropanHour = function(currentTime)
    local newTime = currentTime
    local currentDay = NnD.getEuropanDay(newTime)
    local europanHour
    if currentDay == 1 then
        europanHour = math.floor(newTime / 60)
    else 
        currentDay = currentDay - 1
        europanHour = math.floor((newTime - (currentDay*europanCycleTime)) / 60)
    end 
    return europanHour
end

-- reads the current time stored on the system
-- @return string
NnD.readCurrentTime = function()
    if File.Exists(NnD.Path ..'/GameData/'.. NnD.currentSave ..'.txt') then
        return File.Read(NnD.Path ..'/GameData/'.. NnD.currentSave ..'.txt')
    else 
        return nil
    end
end

-- on first load check that a savefile exists if not write one at 0 
NnD.checkSaveFile = function()
    if not NnD.readCurrentTime() then
        File.Write(NnD.Path ..'/GameData/'.. NnD.currentSave ..'.txt',300)
        print('new file created')
    end
end

-- Check for a prior time file, then adds to it based on how much time has passed. 
-- @param sessionTime integer
NnD.writeCurrentTime = function(sessionTime)
    File.Write(NnD.Path ..'/GameData/'.. NnD.currentSave ..'.txt',sessionTime)
end

-- If there is an item or componenet on the submarine which can have its 
-- lights modified then based on the gametime the lighting will 
-- change darker or lighter
-- @param isDay Boolean
NnD.changeLight = function(isDay)
    if checkDayChange ~= isDay or checkDayChange == 'first' then
        for key,value in pairs(Item.ItemList) do
            if value.Submarine then 
                if value.HasTag('LightComponent') or value.HasTag('Light') then
                    if(value.GetComponentString('LightComponent') and value.Name ~= 'Emergency Light') then
                        local alpha
                        if(isDay) then
                            alpha = 130
                        else
                            alpha = 40
                        end 
                        value.GetComponentString('LightComponent').LightColor = Color(value.GetComponentString('LightComponent').LightColor, alpha)
                    end
                end
            end
        end
    end
end

-- checks if there is daylight and returns 
-- @return boolean
NnD.checkDaylight = function() 
    local currentHour = NnD.getHour(sessionTime)
    if currentHour < earthDayStart then
        return false
    elseif currentHour < earthNightStart then
        return true
    else
        return false
    end 
end

-- for times when a 0 is required for the watch add a zero if less than 10
-- @param enterdTime integer 
-- @return string
NnD.timeAddzero = function(enterdTime)
    if enterdTime < 10 then 
        enterdTime = '0' .. enterdTime
    end
    return enterdTime
end

-- create GUI component on item
-- @param hasBattery Boolean
NnD.updateWatch = function(hasChargedBattery)
    local frame = GUI.Frame(GUI.RectTransform(Vector2(1, 1)), nil)
    frame.CanBeFocused = false

    -- show main watch
    local menu = GUI.Frame(GUI.RectTransform(Vector2(0.25, 0.25), frame.RectTransform, GUI.Anchor.TopRight), 'europanWatch')
    menu.RectTransform.AbsoluteOffset = Point(-100,0)
    menu.CanBeFocused = false
    menu.Visible = true

    -- draw time components if charged batter is in the device
    if hasChargedBattery then 
        
        -- draw the day or night icon depending on time
        local dayNightIcon 
        if NnD.checkDaylight() then
            dayNightIcon = GUI.Frame(GUI.RectTransform(Vector2(0.25, 0.25), frame.RectTransform, GUI.Anchor.TopRight), 'sunLight')
        else 
            dayNightIcon = GUI.Frame(GUI.RectTransform(Vector2(0.25, 0.25), frame.RectTransform, GUI.Anchor.TopRight), 'moonLight')
        end
        dayNightIcon.RectTransform.AbsoluteOffset = Point(-100,0)
        dayNightIcon.CanBeFocused = false

        -- draw the warning lights depending on the Europan Time 
        if NnD.checkEuropanTime() then 
            local warningIcon = GUI.Frame(GUI.RectTransform(Vector2(0.25, 0.25), frame.RectTransform, GUI.Anchor.TopRight), 'huskstage' .. NnD.checkEuropanTime())
            warningIcon.RectTransform.AbsoluteOffset = Point(-100,0)
            warningIcon.CanBeFocused = false
        end

        -- draw the timer on the watch
        Hook.Add('think', 'updateWatchLoop', function(instance, ptable)
            -- Timer.Wait(NnD.updateWatch, period)
            local timeString = NnD.timeAddzero(NnD.getHour(sessionTime)) ..':'.. NnD.timeAddzero(NnD.getMinute(sessionTime)) .. '   |      ' .. NnD.getDay(sessionTime)
            local button = GUI.Button(GUI.RectTransform(Vector2(0.2, 0.2), menu.RectTransform, GUI.Anchor.Center),timeString, GUI.Alignment.Center, nil)
            button.CanBeFocused = false
            button.RectTransform.AbsoluteOffset = Point(-20,10)
            button.TextColor = Color(225,225,225)
            frame.AddToGUIUpdateList()
        end)
    else 
        frame.AddToGUIUpdateList()
    end
end

-- When a charachter interacts with a watch, show the display and
-- call the updated watch function, when not interacting with 
-- the watch hide it
Hook.Patch('Barotrauma.Character', 'ControlLocalPlayer', function (instance, ptable)
    local character = instance
    if not character then return end
    if not character.Inventory then return end
    local rightHand = character.Inventory.GetItemInLimbSlot(InvSlotType.RightHand)
    local leftHand = character.Inventory.GetItemInLimbSlot(InvSlotType.LeftHand)
    local item = rightHand or leftHand
    if not item then 
        Hook.Remove('think', 'updateWatchLoop')
        return
    end
    if not item.HasTag('watch') then 
        Hook.Remove('think', 'updateWatchLoop')
        return 
    end
    
    -- detect current battery level then if no battery level only display the watch
    local battery = item.OwnInventory.GetItemAt(0)
    if battery and math.floor(battery.Condition) > 1 then
        NnD.updateWatch(true)
    else 
        NnD.updateWatch(false)
    end
end, Hook.HookMethodType.After)

-- Checks the current Europan time, if Night time exists return True
-- else return the warning leve
-- @return integer 
NnD.checkEuropanTime = function()
    local currentHour = NnD.getEuropanHour(sessionTime)
    if currentHour < europanDayStart then -- nighttime
        return 4
    elseif currentHour >= europanNightStart then -- nighttime
        return 4
    elseif currentHour > europanDayStart and currentHour <= 26  then -- 1st quater
        return 1
    elseif currentHour > 26 and currentHour <= 47 then -- 2nd quater
        return 2
    elseif currentHour > 47 and currentHour <= 68 then -- 3rd quater
        return 3
    end 
end

-- Become one with the husk
-- spawns an ammount of husks based on the level difficulty 
NnD.spawnHuskSwarms = function()
    local levelDifficulty = math.floor(Game.GameSession.LevelData.Difficulty)
    local calculatedMonsters = levelDifficulty + 50
    for i = 1,calculatedMonsters,1 do 
        local monsterPosition = WayPoint.GetRandom(SpawnType.Enemy).WorldPosition
        Entity.Spawner.AddCharacterToSpawnQueue('Crawlerhusk',monsterPosition,nil)
    end
end



