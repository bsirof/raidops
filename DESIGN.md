# RaidOps Alpha - design notes

Status: **one feature built.** Raid splitting balanced on recorded throughput works
end to end; invites and attendance are still stubs.

## What this is

A rewrite of RaidOps. Same three jobs as the stable build - invites, raid groups,
attendance - built from nothing.

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

## Modern by default

**Solve each problem the way the current client wants it solved.** Not on principle -
because the modern surface is smaller, faster, and less code to own.

The stable build's upstream is old - it predates most of the client surface described
below and has been maintained forward across many expansions. That is a strength for it
and an opening for us: a lot of what it hand-built, Blizzard now ships. Counted in files,
across the other addons installed on this machine versus that build's own 50 Lua files:

| Pattern | Other addons | The stable build |
|---|---|---|
| `Settings.Register*` | 26 | 1 |
| `ScrollUtil` / `CreateScrollBoxList*` | 22 | 0 |
| `CreateFramePool` / `CreateObjectPool` | 42 | 1 |
| `CreateFromMixins` | 97 | 1 |
| `EventRegistry` | 35 | 0 |
| `SetResizeBounds` | 35 | 1 |

That build is not badly written, it is *early*. It predates most of that surface, and
rewriting working code to chase an API is a bad trade for a live addon with users. We have no such
constraint: nothing here is written yet, the target is one interface version, and we
should start where the client already is.

### What follows from it

**Options belong in Blizzard's Settings panel, not in a window of ours.** This is the
big one, and it points straight at `Config.lua`. A custom window with a tab sidebar is
the same architectural decision the stable build made, only smaller. The current answer hands each
pane to the client:

```lua
local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
Settings.RegisterAddOnCategory(category)
```

That deletes the window, the sidebar, the tab strip and all of their state, and users
find this addon where they find every other one. `/roa` still opens it, through
`Settings.OpenToCategory(category)`.

**Lists are ScrollBox, not hand-scrolled frames.** Two of the three features are lists -
a raid roster and an attendance history. The stable build has zero uses of `ScrollUtil`
and drives `SetVerticalScroll` by hand instead. The current pattern recycles rows, manages the
scrollbar, and is a fraction of the code:

```lua
local view = CreateScrollBoxListLinearView()
view:SetElementExtent(rowHeight)
view:SetElementInitializer("Button", initRow)
ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
```

**Rows come from a pool.** `CreateFramePool` for roster rows. Frames are never destroyed
in WoW, so a 40-row roster rebuilt on every `GROUP_ROSTER_UPDATE` leaks frames unless
they are reused.

**Namespaced APIs, no compatibility shims.** The stable build is full of
`C_Item and C_Item.GetItemInfo or GetItemInfo`, because it supports clients back to
Classic. This addon targets one interface version, so call `C_PartyInfo.InviteUnit`,
`C_AddOns.GetAddOnMetadata` and `C_DateAndTime` directly. If the TOC ever grows a second
interface version, revisit; until then a shim is noise pretending to be caution.

**Mixins over closures for anything stateful.** `CreateFromMixins` is how the client
composes behaviour, and it leaves a widget's methods inspectable rather than captured.

### Two cautions

Not everything newer is better, and none of this is a licence to chase APIs.

- **A canvas category is not a floating window.** `Settings` gives us a blank frame
  inside Blizzard's panel, not a movable, resizable window that can sit open next to the
  raid frames during a pull. If that turns out to matter for raid-time use, keeping our
  own frame is a legitimate answer. Decide it before building, not after.
- **Modern does not excuse untested.** Every constraint below still applies, and this
  surface is new to the harness: `tools/wowstub.lua` currently stubs none of `Settings`,
  `ScrollUtil`, `CreateScrollBoxListLinearView`, `CreateFramePool` or `EventRegistry`.
  The universal stub will absorb those calls and return a stub rather than erroring,
  which means a pane that never really registers can still look like a pass. Extending
  the stub is part of adopting each of these, not follow-up work - see constraint 4.

## Architecture

| File | Owns |
|---|---|
| `Core.lua` | saved variables and defaults, module registry, event dispatch, slash commands |
| `UI.lua` | a small dark widget layer: panel, button, check, edit, list |
| `Config.lua` | one window, a tab per module, panes built lazily on first open |
| `Modules/Perf.lua` | per-player DPS and HPS from `C_DamageMeter`, averaged across the night |
| `Modules/Groups.lua` | balancing a split, and the move ordering that applies it |
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
   variables became const in 5.4, so correct code fails under a current Lua. Any real 5.1
   works; this workspace keeps one at `../.tools/bin/lua5.1`.
6. **Never write into the AddOns folder while WoW is running.**

## Where the real work is

Roughly in order of difficulty:

1. ~~**Applying a raid group layout.**~~ Done, in `Groups.PlanMoves`. Both subgroup
   calls fail silently when the destination holds five, so the solver moves people
   into space where there is space and swaps where there is not. The termination
   argument is in the comment above the function, and the stub reproduces the silent
   failure so a bad ordering fails the tests rather than the raid.
2. **Invite throttling.** Blizzard rate-limits invites; batch across frames.
3. **Attendance storage.** Decide the retention policy before writing records, or the
   saved-variable file grows without bound.
4. **Saved group layouts.** `Groups` can compute and apply a split but cannot yet save
   a named layout, load one, or import and export as text.
5. Everything else is straightforward.

## Testing

```
lua5.1 tools/loadtest.lua .                 # headless load and init, any real 5.1
lua5.1 tools/splittest.lua .                # Perf and Groups behaviour
../raidops-build.sh check-alpha             # both, through the build script
../raidops-build.sh deploy-alpha            # copy to AddOns/RaidOps_Alpha
```

`tools/harness.lua` loads the addon and hands back its namespace, so a behavioural
test can reach inside without duplicating the loader.

`tools/splittest.lua` is where constraint 4 is taken seriously. Its stub reproduces the
things that make this code hard rather than papering over them: `SetRaidSubgroup`
refuses a full subgroup without complaining, and `C_DamageMeter` returns pets and
sources with no per-second figure. Every check in it has been run against a
deliberately broken implementation and confirmed to fail. Ten faults were injected
while it was written; each one was caught.
