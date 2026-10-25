# QuickQuest

> World of Warcraft **3.3.5a (WotLK)** addon · made by **feralpaw**

> **Important: QuickQuest needs the guide pack [QuickQuest_Guides](https://github.com/Feralpaw69/QuickQuest_Guides) to work.**
> QuickQuest itself contains no guides - download and install **both** folders, otherwise the guide list stays empty.

World of Warcraft **3.3.5a (WotLK)** leveling addon: step-by-step guides from level 1 to 80 with a direction arrow, waypoints on the world map and minimap, quest item buttons and target buttons.
<img width="975" height="569" alt="image" src="https://github.com/user-attachments/assets/60a68c56-7a17-45c3-ad4e-c845af145aa7" />

## Features
- Guide window with the current step, its tasks and the next steps
- Direction arrow with distance (right-click to skip a waypoint)
- Waypoints on the world map and the minimap
- Buttons for quest items and for the NPCs / enemies of the current step, plus the character macro **QQ Target**
- Accepts and turns in the quests of the guide (hold Shift to do it yourself)
- Experience rates for private servers: server rate, heirlooms and your own buffs (5x with +20% and +50% = 9x)
- Skips quests that are far below your level (and quests whose pre quest was skipped)
- Suggests a guide for your level when you outlevel the current one
- Colour themes, Blizzard or pixel frame style
- Options under *Esc → Interface → AddOns → QuickQuest*

## Commands
| Command | What it does |
|---|---|
| `/qq` | Show / hide the guide window |
| `/qq guides` | Choose a guide |
| `/qq next`, `/qq prev` | Skip forward / go back one step |
| `/qq options` | Open the options |
| `/qq lock` | Lock / unlock frames |
| `/qq reset` | Reset frame positions |

## Installation
1. Download **QuickQuest** (this addon) **and** **QuickQuest_Guides** (the guide pack - required!).
2. Copy both folders, `QuickQuest` and `QuickQuest_Guides`, into `World of Warcraft/Interface/AddOns/`.
   With *Code → Download ZIP* each folder sits inside `<repo name>-main` – copy only the inner folder.
3. Restart the game and make sure both are enabled in the addon list.

Without QuickQuest_Guides the addon loads, but there are no guides to choose.

## Licenses
- Addon code and graphics (`Core.lua`, `Engine/`, `UI/`, `Media/`, `tools/`): MIT, see [LICENSE](LICENSE).
- Guides: not part of this addon. They are in the separate pack **QuickQuest_Guides**, based on [RestedXP Guides](https://github.com/RestedXP/RXPGuides) (CC BY-NC-SA 4.0, not for commercial use).
- Map and area data (`Data/Maps.lua`, `Data/AreaNames.lua`): generated from the 3.3.5a client tables (WorldMapArea, DungeonMap, WorldMapTransforms, AreaTable, Map) with `tools/mapdata.py`.
- Quest data (`Data/QuestData.lua`): generated with `tools/questdata.py` from the [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) world database (GPL-2.0).
