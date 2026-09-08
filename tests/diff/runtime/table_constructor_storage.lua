-- expect: pass
-- stage: runtime
-- feature: tables
-- normalize: none

for i = 1, 100 do
  local t = { nil, i, nil, i + 2, a = i, b = i + 1, c = i + 2, d = i + 3 }
  assert(t[1] == nil and t[2] == i and t[3] == nil and t[4] == i + 2)
  assert(t.a == i and t.b == i + 1 and t.c == i + 2 and t.d == i + 3)
  t.e = i + 4
  t.a = nil
  t.a = i + 5
  assert(t.a == i + 5 and t.e == i + 4)

  local writes = 0
  setmetatable(t, { __newindex = function(table, key, value)
    writes = writes + 1
    rawset(table, key, value)
  end })
  t.f = i
  t.a = nil
  t.a = i
  t[1] = i
  assert(writes == 3 and t.f == i and t.a == i and t[1] == i)
  collectgarbage("step", 0)
  assert(t[2] == i and t[4] == i + 2 and t.e == i + 4)

  -- Replacing an integer key already stored by a keyed constructor field
  -- must expose only the final value to lookup and iteration.
  local replaced = { [2] = -1, nil, i }
  local count = 0
  for key, value in pairs(replaced) do
    assert(key == 2 and value == i)
    count = count + 1
  end
  assert(count == 1)
end
print("table constructor storage ok")
