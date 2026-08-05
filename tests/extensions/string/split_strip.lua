local function assert_parts(actual, expected)
  assert(#actual == #expected)
  for index = 1, #expected do
    assert(actual[index] == expected[index])
  end
end

assert(string.strip(" \t\n\r\v\fhello \t\n") == "hello")
assert(string.strip("xyxhellozy", "xyz") == "hello")
assert(string.strip("aaaa", "a") == "")
assert(string.strip("abc", "") == "abc")
assert(string.strip("\0\0abc\0", "\0") == "abc")
assert(string.strip(" \tabc \t", nil) == "abc")
assert(string.strip("\0 abc \0") == "\0 abc \0")
assert(("  hello  "):strip() == "hello")

assert_parts(string.split("a,b,c", ","), {"a", "b", "c"})
assert_parts(string.split(",a,", ","), {"", "a", ""})
assert_parts(string.split("", ","), {""})
assert_parts(string.split("  a\tb  c  "), {"a", "b", "c"})
assert_parts(string.split("  a  b  ", nil, 1), {"a", "b  "})
assert_parts(string.split("  a  b  ", nil, 0), {"a  b  "})
assert_parts(string.split("a--b--c", "--", 1), {"a", "b--c"})
assert_parts(("a,b,c"):split(",", 1), {"a", "b,c"})

assert_parts(string.rsplit("a,b,c", ","), {"a", "b", "c"})
assert_parts(string.rsplit(",a,", ","), {"", "a", ""})
assert_parts(string.rsplit("  a  b  ", nil, 1), {"  a", "b"})
assert_parts(string.rsplit("  a  b  ", nil, 0), {"  a  b"})
assert_parts(string.rsplit("a--b--c", "--", 1), {"a--b", "c"})
assert_parts(string.split("aaa", "aa"), {"", "a"})
assert_parts(string.rsplit("aaa", "aa"), {"a", ""})

assert(#string.split("   ") == 0)
assert(#string.rsplit("   ") == 0)
assert(not pcall(string.split, "abc", ""))
assert(not pcall(string.rsplit, "abc", ""))
assert(string.rstrip == nil)

print("string extensions ok")
