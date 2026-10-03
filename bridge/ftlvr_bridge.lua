-- Original tabletop bridge code; uses the documented Hyperspace Lua API.
-- State is emitted through Hyperspace's flushed log; Lua's IO sandbox stays intact.
local tick = 0
local sequence = 0
local events = {}
local projectile_ids = {}
local next_id = 0
local next_event = 0
local render_ui_only = false
local tactical = false
local supplemental_hud = false
local dialog_id = 0
local dialog_signature = ""
local errors = {}
local crew_positions = {}
local panel_tab = 'window'
local panel_render_tick = -100
local system_names = {[0]='shields',[1]='engines',[2]='oxygen',[3]='weapons',[4]='drones',
    [5]='medbay',[6]='pilot',[7]='sensors',[8]='doors',[9]='teleporter',[10]='cloaking',
    [11]='artillery',[12]='battery',[13]='clonebay',[14]='mind',[15]='hacking'}

local function json(value)
    local kind = type(value)
    if kind == 'nil' then return 'null' end
    if kind == 'boolean' then return value and 'true' or 'false' end
    if kind == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then return 'null' end
        return tostring(value)
    end
    if kind == 'string' then
        return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
            if c == '\\' then return '\\\\' end
            if c == '"' then return '\\"' end
            return string.format('\\u%04x', string.byte(c))
        end) .. '"'
    end
    local list, count = {}, 0
    for key in pairs(value) do if type(key) == 'number' then count = count + 1 end end
    if count > 0 then
        for i = 1, #value do list[#list+1] = json(value[i]) end
        return '[' .. table.concat(list, ',') .. ']'
    end
    for key, member in pairs(value) do list[#list+1] = json(tostring(key)) .. ':' .. json(member) end
    return '{' .. table.concat(list, ',') .. '}'
end

local function attempt(label, callback, fallback)
    local ok, result = pcall(callback)
    if ok then return result end
    if not errors[label] then log('FTLVR_ERROR ' .. label .. ': ' .. tostring(result)); errors[label] = true end
    return fallback
end

local function point(p) return {x=p.x, y=p.y} end
local function distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end

local function blueprint_title(blueprint, short)
    return attempt(short and 'blueprint_short_title' or 'blueprint_title', function()
        return short and blueprint:GetNameShort() or blueprint:GetNameLong()
    end, blueprint.name)
end

local function drone_snapshot(drone, slot, is_space)
    local id=tostring(drone.selfId)
    if drone.selfId<0 then
        id=(is_space and 'space-' or 'internal-')..tostring(drone.iShipId)..'-'..tostring(slot)
    end
    local result={id=id,native_id=drone.selfId,slot=is_space and -1 or slot,name=drone.blueprint.name,
        kind=drone.blueprint.typeName,type=drone.type,owner=drone.iShipId,
        powered=drone.powered,deployed=drone.deployed,dead=drone.bDead,is_space=is_space}
    if is_space then
        result.space=drone.currentSpace
        result.x, result.y=drone.currentLocation.x,drone.currentLocation.y
        result.angle=drone.current_angle
        result.firing=drone.bFire
        result.target_ship=drone.destinationSpace
        result.target=point(drone.targetLocation)
    else
        local location=drone:GetWorldLocation()
        result.space=drone.iShipId
        result.x,result.y=location.x,location.y
    end
    return result
end

local function append_space_drone(list, drone, slot)
    local value=drone_snapshot(drone,slot,true)
    -- Ordinary drones belong to ShipManager; special drones can also occur
    -- in SpaceManager. Retain one record when both vectors contain an object.
    for _,existing in ipairs(list) do
        if existing.is_space and existing.owner==value.owner and
            ((value.native_id>=0 and existing.native_id==value.native_id) or
             (value.native_id<0 and existing.native_id<0 and existing.name==value.name and
              existing.space==value.space and existing.x==value.x and existing.y==value.y)) then return end
    end
    list[#list+1]=value
end

local function impact(projectile, outcome, ship, location)
    next_event=next_event+1
    events[#events+1]={id='impact-'..tostring(next_event), projectile_id=tostring(projectile.selfId),
        phase='impact', outcome=outcome, ship=ship, target=location and point(location) or nil}
end

local function ship_snapshot(ship, gui)
    if not ship then return nil end
    local graph = Hyperspace.ShipGraph.GetShipInfo(ship.iShipId)
    local result = {layout=ship.myBlueprint.layoutFile, image=ship.myBlueprint.imgFile,
        hull=ship.ship.hullIntegrity.first, hull_max=ship.ship.hullIntegrity.second,
        destroyed=ship.bDestroyed, rooms={}, crew={}, weapons={}, doors={}, drones={},drone_equipment={},
        systems={}, system_power={}, system_status={}, room_systems={}}
    -- Native sensor_4 permits enemy power bars; sensor_2 only reveals rooms.
    -- Condition colours remain public, just as the native target icons do.
    local viewer=Hyperspace.ships.player
    local detailed=ship.iShipId==0 or (viewer and viewer:GetSystemPower(7)>=4)
    for id=0,15 do
        local name=system_names[id]
        if ship:HasSystem(id) then
            local system=ship:GetSystem(id)
            result.systems[name]=true
            result.system_power[name]=ship:GetSystemPower(id)
            local row={id=id,key=name,name=name,room_id=system.roomId,
                allocated=system.powerState.first,max_power=system.powerState.second,
                effective_power=system:GetEffectivePower(),health=system.healthState.first,
                max_health=system.healthState.second,
                damaged=system.healthState.second-system.healthState.first,
                health_visible=true,health_detail_visible=detailed or
                    (system.iHackEffect>0 and system.bUnderAttack),
                repair_progress=math.min(1,math.max(0,system.fRepairOverTime/100)),
                ionized=system.iLockCount>0,locked=system:GetLocked(),hacked=system.iHackEffect,
                powerable=system:GetNeedsPower(),power_cap=system:GetPowerCap(),
                battery_power=system.iBatteryPower,bonus_power=system.iBonusPower,
                on_fire=system.bOnFire,breached=system.bBreached,icon=name}
            result.system_status[#result.system_status+1]=row
            if id==8 then result.door_level=system.powerState.second end
        end
    end
    local reactor=Hyperspace.PowerManager.GetPowerManager(ship.iShipId)
    local installed=reactor.currentPower.second
    local total=math.max(0,reactor:GetMaxPower())
    local raw_available=reactor:GetAvailablePower()
    local cap_loss=math.max(0,installed-total)
    -- GetAvailablePower is installed minus allocated, before environmental
    -- limits. Use the same subtraction as native RenderPowerBar; battery
    -- remains separate so free reactor bars cannot be counted twice.
    local usable_available=math.min(total,math.max(0,raw_available-cap_loss))
    result.reactor={available=usable_available,total=total,
        usable_available=usable_available,usable_total=total,raw_available=raw_available,
        cap_loss=cap_loss,storm_loss=Hyperspace.App.world.space.bStorm and cap_loss or 0,
        used=reactor.currentPower.first,installed=reactor.currentPower.second,
        battery_available=math.max(0,reactor.batteryPower.second-reactor.batteryPower.first),
        battery_total=reactor.batteryPower.second}
    local breaches=ship.ship:GetHullBreaches(true)
    local shield = ship:GetShieldPower()
    result.shield = shield.first
    result.super_shield = shield.super.first
    local ellipse=ship.ship:GetBaseEllipse()
    result.shield_shape={center=point(ellipse.center),a=ellipse.a,b=ellipse.b}
    local image=ship.ship.shipImage
    result.ship_image={x=image.x,y=image.y,w=image.w,h=image.h}
    result.ship_image.name=ship.ship.shipImageName
    result.ship_image.resource=image.resId
    if image.tex then
        result.ship_image.texture_w=image.tex.width
        result.ship_image.texture_h=image.tex.height
    end
    for i=0, graph.rooms:size()-1 do
        local shape = graph:GetRoomShape(i)
        local center = ship:GetRoomCenter(i)
        local system=ship:GetSystemInRoom(i)
        if system then result.room_systems[tostring(i)]=system_names[system.iSystemType] or 'system' end
        local fire_tiles,breach_tiles={},{}
        if ship:GetFireCount(i)>0 then
            for x=shape.x+17.5,shape.x+shape.w-1,35 do
                for y=shape.y+17.5,shape.y+shape.h-1,35 do
                    local fire=ship:GetFireAtPoint(x,y)
                    if fire.fDamage>0 then fire_tiles[#fire_tiles+1]={x=x,y=y,damage=fire.fDamage} end
                end
            end
        end
        for j=0,breaches:size()-1 do
            local breach=breaches[j]
            -- Hull breaches store the tile's corner; consumers use tile centers.
            if breach.roomId==i then breach_tiles[#breach_tiles+1]={x=breach.pLoc.x+17.5,y=breach.pLoc.y+17.5,damage=breach.fDamage} end
        end
        result.rooms[#result.rooms+1] = {id=i, x=shape.x, y=shape.y, w=shape.w, h=shape.h,
            center=point(center), visible=not graph:GetRoomBlackedOut(i), oxygen=graph:GetRoomOxygen(i),
            fires=ship:GetFireCount(i),fire_tiles=fire_tiles,breach_tiles=breach_tiles,breaches=#breach_tiles}
    end
    local seen_doors={}
    for list_index,list in ipairs({ship.ship.vDoorList,ship.ship.vOuterAirlocks}) do
        for i=0,list:size()-1 do
            local door=list[i]
            local key=tostring(door.x)..':'..tostring(door.y)..':'..tostring(door.bVertical)
            if not seen_doors[key] then
                seen_doors[key]=true
                -- Vanilla gives every exterior airlock native id -1. Keep a
                -- unique semantic handle, retaining the original id for logs.
                local id=list_index==2 and 10000+i or door.iDoorId>=0 and door.iDoorId or i
                local locked=door.lockedDown.running
                local forced=door.forcedOpen.running
                result.doors[#result.doors+1]={id=id,native_id=door.iDoorId,x=door.x,y=door.y,
                    vertical=door.bVertical,open=door.bOpen or door.bFakeOpen,
                    room_a=door.iRoom1,room_b=door.iRoom2,health=door.health,max_health=door.baseHealth,
                    locked=locked,forced_open=forced,hacked=door.iHacked,ionized=door.bIoned,
                    level=door.doorLevel,blast=door.iBlast,
                    controllable=ship.iShipId==0 and ship:DoorsFunction() and not locked and not forced}
            end
        end
    end
    for i=0, ship.vCrewList:size()-1 do
        local crew = ship.vCrewList[i]
        if not crew:IsDead() and not crew:OutOfGame() then
            local id=tostring(crew.extend.selfId)
            local previous=crew_positions[id]
            local running=previous~=nil and previous.ship==crew.currentShipId and
                (previous.tick==tick and previous.running or
                ((crew.x-previous.x)^2+(crew.y-previous.y)^2)>0.04)
            crew_positions[id]={x=crew.x,y=crew.y,ship=crew.currentShipId,tick=tick,running=running}
            result.crew[#result.crew+1] = {id=id, index=i,
                name=crew.blueprint:GetNameShort(), species=crew.species, x=crew.x, y=crew.y,
                room=crew.iRoomId, owner=crew.iShipId, ship=crew.currentShipId,
                controllable=crew:GetControllable(), selected=crew.selectionState>0,
                health=crew.health.first, health_max=crew.health.second,
                fighting=crew.bFighting, repairing=crew:Repairing(),
                running=running,working=crew.bActiveManning,is_drone=crew:IsDrone()}
        end
    end
    local drones=ship:GetDroneList()
    for i=0,drones:size()-1 do
        local drone=drones[i]
        result.drone_equipment[#result.drone_equipment+1]={slot=i,name=drone.blueprint.name,
            title=blueprint_title(drone.blueprint,false),short_title=blueprint_title(drone.blueprint,true),
            kind=drone.blueprint.typeName,powered=drone.powered,deployed=drone.deployed}
        -- Hyperspace casts Drone* to its real subclass. Ordinary flying
        -- equipment drones must be included here as well as special vectors.
        if drone.type==2 or drone.type==3 then
            result.drones[#result.drones+1]=drone_snapshot(drone,i,false)
        else
            append_space_drone(result.drones,drone,i)
        end
    end
    for i=0,ship.spaceDrones:size()-1 do
        append_space_drone(result.drones,ship.spaceDrones[i],i)
    end
    local weapons = ship:GetWeaponList()
    for i=0, weapons:size()-1 do
        local weapon = weapons[i]
        local kind=weapon.blueprint.typeName:lower()
        if kind=='missiles' then kind='missile' end
        if kind=='burst' then kind='flak' end
        if weapon.blueprint.damage.iIonDamage>0 then kind='ion' end
        result.weapons[#result.weapons+1] = {slot=i, name=weapon.blueprint.name,
            title=blueprint_title(weapon.blueprint,false),short_title=blueprint_title(weapon.blueprint,true),
            ammo_cost=weapon.blueprint.missiles,
            kind=kind, powered=weapon.powered, autofire=weapon.autoFiring, charge=weapon.cooldown.first,
            cooldown=weapon.cooldown.second, mount=point(weapon.mount.position),
            charge_fraction=weapon.cooldown.second>0 and math.min(1,math.max(0,weapon.cooldown.first/weapon.cooldown.second)) or 1,
            charge_level=weapon.chargeLevel,charge_max=weapon.blueprint.chargeLevels,
            required_power=weapon.requiredPower,ready=weapon.powered and weapon.cooldown.first>=weapon.cooldown.second,
            num_shots=weapon.numShots,shots_fired=weapon.shotsFiredAtTarget,queued_shots=weapon.queuedProjectiles:size(),
            sub_charge=weapon.subCooldown.first,sub_cooldown=weapon.subCooldown.second,
            muzzle=point(weapon.weaponVisual.fireLocation), firing=weapon.weaponVisual.bFiring}
		-- Display the player's real placed aiming marks, never an enemy's intent.
		if ship.iShipId==0 then
			local row=result.weapons[#result.weapons]
			row.targets={}
			for n=0,weapon.targets:size()-1 do row.targets[#row.targets+1]=point(weapon.targets[n]) end
			row.target_ship=weapon.targetId
			row.target_radius=weapon.radius
			row.beam_length=weapon.blueprint.length
		end
    end
    return result
end

local function snapshot()
    local app = Hyperspace.App
    local gui = app.gui
    local player, enemy = Hyperspace.ships.player, Hyperspace.ships.enemy
    local state = {protocol=2, sequence=sequence, source='hyperspace', ready=app.world.bStartedGame,
        combat=enemy~=nil and not enemy.bDestroyed, paused=gui.bPaused,
        frozen=app.world.space.gamePaused, ui_mode='game', tactical=tactical, shots=events, projectiles={}}
    if app.menu.bOpen or not state.ready then state.ui_mode='menu' end
    state.ship_builder_open=app.menu.shipBuilder.bOpen
    state.event_pending = gui.event_pause and not gui.choiceBoxOpen
    state.jumping = player and player.bJumping or false
    state.transition = state.event_pending or (player and player.bJumping or false)
    if state.ui_mode~='menu' and gui.menu_pause and not gui.choiceBoxOpen and not state.transition then state.ui_mode='screen' end
    state.event_open = gui.choiceBoxOpen
    if tactical and state.ui_mode~='menu' then state.ui_mode='screen' end
    if state.event_open then
        state.dialog = attempt('dialog', function()
            local box=gui.choiceBox
            local choices={}
            local signature=box.mainText
            for i=0,box.choices:size()-1 do
                local choice=box.choices[i]
                signature=signature .. '|' .. tostring(choice.type) .. ':' .. choice.text
                choices[#choices+1]={index=i,text=choice.text,type=choice.type,enabled=choice.type~=1}
            end
            if signature~=dialog_signature then dialog_id=dialog_id+1; dialog_signature=signature end
            return {id=tostring(dialog_id),text=box.mainText,choices=choices,centered=box.centered}
        end, nil)
    else
        dialog_signature=''
    end
    local space = app.world.space
    state.hazard = space.bStorm and 'storm' or space.bNebula and 'nebula' or
        space.sunLevel and 'sun' or space.pulsarLevel and 'pulsar' or
        space.asteroidGenerator.bRunning and 'asteroid' or 'clear'
    if player and state.ready then
        state.player = ship_snapshot(player, gui)
        state.hull, state.hull_max = state.player.hull, state.player.hull_max
        state.shield, state.super_shield = state.player.shield, state.player.super_shield
        state.fuel, state.scrap = player.fuel_count, player.currentScrap
        state.oxygen = player:GetOxygenPercentage()
        state.player_origin = point(gui.shipPosition)
        state.enemy_origin = {x=gui.combatControl.position.x+gui.combatControl.targetPosition.x,
            y=gui.combatControl.position.y+gui.combatControl.targetPosition.y}
        state.weapon_selected = gui.combatControl.weapControl.armedSlot
        -- Read the systems' armed state directly. Cursor icons can be stale when
        -- their normal render is hidden by the VR presentation.
        local mind_mode=player.mindSystem and player.mindSystem.iArmed or 0
        local teleport_mode=player.teleportSystem and player.teleportSystem.iArmed or 0
        local hacking_armed=player.hackingSystem and player.hackingSystem.bArmed or false
        local target_kind=mind_mode~=0 and 'mind' or teleport_mode~=0 and 'teleporter' or
            hacking_armed and 'hacking' or (state.weapon_selected>=0 or gui.combatControl.weapControl.armedWeapon~=nil) and 'weapon' or ''
        state.targeting={active=target_kind~='',kind=target_kind,
            ships=target_kind=='mind' and {'player','enemy'} or {'enemy'},
            mode=target_kind=='teleporter' and teleport_mode or target_kind=='mind' and mind_mode or 0}
        state.autofire = gui.combatControl.weapControl.autoFiring
        state.drone_slots = player:GetDroneList():size()
        state.beam_targeting = gui.combatControl.movingBeam
        state.boss_visual = gui.combatControl.boss_visual
        state.jump_button = point(gui.ftlButton.position)
        state.ship_button = point(gui.upgradeButton.position)
        state.map_open = app.world.starMap.bOpen
        if state.ui_mode~='menu' and (state.map_open or gui.equipScreen.bOpen) then state.ui_mode='screen' end
        local loc = app.world.starMap.currentLoc
        local at_store = loc and loc.event and loc.event.store or false
        state.navigation = {
            jump=gui.ftlButton.bActive and player.jump_timer.first>=player.jump_timer.second and
                player:GetSystemPower(1)>0 and player:GetSystemPower(6)>0 and not player.bJumping,
            ship=gui.upgradeButton.bActive,
            store=at_store and gui.upgradeButton.bActive and not gui.dangerLocation}
    end
    if state.combat then
        state.enemy = ship_snapshot(enemy, gui)
        state.enemy_hull, state.enemy_hull_max = state.enemy.hull, state.enemy.hull_max
        state.enemy_shield, state.enemy_super_shield = state.enemy.shield, state.enemy.super_shield
    end
    -- All in-game native windows float above the table. The actual main menu
    -- keeps its existing headset screen, and navigation remains on the hand.
    local tab_open=tick-panel_render_tick<=8
    if state.ui_mode~='menu' and tab_open and not state.transition then state.ui_mode='screen' end
    state.blocking_ui=state.ui_mode=='menu' or state.map_open or state.event_open or state.event_pending or
        state.transition or gui.menu_pause or gui.equipScreen.bOpen or tab_open
    state.panel_open=state.ready and (gui.menu_pause or gui.equipScreen.bOpen or tab_open) and not
        (state.map_open or state.event_open or state.event_pending or state.transition)
    state.panel_kind=state.panel_open and (tab_open and panel_tab or gui.equipScreen.bOpen and 'ship' or 'window') or nil
    for i=0,space.drones:size()-1 do
        local drone=space.drones[i]
        local side=drone.iShipId==0 and state.player or state.enemy
        if side then append_space_drone(side.drones,drone,i) end
    end
    for id,position in pairs(crew_positions) do
        if tick-position.tick>120 then crew_positions[id]=nil end
    end
    local alive={}
    for i=0, space.projectiles:size()-1 do
        local p=space.projectiles[i]
        if not projectile_ids[p.selfId] and not p:Dead() and (p:GetType()==2 or p:GetType()==6) then
            local target_ship=Hyperspace.ships(p.targetId)
            if target_ship then
                next_id=next_id+1
                projectile_ids[p.selfId]={id=next_id,start=point(p.position)}
                local graph=Hyperspace.ShipGraph.GetShipInfo(p.targetId)
                events[#events+1]={id='fire-'..tostring(next_id),projectile_id=tostring(p.selfId),
                    source='environment',ship=p.targetId,phase='fire',outcome='pending',
                    target_space=p.targetId,
                    kind=p:GetType()==2 and 'asteroid' or 'laser',origin_point=point(p.position),
                    target=point(p.target),target_room=graph:GetSelectedRoom(p.target.x,p.target.y,true)}
            end
        end
        local record=projectile_ids[p.selfId]
        if record and not p:Dead() then
            alive[p.selfId]=true
            local progress=math.min(0.48,distance(p.position,record.start)/600)
            if p.currentSpace==p.targetId then
                local remaining=distance(p.position,p.target)
                record.entry_distance=record.entry_distance or math.max(1,remaining)
                progress=0.5+0.5*(1-math.min(1,remaining/record.entry_distance))
            end
            local live={id=tostring(p.selfId), progress=progress, missed=p.missed}
            if record.beam and p.currentSpace==p.targetId then
                live.beam_point=point(record.beam.sub_end)
            end
            state.projectiles[#state.projectiles+1]=live
        end
    end
    for id in pairs(projectile_ids) do
        if not alive[id] then projectile_ids[id]=nil end
    end
    render_ui_only = state.ready and not Hyperspace.App.menu.bOpen and not tactical
    sequence = sequence + 1
    log('FTLVR_STATE ' .. json(state))
    events = {}
end

script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
    -- A failed supplemental capture cannot keep the real game render hidden.
    supplemental_hud=false
    tick = tick + 1
    if tick % 6 == 0 then attempt('snapshot', snapshot, nil) end
end)

-- Hyperspace supplies the native tab name through this render callback.
if Defines.RenderEvents.TABBED_WINDOW then
    script.on_render_event(Defines.RenderEvents.TABBED_WINDOW,function(name)
        panel_tab=tostring(name)
        panel_render_tick=tick
        return Defines.Chain.CONTINUE
    end,function() end)
end

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
    next_id = next_id + 1
    local id = next_id
    projectile_ids[projectile.selfId] = {id=id,start=point(projectile.position)}
    local target_ship = Hyperspace.ships(projectile.targetId)
    if not target_ship or projectile.ownerId < 0 or projectile.ownerId > 1 then return end
    local kind = weapon.blueprint.typeName:lower()
    if kind == 'burst' then kind='laser' end
    if kind == 'missiles' then kind='missile' end
    if projectile.damage.iIonDamage > 0 then kind='ion' end
    local graph = Hyperspace.ShipGraph.GetShipInfo(projectile.targetId)
    local slot=0
    local sender=Hyperspace.ships(projectile.ownerId)
    if sender then
        local list=sender:GetWeaponList()
        for i=0,list:size()-1 do
            if list[i].mount.position.x==weapon.mount.position.x and list[i].mount.position.y==weapon.mount.position.y then slot=i;break end
        end
    end
    local event = {id='fire-'..tostring(id), projectile_id=tostring(projectile.selfId), weapon_slot=slot,
        source=projectile.ownerId==0 and 'player' or 'enemy', kind=kind,
        target_space=projectile.targetId,
        start=point(projectile.position), target=point(projectile.target),
        target_room=graph:GetSelectedRoom(projectile.target.x, projectile.target.y, true),
        phase='fire', duration=0.7, outcome='pending'}
    if kind=='beam' then
        event.end_point=attempt('beam_end', function() return point(projectile.target2) end, point(projectile.target))
        projectile_ids[projectile.selfId].beam=projectile
    end
    events[#events+1] = event
end)

script.on_internal_event(Defines.InternalEvents.DRONE_FIRE, function(projectile, drone)
    next_id=next_id+1
    projectile_ids[projectile.selfId]={id=next_id,start=point(projectile.position)}
    local target_ship=Hyperspace.ships(projectile.targetId)
    if target_ship and (projectile.ownerId==0 or projectile.ownerId==1) then
        local graph=Hyperspace.ShipGraph.GetShipInfo(projectile.targetId)
        local kind=projectile:GetType()==5 and 'beam' or projectile.damage.iIonDamage>0 and 'ion' or 'laser'
        local event={id='fire-'..tostring(next_id),projectile_id=tostring(projectile.selfId),
            phase='fire',outcome='pending',source=projectile.ownerId==0 and 'player' or 'enemy',
            drone_id=tostring(drone.selfId),origin_space=drone.currentSpace,
            target_space=projectile.targetId,
            kind=kind,origin_point=point(projectile.position),target=point(projectile.target),
            target_room=graph:GetSelectedRoom(projectile.target.x,projectile.target.y,true)}
        if kind=='beam' then
            projectile_ids[projectile.selfId].beam=projectile
            event.end_point=point(projectile.target2)
        end
        events[#events+1]=event
    end
    return Defines.Chain.CONTINUE
end)

-- A missed projectile can leave native space between the 10 Hz snapshots.
-- Observe the real flag after every native update and retain the result once.
script.on_internal_event(Defines.InternalEvents.PROJECTILE_UPDATE_POST,function(projectile)
    local record=projectile_ids[projectile.selfId]
    if record and projectile.missed and not record.miss_reported then
        record.miss_reported=true
        impact(projectile,'miss',projectile.targetId,projectile.target)
    end
    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.SHIELD_COLLISION, function(ship, projectile, damage, response)
    -- Actual collision responses are retained; the renderer never decides damage.
    if projectile and response.collision_type==2 then
        impact(projectile,'shield',ship.iShipId,response.point)
    end
    return Defines.Chain.CONTINUE
end)
script.on_internal_event(Defines.InternalEvents.DAMAGE_BEAM, function(ship, projectile, location, damage, newTile, beamHit)
    if projectile and newTile then impact(projectile,'beam',ship.iShipId,location) end
    return Defines.Chain.CONTINUE, beamHit
end)
script.on_internal_event(Defines.InternalEvents.DAMAGE_AREA_HIT, function(ship, projectile, location, damage, friendly)
    if projectile then
        impact(projectile,'hull',ship.iShipId,location)
    end
    return Defines.Chain.CONTINUE
end)

script.on_internal_event(Defines.InternalEvents.ON_KEY_DOWN, function(key)
    if key==Defines.SDL.KEY_F6 then supplemental_hud=true; return Defines.Chain.PREEMPT end
    if key==Defines.SDL.KEY_F7 then supplemental_hud=false; return Defines.Chain.PREEMPT end
    if key==Defines.SDL.KEY_F9 then
        Hyperspace.App:OnRequestExit()
        return Defines.Chain.PREEMPT
    end
    if key==Defines.SDL.KEY_F8 then tactical=not tactical; return Defines.Chain.PREEMPT end
    return Defines.Chain.CONTINUE
end)

-- Render callbacks also advance FTL jump animations. Keep those callbacks
-- running and clip their geometry offscreen; never skip game logic to hide it.
for _, name in ipairs({'LAYER_BACKGROUND','LAYER_FOREGROUND','LAYER_ASTEROIDS','LAYER_PLAYER','SHIP','SHIP_MANAGER','SHIP_JUMP','LAYER_FRONT'}) do
    if Defines.RenderEvents[name] then
        local active={}
        script.on_render_event(Defines.RenderEvents[name], function()
            if supplemental_hud then
                active[#active+1]=false
                -- This independent HUD pass must not update world render
                -- animations a second time. Normal render callbacks still run.
                return Defines.Chain.PREEMPT
            end
            -- Read the native state each render, including jump/event frames;
            -- snapshots are intentionally slower than the renderer.
            render_ui_only = Hyperspace.App.world.bStartedGame and not Hyperspace.App.menu.bOpen and not tactical
            active[#active+1]=render_ui_only
            if render_ui_only then
                Graphics.CSurface.GL_PushMatrix()
                -- agent.js hooks this sentinel and pushes an empty scissor.
                -- The after callback must pop both the matrix and that scissor.
                Graphics.CSurface.GL_Translate(-100000,-100000,0)
            end
            return Defines.Chain.CONTINUE
        end, function()
            if active[#active] then
                Graphics.CSurface.GL_PopMatrix()
                Graphics.CSurface.GL_PopScissor()
            end
            active[#active]=nil
        end)
    end
end
log('FTLVR_BRIDGE_READY protocol=2')
