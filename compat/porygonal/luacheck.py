#!/usr/bin/env python3
"""Syntax-check Lua files with the engine's own lua51.dll (LuaJIT).

There is no standalone Lua on this machine, but the Gen1 Recomp build ships
the interpreter LOVE uses.  Loading a chunk without running it is exactly the
compile step the mod loader performs, so this catches a syntax error before
the game does -- and before a broken adapter reads as "Porygonal found no
renderer", which is what a load failure looks like from the outside.

    python luacheck.py <file.lua> [...]
"""

import ctypes
import os
import sys

DLL = (r"C:\Users\breno\Downloads\GBA\Quiver-Windows-x64\Apps"
       r"\PokemonRedBlueYellow-Gen1RecompProject-Recomp\lua51.dll")


def check(lua, path):
    with open(path, "rb") as handle:
        source = handle.read()

    state = lua.luaL_newstate()
    if not state:
        raise RuntimeError("could not create a Lua state")
    try:
        name = ("@" + os.path.basename(path)).encode("utf-8")
        # 0 == LUA_OK
        status = lua.luaL_loadbuffer(state, source, len(source), name)
        if status == 0:
            return None
        lua.lua_tolstring.restype = ctypes.c_char_p
        message = lua.lua_tolstring(state, -1, None)
        return (message or b"unknown error").decode("utf-8", "replace")
    finally:
        lua.lua_close(state)


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    directory = os.path.dirname(DLL)
    if hasattr(os, "add_dll_directory") and os.path.isdir(directory):
        os.add_dll_directory(directory)
    lua = ctypes.CDLL(DLL)
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p,
                                    ctypes.c_size_t, ctypes.c_char_p]
    lua.lua_close.argtypes = [ctypes.c_void_p]
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int,
                                  ctypes.c_void_p]

    bad = 0
    for path in argv[1:]:
        error = check(lua, path)
        if error:
            bad += 1
            print("FAIL %s\n     %s" % (path, error))
        else:
            print("ok   %s" % path)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
