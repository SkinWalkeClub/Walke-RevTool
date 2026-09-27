-- run under your executor
local R = loadstring(game:HttpGet("https://raw.githubusercontent.com/YOURNAME/revtool/main/revtool.lua"))()

-- 1. spy on remotes, then go do something in game
R.spy.start()
R.spy.onCall = function(e) print("fired:", e.name) end

-- 2. after a bit, dump everything you captured as runnable lua
task.wait(10)
print("---- captured calls ----")
print(R.spy.dumpAll())

-- refire the last call
local last = R.spy.log[#R.spy.log]
if last then R.spy.refire(last) end

-- 3. query the game
for _, p in ipairs(R.byTag(workspace, "Enemy")) do
	print("enemy:", p:GetFullName())
end

-- 4. see what a game changes when you do X
local before = R.snapshot(workspace)
task.wait(5)
local after = R.snapshot(workspace)
R.printDiff(R.diff(before, after))
