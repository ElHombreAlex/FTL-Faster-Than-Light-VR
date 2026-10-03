"""Resolve community-documented CApp signatures against the owned lab binary."""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path

import capstone


def resolve(executable: Path, signatures: Path) -> dict:
    data = executable.read_bytes()
    pe = struct.unpack_from('<I', data, 0x3C)[0]
    count = struct.unpack_from('<H', data, pe + 6)[0]
    optional_size = struct.unpack_from('<H', data, pe + 20)[0]
    sections = pe + 24 + optional_size
    code = None
    for i in range(count):
        offset = sections + i * 40
        if data[offset:offset+8].rstrip(b'\0') == b'.text':
            _, rva, length, raw = struct.unpack_from('<IIII', data, offset + 8)
            code = data[raw:raw+length]
            break
    if code is None:
        raise ValueError('Missing .text section')
    decoder = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    previous_end = 0
    hooks = {}
    for signature, name in re.findall(r'"([.0-9a-fA-F?]+)":[^\n]*\n[^\n]*CApp::(\w+)\(', signatures.read_text()):
        pattern = signature.lstrip('.')
        regex = b''.join(b'.' if pattern[i:i+2] == '??' else re.escape(bytes.fromhex(pattern[i:i+2]))
                         for i in range(0, len(pattern), 2))
        match = re.search(regex, code[previous_end if signature.startswith('.') else 0:], re.S)
        if not match:
            raise ValueError(f'No signature match for CApp::{name}')
        start = match.start() + (previous_end if signature.startswith('.') else 0)
        hooks[name] = rva + start
        previous_end = start + len(pattern) // 2
        for instruction in decoder.disasm(code[start:start+32768], rva + start):
            if instruction.mnemonic in ('ret', 'retf'):
                previous_end = instruction.address + instruction.size - rva
                break
        if name == 'OnExecute':
            break
    needed = ['OnLoop','OnRender','OnInputFocus','OnMouseMove','OnLButtonDown','OnLButtonUp','OnRButtonDown','OnRButtonUp','OnKeyDown','OnKeyUp','OnTextInput','OnTextEvent']
    if not all(name in hooks for name in needed):
        raise ValueError('Missing required input/render hooks')
    # Modifier getters are documented in the matching CEvent signature file.
    # Resolve independently and require uniqueness; never use a guessed address.
    event_source = (signatures.parent/'CEvent.zhl').read_text()
    for signature, name in re.findall(r'"([.0-9a-fA-F?]+)":[^\n]*\n[^\n]*CEvent::(GetShiftState|GetCtrlState)\(', event_source):
        pattern=signature.lstrip('.')
        regex=b''.join(b'.' if pattern[i:i+2]=='??' else re.escape(bytes.fromhex(pattern[i:i+2]))
                       for i in range(0,len(pattern),2))
        matches=list(re.finditer(regex,code,re.S))
        if len(matches)!=1: raise ValueError(f'Ambiguous modifier signature: {name}')
        hooks[name]=rva+matches[0].start()
        needed.append(name)
    if not all(name in hooks for name in ('GetShiftState','GetCtrlState')):
        raise ValueError('Missing native modifier getters')
    text_source=(signatures.parent/'TextInput.zhl').read_text()
    for signature,name in re.findall(r'"([.0-9a-fA-F?]+)":[^\n]*\n[^\n]*TextInput::(OnRender|GetActive|Start)\(',text_source):
        pattern=signature.lstrip('.')
        regex=b''.join(b'.' if pattern[i:i+2]=='??' else re.escape(bytes.fromhex(pattern[i:i+2]))
                       for i in range(0,len(pattern),2))
        matches=list(re.finditer(regex,code,re.S))
        if len(matches)!=1: raise ValueError(f'Ambiguous TextInput signature: {name}')
        hook_name='TextInput'+name
        hooks[hook_name]=rva+matches[0].start()
        needed.append(hook_name)
    if not all(name in hooks for name in ('TextInputGetActive','TextInputOnRender','TextInputStart')):
        raise ValueError('Missing native text-entry hooks')
    active_offset=hooks['TextInputGetActive']-rva
    first=next(decoder.disasm(code[active_offset:active_offset+16],hooks['TextInputGetActive']))
    if first.mnemonic!='movzx' or first.op_str!='eax, byte ptr [ecx + 0x38]':
        raise ValueError('Native TextInput active flag offset changed')
    # Independent HUD render pass uses only UI methods; no second game/world
    # render advances ship, jump or projectile animations.
    for class_name,method_names in {'CommandGui':('RenderStatic','RenderPause'),
                                   'TabbedWindow':('OnRender',),'ChoiceBox':('OnRender',),
                                   'MouseControl':('OnRender',),'StarMap':('OnRender',)}.items():
        source=(signatures.parent/(class_name+'.zhl')).read_text()
        for signature,name in re.findall(r'"([.0-9a-fA-F?]+)":[^\n]*\n[^\n]*'+class_name+r'::(\w+)\(',source):
            if name not in method_names: continue
            pattern=signature.lstrip('.')
            regex=b''.join(b'.' if pattern[i:i+2]=='??' else re.escape(bytes.fromhex(pattern[i:i+2]))
                           for i in range(0,len(pattern),2))
            matches=list(re.finditer(regex,code,re.S))
            if len(matches)!=1: raise ValueError(f'Ambiguous HUD signature: {class_name}::{name}')
            hook_name=class_name+name
            hooks[hook_name]=rva+matches[0].start()
            needed.append(hook_name)
        if not all(class_name+name in hooks for name in method_names):
            raise ValueError('Missing isolated native HUD render hooks for '+class_name)
    def method_address(class_name,name):
        source=(signatures.parent/(class_name+'.zhl')).read_text()
        signature=re.search(r'"([.0-9a-fA-F?]+)":[^\n]*\n[^\n]*'+class_name+r'::'+name+r'\(',source).group(1)
        pattern=signature.lstrip('.')
        regex=b''.join(b'.' if pattern[i:i+2]=='??' else re.escape(bytes.fromhex(pattern[i:i+2]))
                       for i in range(0,len(pattern),2))
        matches=list(re.finditer(regex,code,re.S))
        if len(matches)!=1: raise ValueError(f'Ambiguous structure probe: {class_name}::{name}')
        return rva+matches[0].start()
    command_loop=method_address('CommandGui','OnLoop')
    system_loop=method_address('SystemControl','OnLoop')
    instructions=list(decoder.disasm(code[command_loop-rva:command_loop-rva+4096],command_loop))
    system_offsets=[]
    for index,instruction in enumerate(instructions):
        if instruction.mnemonic=='call' and instruction.op_str==hex(system_loop):
            previous=instructions[index-1]
            match=re.fullmatch(r'ecx, \[ebx \+ (0x[0-9a-f]+)\]',previous.op_str)
            if previous.mnemonic=='lea' and match: system_offsets.append(int(match.group(1),16))
    if system_offsets!=[0x320]: raise ValueError('CommandGui SystemControl offset changed')
    app_loop=list(decoder.disasm(code[hooks['OnLoop']-rva:hooks['OnLoop']-rva+4096],hooks['OnLoop']))
    app_offsets=[]
    for index,instruction in enumerate(app_loop):
        if instruction.mnemonic=='call' and instruction.op_str==hex(command_loop):
            previous=app_loop[index-1]
            if previous.mnemonic=='mov' and previous.op_str=='ecx, dword ptr [ebx + 8]':app_offsets.append(8)
    if app_offsets!=[8]: raise ValueError('CApp GUI pointer offset changed')
    get_id=method_address('ShipSystem','GetId')
    get_id_start=next(decoder.disasm(code[get_id-rva:get_id-rva+8],get_id))
    if get_id_start.mnemonic!='mov' or get_id_start.op_str!='eax, dword ptr [ecx + 0x40]':
        raise ValueError('ShipSystem id offset changed')
    get_box=method_address('SystemControl','GetSystemBox')
    box_code=list(decoder.disasm(code[get_box-rva:get_box-rva+180],get_box))
    if not any(i.mnemonic=='mov' and i.op_str=='ecx, dword ptr [eax + 0x4c]' for i in box_code):
        raise ValueError('SystemBox system pointer offset changed')
    # Position and vector offsets follow the documented win32 SystemControl
    # and SystemBox structures; the surrounding method accesses are verified.
    offsets={'app_gui':8,'gui_system_control':system_offsets[0],'system_control_position':0x28,
             'system_control_boxes':8,'system_box_position':4,'system_box_system':0x4c,'system_id':0x40}
    # Both key handlers set/clear the same force_autofire flag. Validate the
    # instructions before exposing its read-only diagnostic address.
    def flag_addresses(name, value):
        start=hooks[name]-rva
        addresses=[]
        for instruction in decoder.disasm(code[start:start+600],hooks[name]):
            if instruction.mnemonic=='mov' and instruction.op_str.startswith('byte ptr [0x') and instruction.op_str.endswith(', '+str(value)):
                absolute=int(instruction.op_str.split('[0x')[1].split(']')[0],16)
                addresses.append(absolute-struct.unpack_from('<I',data,pe+24+28)[0])
        return addresses
    flags=set(flag_addresses('OnKeyDown',1)) & set(flag_addresses('OnKeyUp',0))
    if len(flags)!=1: raise ValueError('Ambiguous force_autofire state flag')
    hooks['ForceAutofireFlag']=flags.pop()
    needed.append('ForceAutofireFlag')
    return {'sha1': hashlib.sha1(data).hexdigest(), 'rvas': {name: hooks[name] for name in needed},'offsets':offsets}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('executable', type=Path)
    parser.add_argument('signatures', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = resolve(args.executable, args.signatures)
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))
