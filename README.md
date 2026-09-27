<p align="center">
  <img src="https://media.discordapp.net/attachments/1553563238220955658/1553599334434476073/walke_revtool.png?ex=6ab9d5a1&is=6ab88421&hm=f9a2d9bdc7f26b4db8f7fa4a8baad44d90549eb8222a8a030c03efaaaf7f32c3&=&format=webp&quality=lossless&width=640&height=640" width="600" alt="Walke Serializer">
</p>

# Walke RevTool

Reverse a Roblox game fast. Spy on its remotes and get every call back as **runnable Lua**, query the DataModel without writing loops, and snapshot → diff to see exactly what a game changed

Three things you do constantly when reversing a game, in one small library.

## Load it

```lua
local R = loadstring(game:HttpGet("https://raw.githubusercontent.com/SkinWalkeClub/revtool/main/revtool.lua"))()
```

## Remote spy

Hook every remote the client fires and read them as copy-paste code:

```lua
R.spy.start()

-- ... play the game, press the button you care about ...

print(R.spy.dumpAll())
--> game:GetService("ReplicatedStorage"):FindFirstChild("BuyItem"):FireServer("Sword", 3)
--> game:GetService("ReplicatedStorage"):FindFirstChild("Attack"):InvokeServer(Vector3.new(0, 5, 0))
```

Every logged call is an entry in `R.spy.log`:

```lua
local e = R.spy.log[#R.spy.log]
print(R.spy.export(e))   -- the call as runnable lua
R.spy.refire(e)          -- fire it again exactly as captured
```

- `R.spy.ignore["Ping"] = true` — stop logging a noisy remote
- `R.spy.onCall = function(e) ... end` — callback on every captured call
- `R.spy.max = 500` — ring-buffer cap
- `R.spy.clear()`

The arg dumper rebuilds Vector3 / CFrame / Color3 / UDim2 / Enum / instances / nested tables, so what you copy out actually runs.

## Query the DataModel

Stop writing `GetDescendants` loops:

```lua
R.byClass(workspace, "Part")            -- every Part
R.byName(workspace, "Ammo")             -- everything named Ammo
R.byTag(workspace, "Enemy")             -- CollectionService tag
R.byAttr(workspace, "Team", "Red")      -- attribute match
R.qfirst(workspace, { name = "Boss" })  -- first match

R.q(workspace, {                        -- combine anything
	class = "Part",
	attr = { Locked = true },
	predicate = function(o) return o.Transparency < 1 end,
})
```

## Snapshot → diff

See what a game does under the hood: snapshot, trigger something, snapshot again, diff.

```lua
local before = R.snapshot(workspace)
-- ... buy an item / take damage / whatever ...
local after = R.snapshot(workspace)
R.printDiff(R.diff(before, after))
--> [revtool] +1 -0 ~2
-->   + Workspace.DroppedItem (Part)
-->   ~ Workspace.Player.Humanoid.Health: 100 -> 75
-->   ~ Workspace.Door.CanCollide: true -> false
```

`R.diff` returns `{ added, removed, changed }` if you want to handle it yourself. Pass your own property list to `R.snapshot(root, { "Health", "CFrame" })` to focus the diff.

## Requirements

- **Spy**: needs `hookmetamethod`, or `getrawmetatable` + `setreadonly` (any half-decent executor has these). If they're missing, `R.spy.start()` returns `false, reason` instead of erroring.
- **Query / snapshot / diff**: pure Lua, work anywhere (even off Roblox — the whole logic core is tested against a mock runtime).

## Limits

- The spy captures **outgoing** calls (`FireServer` / `InvokeServer`) — what your client sends. Server → client (`FireClient`) isn't hooked in v0.1.
- Snapshots key instances by `GetFullName`, so two siblings with the same name can collide in a diff. Rename or scope your root if that bites you.
- The dumper can't serialize functions or userdata it doesn't recognize; those come out as a `nil --[[type]]` marker.

## License

MIT.
