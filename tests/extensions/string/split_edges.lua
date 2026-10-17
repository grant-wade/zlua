-- Edge cases for string.split and string.rsplit.

local function show(label, parts)
  local quoted = {}
  for index = 1, #parts do
    quoted[index] = string.format("%q", parts[index])
  end
  print(label, #parts, table.concat(quoted, " "))
end

local function show_error(label, fn, ...)
  local ok, err = pcall(fn, ...)
  print(label, ok, (tostring(err):gsub("^.*split_edges%.lua:", "split_edges.lua:")))
end

-- maxsplit: 0 means no split, negative means unlimited, larger than the
-- number of separators returns every piece.
show("split max=0", string.split("a,b,c", ",", 0))
show("rsplit max=0", string.rsplit("a,b,c", ",", 0))
show("split max=-1", string.split("a,b,c", ",", -1))
show("split max=-5", string.split("a,b,c", ",", -5))
show("rsplit max=-1", string.rsplit("a,b,c", ",", -1))
show("split max=1", string.split("a,b,c", ",", 1))
show("rsplit max=1", string.rsplit("a,b,c", ",", 1))
show("split max=2", string.split("a,b,c", ",", 2))
show("split max=10", string.split("a,b,c", ",", 10))
show("rsplit max=10", string.rsplit("a,b,c", ",", 10))
show("split max=nil", string.split("a,b,c", ",", nil))
show("split max=2.0", string.split("a,b,c", ",", 2.0))
show("split max='1'", string.split("a,b,c", ",", "1"))
show("split max=maxint", string.split("a,b", ",", math.maxinteger))
show("split max=minint", string.split("a,b", ",", math.mininteger))

-- Whitespace mode with maxsplit.
show("ws max=0", string.split("  a b  ", nil, 0))
show("rws max=0", string.rsplit("  a b  ", nil, 0))
show("ws max=-1", string.split("  a b  c ", nil, -1))
show("ws max=1", string.split(" a  b  c ", nil, 1))
show("rws max=1", string.rsplit(" a  b  c ", nil, 1))
show("ws max=2", string.split("a b c d", nil, 2))
show("rws max=2", string.rsplit("a b c d", nil, 2))
show("ws max=9", string.split("a b", nil, 9))
show("ws max=0 blank", string.split("   ", nil, 0))

-- Leading and trailing separators keep empty fields.
show("lead", string.split(",a", ","))
show("trail", string.split("a,", ","))
show("both", string.split(",a,", ","))
show("only sep", string.split(",", ","))
show("only seps", string.split(",,,", ","))
show("rsplit only seps", string.rsplit(",,,", ","))
show("lead max=1", string.split(",a,b", ",", 1))
show("rtrail max=1", string.rsplit("a,b,", ",", 1))

-- Multi-byte separators are matched without overlap.
show("multi", string.split("a::b::c", "::"))
show("rmulti", string.rsplit("a::b::c", "::", 1))
show("multi lead", string.split("::a::", "::"))
show("overlap", string.split("aaaa", "aa"))
show("roverlap", string.rsplit("aaaaa", "aa"))
show("sep longer", string.split("ab", "abc"))
show("sep equal", string.split("abc", "abc"))
show("sep missing", string.split("abc", ","))

-- Separators are plain text, not Lua patterns.
show("plain dot", string.split("a.b.c", "."))
show("plain percent", string.split("a%sb c", "%s"))
show("plain class", string.split("a[,]b,c", "[,]"))
show("plain anchor", string.split("^a^b", "^"))

-- Empty inputs.
show("empty sep", string.split("", ","))
show("empty rsep", string.rsplit("", ","))
show("empty ws", string.split(""))
show("empty rws", string.rsplit(""))
show("empty max=0", string.split("", ",", 0))

-- Whitespace mode splits on ASCII space, \t, \n, \r, \v, and \f only.
show("ws kinds", string.split("a\tb\nc\rd\ve\ff g"))
local nbsp = string.split("a\194\160b")
print("ws nbsp", #nbsp, #nbsp[1])
show("ws nul", string.split("a\0b c"))

-- Embedded zero bytes are ordinary separator bytes.
show("nul sep", string.split("a\0b\0c", "\0"))

-- Method syntax.
show("method", ("x-y-z"):split("-"))
show("rmethod", ("x-y-z"):rsplit("-", 1))

-- Argument errors.
show_error("empty separator", string.split, "abc", "")
show_error("rsplit empty separator", string.rsplit, "abc", "")
show_error("method empty separator", function() return ("abc"):split("") end)
show("number source", string.split(123, "2"))
show_error("nil source", string.split)
show_error("table source", string.rsplit, {}, ",")
show("number separator", string.split("a1b", 1))
show_error("boolean separator", string.split, "a b", false)
show_error("string maxsplit", string.split, "a,b", ",", "x")
show_error("float maxsplit", string.split, "a,b", ",", 1.5)
show_error("table maxsplit", string.rsplit, "a,b", ",", {})
