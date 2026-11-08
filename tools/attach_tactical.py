"""Generate a candidate from a current owner file. Never edit the input in place."""
from pathlib import Path
import argparse
import hashlib
import json

MARKER = '-- MIDBOT T024 optional tactical attachment'
FOOTER = '''
-- MIDBOT T024 optional tactical attachment
do
    local ok, helper = pcall(require, GetScriptDirectory() .. "/laning/tactical/entry");
    if ok then
        local loaded, attached, reason = pcall(helper.BindLegacy, getfenv(1));
        if not loaded or not attached then print("[MIDBOT tactical] attach_skipped " .. tostring(reason or attached)) end;
    else print("[MIDBOT tactical] module_unavailable") end;
end;
'''

def attach(source):
    if MARKER in source: return source
    for name in ('AbilityUsageThink', 'ItemUsageThink', 'ConsiderRequiem', 'CastRaze'):
        if f'function {name}(' not in source: raise ValueError('Missing owner callback: ' + name)
    return source.rstrip() + '\n' + FOOTER

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.source.resolve()==args.output.resolve(): raise ValueError('Source cannot be replaced in place')
    if args.output.exists(): raise ValueError('Choose a new output; existing files are not overwritten')
    original=args.source.read_bytes(); updated=attach(original.decode('utf-8-sig')).encode('utf-8')
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_bytes(updated)
    print(json.dumps({'candidate':str(args.output),'input_sha256':hashlib.sha256(original).hexdigest(),
                      'output_sha256':hashlib.sha256(updated).hexdigest(),'installed':False}))
if __name__=='__main__':main()
