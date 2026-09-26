# RaidOps Alpha

A small, dark, raid-leading addon for World of Warcraft: invites, raid group layouts,
and attendance. Nothing else.

**Status: early.** Raid splitting works end to end. Invites and attendance are still
stubs.

Written from scratch, because the author wanted something small enough to actually
understand. MIT licensed; do what you like with it.

## Design

Three ideas, and they are the whole thing.

**One file per feature.** A module registers itself, declares event handlers, and builds
its own options pane. Core wires everything up and wraps every handler in `pcall`, so a
broken module cannot take the addon down with it.

```lua
local module = RO:NewModule("Invites", { keywords = "inv invite 123" })

function module.events.CHAT_MSG_WHISPER(self, text, sender) ... end
function module:OnEnable() ... end
function module:BuildOptions(pane) ... end
```

**A UI layer you can read in one sitting.** `UI.lua` is under 200 lines: panel, button,
checkbox, edit box, recycling list. Flat, dark, no art files, no third-party library. Add
a widget when it is needed twice.

**No dependencies.** No Ace, no LibStub, no embedded libraries at all.

| File | Owns |
|---|---|
| `Core.lua` | saved variables and defaults, module registry, event dispatch, slash commands |
| `UI.lua` | the widget layer |
| `Config.lua` | one window, a tab per module, panes built on first open |
| `Modules/` | one file per feature |

## Commands

| | |
|---|---|
| `/roa` | open the options window |
| `/roa help` | list commands |
| `/roa debug` | toggle debug output |
| `/roa perf` | what the damage meter is reporting |
| `/roa perf store` | recorded averages per player |
| `/roa split [2-4]` | preview a balanced split; nothing moves |
| `/roa split apply` | run the preview against the live raid |

## Testing without the game

`tools/loadtest.lua` runs the addon headlessly under a WoW API stub: it reads the TOC,
executes every file in load order with the varargs the game passes, then fires
`ADDON_LOADED`, `PLAYER_LOGIN`, drains timers and builds every options pane.

```bash
lua5.1 tools/loadtest.lua .
lua5.1 tools/splittest.lua .
```

Two things make the stub useful rather than a rubber stamp, both learned the hard way:

- **Unknown widget keys resolve as methods only when they carry a widget-method prefix.**
  A stub that returns a function for every key breaks the ubiquitous
  `self.X = self.X or self:CreateTexture()`, because the field reads truthy and the addon
  stores a function where it wanted a texture.
- **A global the addon assigns through `_G` must hold a real value at the end of the run.**
  Otherwise a failed export is indistinguishable from a working one, since the stub
  cheerfully invents whatever is read.

## Notes for anyone building a WoW addon

Collected from debugging a previous build, and worth more than the code here.

1. **Saved variables do not exist at file scope.** WoW executes an addon's Lua files
   before restoring its saved variables. Anything touching the database belongs in
   `ADDON_LOADED` or later. A `pcall` around an early return hides this perfectly.
2. **Do not gate anything on `GlobalAddonName`.** Comparing against a folder name means
   renaming the folder silently disables code.
3. **`COMBAT_LOG_EVENT` and `COMBAT_LOG_EVENT_UNFILTERED` error on registration** as of
   Midnight. Do not register them unless combat data is genuinely needed.
4. **`SetRaidSubgroup` and `SwapRaidSubgroup` fail silently when the destination subgroup
   is full.** Applying a group layout is a move-ordering problem, not a loop.
5. **A test that cannot fail proves nothing.** Break it on purpose first.

`DESIGN.md` has the rest.

## License

MIT.
