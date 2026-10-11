-- Edge cases for string.strip.

local function show(label, value)
  print(label, string.format("%q", value))
end

local function show_error(label, fn, ...)
  local ok, err = pcall(fn, ...)
  print(label, ok, (tostring(err):gsub("^.*strip_edges%.lua:", "strip_edges.lua:")))
end

-- Default set: ASCII space, \t, \n, \r, \v, and \f.
show("default", string.strip(" \t\n\r\v\fx y\f\v\r\n\t "))
show("default inner", string.strip("  a  b  "))
show("default nul kept", string.strip("\0 x \0"))
print("default nbsp kept", #string.strip("\194\160x\194\160"))
show("default nil chars", string.strip("  x  ", nil))

-- Custom sets are byte sets, not prefixes/suffixes or patterns.
show("set", string.strip("abcxcba", "abc"))
show("set order", string.strip("cabxbac", "bca"))
show("set dup", string.strip("aaxaa", "aaa"))
show("set not prefix", string.strip("abxba", "ab"))
show("set keeps space", string.strip(" -x- ", "-"))
show("set with space", string.strip(" -x- ", "- "))
show("set pattern chars", string.strip("%.x.%", "%."))
show("set class", string.strip("[a]x[a]", "[]"))
show("set nul", string.strip("\0\0x\0", "\0"))
show("set high bytes", string.strip("\255x\254", "\254\255"))
show("set empty", string.strip("  x  ", ""))
show("set strips all", string.strip("abcabc", "cba"))
show("set no match", string.strip("xyz", "abc"))

-- Empty and fully stripped input.
show("empty", string.strip(""))
show("empty set", string.strip("", "abc"))
show("all space", string.strip(" \t\n "))
show("single", string.strip("x"))
show("single space", string.strip(" "))

-- Method syntax and multiple results.
show("method", ("  m  "):strip())
show("method set", ("--m--"):strip("-"))
print("result count", select("#", string.strip("  x  ")))

-- Argument errors.
show_error("nil source", string.strip)
show("number source", string.strip(12))
show_error("table source", string.strip, {})
show("number chars", string.strip("1x1", 1))
show_error("boolean chars", string.strip, "x", true)
show_error("method bad chars", function() return ("x"):strip({}) end)
