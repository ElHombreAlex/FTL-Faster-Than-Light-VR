# Controls

[Back to README](../README.md) · [Installation](INSTALLATION.md) · [Project status](STATUS.md)

The main mapping targets **Steam Frame controllers through SteamVR/OpenXR**. Other OpenXR profiles are included, but their comfort and complete button coverage have not been verified on hardware. The left hand holds navigation; the right hand points and acts.

Open **Controls / Help** on the left panel for an illustrated controller diagram. The HUD and hand panel also display contextual input hints. The diagram is drawn by [controller_help.gd](../scripts/controller_help.gd); the actual action bindings are in [openxr_action_map.tres](../openxr_action_map.tres).

## Steam Frame quick reference

| Control | Action |
|---|---|
| Right trigger | Click native HUD/menu controls, select crew, order movement or target a room |
| Right trigger held on crew | Grab a movement preview; release over a room on that crew's current ship to order movement |
| Right trigger held for a beam | Start at one enemy room and release at the beam's end room |
| Right B | Native right click on a pointed HUD control; cancel selection/grab/wheel over space |
| Right A | Toggle enemy room inspection; change category when the wheel is open |
| Right grip, held | Hold the game's Shift modifier |
| Right stick click, held | Hold the game's Ctrl modifier |
| Right bumper, held | Open the shortcut wheel |
| Right stick direction | Select a wheel slot; release bumper to confirm |
| Left Dpad Down | Open or close Tactical |
| Left View | Pause or resume |
| Left Dpad Up | Open or close System Power |
| Left Dpad Left / Right | Previous / next hand-screen page |
| Left grip, held + hand motion | Move the encounter |
| Left stick horizontal / vertical | Rotate / resize the encounter |
| Left stick click | Recenter the encounter |
| Left trigger | Return crew to stations, except on System Power |
| Right grip + left trigger | Save stations, except on System Power |

The page order is **Navigation → Tactical → Shortcuts → System Power → Jump → Help**. Navigation includes a direct **SYSTEM POWER** button as well as Shortcuts. Point at an available panel button with the right controller and pull the right trigger. Jump, Ship and Store are offered according to native game availability.

## System Power page

This page changes the contextual controls below. **Steam Frame X/Y are on the right controller.**

| Control | Action |
|---|---|
| Point at a system card | Select that system without changing its power |
| Right X / Y | Select previous / next installed powerable system |
| Left trigger | Add one native power step to the selected system |
| Left bumper | Remove one native power step |

The game decides whether a change is allowed. One engine step changes one power bar; one shield step normally changes two. Damage, ion locks, capacity, bonus power and battery power follow the actual game state. The reactor column shows **usable free reactor power after environmental limits**: storm/capped bars are marked separately, and battery availability remains a separate counter. A stationary pointer does not continuously override X/Y selection.

## Crew, doors and room targeting

- Trigger-click a crew miniature or original HUD portrait to select it. Hold right grip while selecting to add to the selection group.
- Hold the trigger on a crew member, aim at the highlighted destination floor, then release. The miniature is a preview; FTL moves the actual crew under its usual rules.
- Release over empty space to keep the selection, or use B to cancel the grab.
- Trigger-click a door or airlock to toggle it. Native locked, disabled and hacked states still apply.
- Select a weapon or targeting system first, then point at its allowed ship and trigger-click a room. Mind control, hacking and teleporters use native targeting rules, including power, cooldown and sensor restrictions.
- Tactical retains the original 2D view while allowing 3D crew, room and door interaction.

Enemy inspection reveals room roles; it does not reveal crew or hazards that FTL's sensors hide.

After a weapon target is placed, its native numbered mark stays on the room even when the targeting cursor closes. The number identifies the weapon slot: red marks indicate a single volley and yellow marks native autofire. Beam marks show both endpoints and the real sweep direction; flak marks include the native spread area. These marks remain attached while paused or while the table is moved, and disappear when the game clears the target or the encounter ends. They display your placed targets without revealing enemy weapon intent or hidden crew/system information.

## Shortcut wheel and event choices

Hold the **right bumper**, move the right stick toward a slot and release the bumper to activate it. Returning the stick to the center cancels. Right trigger confirms immediately; B cancels. Right A changes the category.

Every normal wheel opening starts with weapon slots 1–4 and drone slots 5–8. Changing category with right A applies to that opening; the next opening returns to weapons/drones. Equipped weapons/drones show their native localized names; weapon-family silhouettes and ammo captions distinguish similar equipment. Long names are clipped inside their sector, with a wider selected-name caption below. Numbers remain the original native shortcuts. Other categories provide system power and system actions. Uninstalled or unavailable entries cannot activate. When a choice event is open, the wheel becomes a choice selector for entries 1–8; original dialog controls remain pointable.

Shift and Ctrl also apply when confirming relevant wheel or shortcut commands.

| Original shortcut | VR equivalent |
|---|---|
| Shift + crew selection | Hold right grip while trigger-clicking crew |
| Shift + weapon/drone shortcut | Hold right grip while selecting its shortcut to depower |
| Shift + system power shortcut | Hold right grip while selecting its shortcut to remove power |
| Ctrl + weapon selection/target | Hold right stick click to reverse global autofire for that weapon |
| Right click | Point at the original control and press right B |

Shortcut pages include crew selection/stations, doors, autofire, installed weapons/drones and installed system actions. The original keyboard labels remain visible:

- Power: A shields, S engines, F oxygen, D medbay/clonebay, W weapons, E drones, G teleporter, H cloaking, K mind control, L hacking, Y artillery.
- Actions: Q all crew; `/` save stations; Enter return to stations; Z/X open/close doors; V autofire; C cloak; T/R send/return teleporters; N hacking; M mind control; B battery.

These are native key equivalents shown on buttons, not extra physical controller buttons.

## Navigation, windows and renaming

**Jump** opens the actual sector map above and ahead of the installed piloting room. Point at a beacon using the right controller and use the original confirmation controls. The map follows the ship's cockpit and orientation. **Close Map** returns to the encounter.

During an actual native jump, surrounding stars stretch along your ship's bow. Turning your head does not change the travel direction. Arrival restores normal stars, including when the arrival dialog opens. Opening the map or charging FTL alone does not start the stretch.

Events, Store (including BUY/SELL), upgrades, crew and equipment windows float above the player ship. Their original localized controls stay interactive. Main menus remain complete, head-relative 2D views.

Gameplay uses a **compact HUD anchored to the headset**, retaining native upper status and the crew roster while removing the lower weapons/reactor/system/subsystem strip. Use Power, Shortcuts or the wheel for those lower-strip actions. The HUD keeps a fixed readable size and follows the headset whenever there is room. If that movement would carry the panel into the ship or shield, it stops 8 cm above the ship until clearance permits headset-relative placement again. A raised or oversized table can therefore raise the panel during overlap. The hand panel retains visual and pointing priority where it overlaps the HUD. Ship, shop, pause-menu and Options windows opened during a run appear only above the ship; point at that floating panel to use them. Initial/hangar menus and desktop Tactical/map inspection keep the complete native view.

The native intruder warning keeps its lettering and subtle shadow/fringe on a transparent backdrop; neighboring HUD controls remain visible and pointable.

To rename a ship or crew member, click its original name-edit field. A floating **QWERTY keyboard** appears:

- Right trigger selects keys; Shift changes case.
- Back deletes one character; Clear empties the field.
- Done confirms; Cancel or right B restores the original name.
- Native name-length limits apply. Desktop Unicode typing is forwarded while the field is active.

The VR keyboard does not install a keyboard layout or alter Windows language settings.

## Placement and tracking

At first tracked launch the ship is placed in front of and below the headset. The encounter then stays where it was placed until moved with left grip, resized/rotated or recentered. It does not continually follow the headset. Enemy arrival retains the player anchor.

The controller panel and pointer use bounded pose smoothing. If the right controller loses tracking, a warning appears. Check SteamVR controller status and reconnect before continuing if pointing disappears.

## Desktop client

Desktop mode is useful for setup and debugging; it is not a headset performance test.

| Input | Action |
|---|---|
| Left click | Point/select/order using the native HUD and 3D scene |
| Right click | Native secondary click/cancel |
| Space | Pause/resume |
| 1–4 / 5–8 | Weapon / drone shortcuts |
| E | Inspect enemy rooms |
| R | Recenter |
| J | Open navigation |
| F8 | Toggle Tactical |
| Escape | Native menu |

Live desktop mode forwards actions to the isolated FTL process. The separate `--demo` mode provides renderer fixtures; it does not run a campaign.
