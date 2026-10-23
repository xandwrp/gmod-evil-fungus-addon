# Evil Fungus

> A fungus for Garry's Mod that grows over everything and puts people to sleep on it.

On the [Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3821991353).

## Needs

- [Syhgma's Evil API](https://steamcommunity.com/sharedfiles/filedetails/?id=3823740816) ([source](https://github.com/xandwrp/gmod-evil-api))

Optional:

- Evil Crawling Thing, crawlers walk through it and carry spores off somewhere else
- Evil barnacles, each one grows a small patch of it around itself that joins up with the rest, and whatever they catch gets wired in and turned like a sleeper

## Spawning

Entities > Syhgma's Evil Entities > Evil Fungus. Point it at the world, not a prop.

## What it does

- Grows over floors, walls and ceilings, and feels you walking on it
- Anyone on it long enough falls asleep and slowly gets replaced
- Sleepers can be dragged off and saved for a while
- Gets smarter with every head it keeps, and learns the ways people get away
- Goes looking for bodies lying around
- Throws spores to start new patches
- Can raise some of the bodies it keeps as husks that drag people back to it, then burst into new patches somewhere high (off by default)
- Burns, gets blown apart by explosions and cut by bullets, and is scared of fire
- Eats VJ Base and ZBase NPCs too

## Settings

Spawn menu > Utilities > Syhgma's Evil Entities > Evil Fungus (superadmins), or the convars. They all start with `evil_fungus_`. Presets: normal, unhinged.

## Commands

Superadmin only.

- `evil_fungus_clear` removes every fungus on the map
- `evil_fungus_teach <heads|tactic|all> [amount]` gives every fungus heads or tricks
