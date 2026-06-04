#include <lua.h>
#include <lauxlib.h>
#include <sys/time.h>

// -- build
// gcc -shared -fPIC -o meti.so meti.c $(pkg-config --cflags lua5.5)

// same as socket.gettime
static int l_gettime(lua_State* L) {
	struct timeval v;
	gettimeofday(&v, NULL);
	lua_pushnumber(L, (double)v.tv_sec + (double)v.tv_usec / 1.0e6);
	return 1;
}

// export as function
int luaopen_meti(lua_State* L) {
	lua_pushcfunction(L, l_gettime);
	return 1;
}
