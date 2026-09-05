#include <assert.h>
#include <stdio.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

static void run(lua_State *L, const char *source) {
  if (luaL_dostring(L, source) != LUA_OK) {
    fprintf(stderr, "%s\n", lua_tostring(L, -1));
    assert(0);
  }
}

int main(void) {
  lua_State *L = luaL_newstate();
  assert(L != NULL);
  luaL_openlibs(L);
  run(L,
      "leaf = {answer = 42, [1] = 'array', [20] = 'sparse'}; "
      "graph = {left = leaf, right = leaf, [leaf] = leaf}; "
      "graph.self = graph; leaf.parent = graph; "
      "setmetatable(graph, {__index = leaf, owner = graph}); "
      "local node = graph; "
      "for i = 1, 8 do node = {left = node, right = node} end; "
      "diamond = node");

  lua_getglobal(L, "leaf");
  const int leaf = lua_absindex(L, -1);
  const void *identity = lua_topointer(L, leaf);
  lua_getglobal(L, "graph");
  const int graph = lua_absindex(L, -1);
  lua_pushvalue(L, leaf);
  lua_rawget(L, graph);
  assert(lua_rawequal(L, -1, leaf));
  lua_pop(L, 1);
  lua_getmetatable(L, graph);
  lua_getfield(L, -1, "owner");
  assert(lua_rawequal(L, -1, graph));
  lua_pop(L, 2);

  /* Mutating a linked C peer must be visible through every Lua alias. */
  lua_pushinteger(L, 43);
  lua_setfield(L, leaf, "answer");
  lua_pushnil(L);
  lua_rawseti(L, leaf, 1);
  lua_pushstring(L, "updated");
  lua_pushnumber(L, 20.0);
  lua_insert(L, -2);
  lua_rawset(L, leaf);
  run(L,
      "assert(graph.left == leaf and graph.right == leaf); "
      "assert(graph[leaf] == leaf and graph.self == graph); "
      "assert(graph.answer == 43 and leaf[1] == nil and leaf[20] == 'updated'); "
      "local node = diamond; for i = 1, 8 do "
      "assert(node.left == node.right); node = node.left end; "
      "assert(node == graph); "
      "leaf.answer = nil; leaf[1] = 'restored'; leaf[20] = nil; "
      "leaf.added = 99; collectgarbage()");

  /* Later traversals must not reuse a stale 'already visited' decision. */
  assert(lua_topointer(L, leaf) == identity);
  lua_getfield(L, leaf, "answer");
  assert(lua_isnil(L, -1));
  lua_pop(L, 1);
  lua_rawgeti(L, leaf, 1);
  assert(lua_type(L, -1) == LUA_TSTRING);
  lua_pop(L, 1);
  lua_rawgeti(L, leaf, 20);
  assert(lua_isnil(L, -1));
  lua_pop(L, 1);
  lua_getfield(L, leaf, "added");
  assert(lua_tointeger(L, -1) == 99);
  lua_pop(L, 1);
  int count = 0;
  lua_pushnil(L);
  while (lua_next(L, leaf)) {
    count++;
    lua_pop(L, 1);
  }
  assert(count == 3); /* parent, 1, added; no duplicate normalized keys */
  lua_close(L);
  puts("shared graph synchronized");
  return 0;
}
