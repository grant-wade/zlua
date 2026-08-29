#include <stdio.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

int main(void) {
  lua_State *L = luaL_newstate();
  lua_getglobal(L, "_G");
  printf("global_before_open=%s\n", lua_typename(L, lua_type(L, -1)));
  lua_pop(L, 1);
  luaL_openlibs(L);

  lua_getglobal(L, "_G");
  lua_getfield(L, -1, "_G");
  printf("global_self=%d\n", lua_rawequal(L, -1, -2));
  lua_pop(L, 2);

  lua_getglobal(L, "package");
  lua_getfield(L, -1, "loaded");
  lua_getfield(L, -1, "package");
  printf("package_identity=%d\n", lua_rawequal(L, -1, -3));
  lua_pop(L, 3);

  lua_newtable(L);
  const void *cycle = lua_topointer(L, -1);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "self");
  lua_pushvalue(L, -1);
  lua_setglobal(L, "cycle");
  lua_pop(L, 1);

  if (luaL_dostring(L, "cycle.answer = 42; return cycle") != LUA_OK) {
    fprintf(stderr, "%s\n", lua_tostring(L, -1));
    lua_close(L);
    return 1;
  }
  lua_getfield(L, -1, "self");
  lua_getfield(L, -2, "answer");
  printf("cycle_identity=%d self_identity=%d answer=%lld\n",
      lua_topointer(L, -3) == cycle,
      lua_rawequal(L, -2, -3),
      (long long)lua_tointeger(L, -1));
  lua_pop(L, 3);

  lua_close(L);
  return 0;
}
