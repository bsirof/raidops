# RaidOps Alpha - design notes

Status: **scaffold only.** Nothing is implemented. This exists so that tinkering starts
at feature work instead of plumbing.

## What this is

A clean-room rewrite of RaidOps. Same three jobs as the stable build (invites, raid
groups, attendance), none of the same code.

## The one rule

**No other addon source enters this addon. Not a file, not a function, not a
copy-pasted block.** Ideas, API knowledge and lessons are fair game; text is not.

Why it matters: most WoW addons are All Rights Reserved, so a build that borrows from one
cannot be shared with anyone. This one is entirely ours, MIT licensed, and can be
published, shown to guildmates, or put on GitHub without a licensing question. That
freedom survives only while the rule does.

If you ever need to see how another addon solved something, read it, close it, and write
your own from what you understood. Do not have it open in the other window while typing.

## Coexistence

Alpha shares nothing with stable, so both can run at once:

Alpha shares no folder, global, saved variable or slash command with the previous build,
so both can be enabled at once.

| | Previous build | Alpha |
|---|---|---|
| Folder | `RaidOps` | `RaidOps_Alpha` |
| Slash | `/ro` | `/roa` |
| Saved variable | its own | `RaidOpsAlphaDB` |
| Minimap accent | amber | cyan |

Running them side by side is the point: compare behaviour without giving anything up.

## Architecture

| File | Owns |
|---|---|
| `Core.lua` | saved variables and defaults, module registry, event dispatch, slash commands |
| `UI.lua` | a small dark widget layer: panel, button, check, edit, list |
| `Config.lua` | one window, a tab per module, panes built lazily on first open |
| `Modules/*.lua` | one file per feature, each self-contained |

A module declares handlers rather than managing frames:

```lua
local module = RO:NewModule("Invites", { keywords = "inv invite 123" })
function module.events.CHAT_MSG_WHISPER(self, text, sender) ... end
function module:OnEnable() ... end
function module:BuildOptions(pane) ... end
```

Core wires the events, merges defaults into `module.db`, and wraps every handler in
`pcall` so one broken module cannot take the addon down.

`UI.lua` stays small on purpose. The stable build inherited a 229 KB widget toolkit to
render four option panes. If a widget is needed twice, add it; if once, build it inline.

## Hard-won constraints, carried over

These cost real debugging on the stable build. Do not rediscover them.

1. **Saved variables do not exist at file scope.** WoW executes an addon's Lua files
   before restoring its saved variables. Anything touching the database runs in
   `ADDON_LOADED` or later. Core already does this; keep module code inside handlers.
2. **`COMBAT_LOG_EVENT` and `COMBAT_LOG_EVENT_UNFILTERED` error on registration** in
   Midnight. None of these three features need combat data, so this addon should never
   register either.
3. **Do not gate anything on the folder name.** `GlobalAddonName == "Something"` is how
   the stable build silently lost a library export after a rename.
4. **A test that cannot fail proves nothing.** `tools/loadtest.lua` runs this addon
   headlessly under a WoW API stub. When adding a check, break the thing on purpose first
   and confirm the check catches it. Core `pcall`s module handlers, so an error in
   `OnEnable` or an event handler is only a printed line - report it through
   `RO.onModuleError` or the harness will call a broken module clean.
5. **Test under Lua 5.1, not a newer one.** WoW runs 5.1 and the differences bite: loop
   variables became const in 5.4. Use `../.tools/bin/lua5.1`.
6. **Never write into the AddOns folder while WoW is running.**

## Where the real work is

Roughly in order of difficulty:

1. **Applying a raid group layout.** `SetRaidSubgroup` and `SwapRaidSubgroup` fail
   silently when the destination subgroup is full, so this is a move-ordering problem,
   not a loop. Worth designing on paper first.
2. **Invite throttling.** Blizzard rate-limits invites; batch across frames.
3. **Attendance storage.** Decide the retention policy before writing records, or the
   saved-variable file grows without bound.
4. Everything else is straightforward.

## Testing

```
../.tools/bin/lua5.1 tools/loadtest.lua .   # headless load and init
../raidops-build.sh check-alpha             # same, through the build script
../raidops-build.sh deploy-alpha            # copy to AddOns/RaidOps_Alpha
```
