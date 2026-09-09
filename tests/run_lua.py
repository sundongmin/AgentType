#!/usr/bin/env python3
"""Test-only runner: use LuaSkin bundled with Hammerspoon, no running app needed."""
import ctypes
import os
from pathlib import Path

root = Path(__file__).resolve().parents[1]
library = os.environ.get("GIM_TEST_LUA_LIBRARY", "/Applications/Hammerspoon.app/Contents/Frameworks/LuaSkin.framework/Versions/A/LuaSkin")
lua = ctypes.CDLL(library)
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lua.luaL_loadstring.restype = ctypes.c_int
lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
lua.lua_pcallk.restype = ctypes.c_int
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]

def quote(text):
    return '"' + str(text).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'

state = lua.luaL_newstate()
if not state:
    raise RuntimeError("Unable to initialize Lua")
lua.luaL_openlibs(state)
try:
    source = "arg={[1]=" + quote(root / 'GhosttyInputMethod.spoon/init.lua') + "}; dofile(" + quote(root / 'tests/test_state.lua') + ")"
    result = lua.luaL_loadstring(state, source.encode())
    if not result:
        result = lua.lua_pcallk(state, 0, -1, 0, 0, None)
    if result:
        raise RuntimeError(lua.lua_tolstring(state, -1, None).decode())
finally:
    lua.lua_close(state)
