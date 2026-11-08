"""Isolated Lua 5.1 tests; optional current ability callback supplied for integration."""
from pathlib import Path
import argparse
import os
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--ability-source', type=Path)
args = parser.parse_args()
source = args.ability_source.resolve() if args.ability_source else None
os.chdir(root)
lua = LuaRuntime(unpack_returned_tuples=True)
if source:
    lua.globals().ABILITY_TEST_SOURCE = str(source)
lua.execute((root / 'tests/social/kill_chat_test.lua').read_text(encoding='utf-8'))
