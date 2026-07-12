# Scroll Transmog
<p align="center">
<img src="https://github.com/zyggy123/warmane-like-transmogrification/blob/main/icon.png" width="200" />
</p>

Item-based transmogrification system for AzerothCore 3.3.5a using Eluna (Lua scripts).

Players use **scrolls** dropped by raid bosses to extract and apply item appearances — no NPC, no core patch, no client modification required.

[![License](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)
[![AzerothCore](https://img.shields.io/badge/AzerothCore-3.3.5a-brightgreen)](https://www.azerothcore.org/)
[![Eluna](https://img.shields.io/badge/Eluna-required-orange)](https://github.com/azerothcore/mod-eluna)

## Description

Traditional transmogrification uses an NPC with a gossip menu. This module replaces that with **consumable scrolls** that work like profession recipes:

| Item | Purpose |
|------|---------|
| **Scroll of Deception** | Extract the appearance of a non-Legendary item into an Essence |
| **Scroll of Illusion** | Extract the appearance of a **Legendary** item into an Essence |
| **Scroll of Purification** | Remove a transmogrification, restoring the original look |
| **Essence** | Holds one extracted appearance; use it on a compatible item to apply |

**How it works:**
1. Right-click a scroll → cursor becomes a targeting glow
2. Click a soulbound armor/weapon (equipped or in bags)
3. An Essence is created (source item is **not** destroyed; scroll is consumed)
4. Right-click the Essence and click a compatible equipped item → appearance applied

**Key features:**
- Server-side only — uses `PLAYER_VISIBLE_ITEM_*` update fields, so any stock 3.3.5a client sees the appearances
- No core modifications, no client patches, no addons
- Scrolls drop from all raid bosses (Naxx, Ulduar, ICC, etc.) in the loot window
- Scrolls are **tradeable** (can be sold on AH); Essences are **Bind on Pickup**
- Compatibility rules: armor must match slot; weapons must match category (1H/2H/ranged/etc.)
- Stats, item level, enchants never change — visual only

## Requirements

- [AzerothCore 3.3.5a](https://github.com/azerothcore/azerothcore-wotlk) (master branch)
- [mod-eluna](https://github.com/azerothcore/mod-eluna) or mod-ale installed and active
- MySQL/MariaDB access to `acore_world` and `acore_characters` databases

## Installation

### 1. SQL — World Database

Run these files in `acore_world` in order:

```bash
mysql -u root -p acore_world < sql/01_world_transmog_items.sql
mysql -u root -p acore_world < sql/03_world_boss_loot.sql
mysql -u root -p acore_world < sql/04_world_scroll_binding.sql  # optional
```

- **`01_world_transmog_items.sql`** — Creates the four item templates (23885, 35517, 24315, 38567)
- **`03_world_boss_loot.sql`** — Adds scrolls to all raid boss loot tables (10N/10H/25N/25H). Edit `@DECEPTION_CHANCE` / `@ILLUSION_CHANCE` at the top (default 100%). Safe to re-run after changes.
- **`04_world_scroll_binding.sql`** — *Optional.* Default: scrolls are tradeable. Uncomment Variant B to make them Bind on Pickup instead.

### 2. SQL — Character Database

Run in `acore_characters`:

```bash
mysql -u root -p acore_characters < sql/02_characters_transmog_tables.sql
```

Creates two tables for persistence (`custom_transmogrification`, `essence_tracking`).

### 3. Lua Script

Copy the Lua script to your server:

```bash
cp lua_script/scroll_transmog.lua /path/to/azerothcore/lua_scripts/
```

### 4. Restart & Client Cache

- Restart the worldserver (item templates are cached at startup)
- Have players delete `Cache/WDB` in their WoW 3.3.5a client directory (otherwise they see stale item tooltips)

**That's it!** Scrolls will now drop from raid bosses and players can use them.

## Configuration

All settings are in the `C` table at the top of `scroll_transmog.lua`:

```lua
DEBUG = false               -- Verbose logging (GMs can toggle in-game: "transmog debug")
DROP_MODE = "loot"          -- "loot" | "onkill" | "off"
NORMAL_CHANCE = 0.08        -- Used only in "onkill" mode (8%)
LEGENDARY_CHANCE = 0.01     -- Used only in "onkill" mode (1%)
RAID_MAPS = { ... }         -- Used only in "onkill" mode
BOSS_ENTRIES = { }          -- Leave empty for auto-population in "onkill" mode
```

### Drop Modes

- **`"loot"` (default)** — Scrolls appear in the **boss loot window** via `creature_loot_template`. Configured by `sql/03_world_boss_loot.sql`. Covers 194 boss loot tables across 8 raids (all difficulties).
- **`"onkill"`** — Script rewards **only the killing player** directly, using `NORMAL_CHANCE` / `LEGENDARY_CHANCE`. Boss entries are auto-populated from the world DB at startup (all difficulties included).
- **`"off"`** — No boss rewards; distribute scrolls via vendors, quests, vote rewards, etc.

**Important:** If you switch to `"onkill"` mode, remove the loot rows:
```sql
DELETE FROM creature_loot_template WHERE Item IN (23885, 35517);
```

## Uninstallation

```bash
# Remove boss loot only (keep items):
mysql -u root -p acore_world < sql/99_world_remove_boss_loot.sql

# Full world DB cleanup (removes items + loot):
mysql -u root -p acore_world < sql/99_world_uninstall_all.sql

# Full character DB cleanup (removes all transmog data):
mysql -u root -p acore_characters < sql/99_characters_uninstall_all.sql
```

Delete `lua_scripts/scroll_transmog.lua` and restart the worldserver.

## How It Works (Technical)

- **Appearance storage:** `custom_transmogrification` table stores (item GUID → fake entry ID → owner GUID)
- **Essence tracking:** `essence_tracking` table stores (essence item GUID → appearance entry + source class/subclass/invtype for compatibility checks)
- **Client sync:** At equip time (`PLAYER_EVENT_ON_EQUIP`), the script updates `PLAYER_VISIBLE_ITEM_X_ENTRYID` with the fake entry. The client renders that model. Stats, item level, enchants, and the real item never change.
- **Scroll mechanics:** Item use is intercepted via `RegisterItemEvent(entry, 2, callback)`. The spell on the item (47147) is never actually cast — it only provides the targeting cursor. All validation (soulbound, compatibility, ownership) happens server-side in Lua.

## Credits

- **Author:** Zyggy (based on concepts from Rochet2's classic Eluna Transmogrifier)
- **License:** GNU Affero General Public License v3.0
- **AzerothCore:** [https://www.azerothcore.org/](https://www.azerothcore.org/)
- **Eluna Engine:** [https://github.com/azerothcore/mod-eluna](https://github.com/azerothcore/mod-eluna)

Visible-item override technique inspired by Rochet2's NPC-based transmogrifier. Rewritten as a scroll/essence consumable flow for a more immersive, item-driven experience.

## Support

- **AzerothCore Discord:** [https://discord.gg/gkt4y2x](https://discord.gg/gkt4y2x)
- **Forum:** [AzerothCore Forum](https://github.com/azerothcore/azerothcore-wotlk/discussions)

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the [GNU AGPL-3.0](LICENSE) - see the LICENSE file for details.
