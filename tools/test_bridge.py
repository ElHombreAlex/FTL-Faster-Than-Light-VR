import json
import tempfile
import time
import unittest
from pathlib import Path
from PIL import Image

import numpy as np
from hud_alpha import clear_world_alpha, clear_supplemental_hud_alpha
from run_bridge import (decode_state_line, translate_command, full_screen_capture,apply_end_screen,
                        remove_enemy_hud, native_window_frame, remove_pause_overlay,
                        FRAME_HEADER, raw_frame_bytes, FramePublisher)


class BridgeTests(unittest.TestCase):
    def test_results_override_stale_native_modal_flags(self):
        state={'ready':True,'ui_mode':'game','panel_open':True,'tactical':True,
               'map_open':True,'event_open':True,'transition':True}
        apply_end_screen(state,True)
        self.assertTrue(full_screen_capture(state))
        self.assertTrue(state['blocking_ui'])
        for key in ('panel_open','tactical','map_open','event_open','transition'):
            self.assertFalse(state[key])
        fresh={'ready':True,'ui_mode':'game'}
        apply_end_screen(fresh,False)
        self.assertFalse(full_screen_capture(fresh))

    def test_beam_free_endpoints_keep_subroom_precision_and_drag_movement(self):
        state={'ready':True,'ui_mode':'game','combat':True,'weapon_selected':0,
               'targeting':{'active':True,'kind':'weapon','ships':['enemy']},
               'player':{'weapons':[{'slot':0,'kind':'beam'}]},
               'enemy_origin':{'x':900,'y':105},
               'enemy':{'ship_image':{'x':-20,'y':-10,'w':250,'h':350},
                        'rooms':[{'id':3,'x':0,'y':0,'w':35,'h':70,'center':{'x':17.5,'y':35}}]}}
        data={'room_id':-1,'ship':'enemy','point':{'x':72.25,'y':103.75}}
        for phase in ('down','up','move'):
            commands=translate_command({'action':'target_room','data':dict(data,phase=phase)},state)
            actual=commands[0]
            self.assertEqual((actual['x'],actual['y']),(972,209))
            self.assertEqual(actual['type'],'move' if phase=='move' else 'mouse')
            if phase=='up':
                self.assertEqual([c['phase'] for c in commands],['up','click'])
                self.assertTrue(all(c['x']==972 and c['y']==209 for c in commands))
        for point in ({'x':float('nan'),'y':20},{'x':True,'y':20},{'x':800,'y':20},'bad'):
            with self.assertRaises(ValueError):
                translate_command({'action':'target_room','data':dict(data,point=point)},state)
        state['targeting']['kind']='mind'
        with self.assertRaises(ValueError):translate_command({'action':'target_room','data':data},state)
        state['targeting']['kind']='weapon';state['player']['weapons'][0]['kind']='laser'
        with self.assertRaises(ValueError):translate_command({'action':'target_room','data':data},state)

    def test_empty_native_drone_equipment_does_not_erase_weapons(self):
        weapons=[{'slot':0,'name':'MISSILES_2','title':'Artemis Missiles','ammo_cost':1},
                 {'slot':1,'name':'LASER_BURST_3','title':'Burst Laser Mark II','ammo_cost':0}]
        raw={'protocol':2,'source':'hyperspace','ready':True,
             'player':{'weapons':weapons,'drone_equipment':{},'crew':{},'drones':{}}}
        normalized=decode_state_line('FTLVR_STATE '+json.dumps(raw))
        self.assertEqual(normalized['player']['drone_equipment'],[])
        self.assertEqual(normalized['player']['weapons'],weapons)

    def test_raw_transport_keeps_dimensions_rgba_orientation_and_timestamp(self):
        image=Image.new('RGBA',(960,540),(10,20,30,40))
        image.putpixel((0,0),(1,2,3,4));image.putpixel((0,539),(5,6,7,8))
        raw=raw_frame_bytes(image,12,123.5)
        self.assertEqual(FRAME_HEADER.size,36)
        self.assertEqual(FRAME_HEADER.unpack(raw[:36]),(b'FVR1',1,960,540,4,12,123.5))
        self.assertEqual(len(raw),36+960*540*4)
        self.assertEqual(raw[36:40],bytes((1,2,3,4)))
        self.assertEqual(raw[36+539*960*4:40+539*960*4],bytes((5,6,7,8)))

    def test_independent_raw_streams_publish_without_waiting_for_png_preview(self):
        with tempfile.TemporaryDirectory() as directory:
            publisher=FramePublisher(Path(directory))
            image=Image.new('RGBA',(16,9),(10,20,30,40))
            try:
                for i in range(8):publisher.publish('screen_frame',image,float(i))
                publisher.publish('hud_frame',image,8.)
                raw=(Path(directory)/'screen_frame.rgba').read_bytes()
                self.assertEqual(FRAME_HEADER.unpack(raw[:36])[-2:],(8,7.))
                self.assertTrue((Path(directory)/'hud_frame.rgba').exists())
                deadline=time.monotonic()+1
                while not (Path(directory)/'hud_frame.png').exists() and time.monotonic()<deadline:time.sleep(.01)
                self.assertTrue((Path(directory)/'hud_frame.png').exists())
            finally:publisher.close()

    def test_jump_and_pending_events_never_become_full_screen(self):
        base={'ready':True,'ui_mode':'screen'}
        self.assertFalse(full_screen_capture(base))
        for key in ('transition','event_pending','event_open','map_open','tactical'):
            self.assertFalse(full_screen_capture(dict(base,**{key:True})),key)
        self.assertTrue(full_screen_capture({'ready':False,'ui_mode':'menu'}))
        self.assertTrue(full_screen_capture({'ready':True,'ui_mode':'menu'}))
        self.assertFalse(full_screen_capture(dict(base,panel_open=True,panel_kind='shop')))

    def test_in_run_modal_window_never_duplicates_on_full_headset_screen(self):
        for kind in ('ship', 'window', 'options', 'sell'):
            with self.subTest(kind=kind):
                self.assertFalse(full_screen_capture({'ready':True,'ui_mode':'menu',
                                                     'panel_open':True,'panel_kind':kind}))
        self.assertTrue(full_screen_capture({'ready':False,'ui_mode':'menu','panel_open':True}))

    def test_enemy_frame_removed_without_touching_player_widgets(self):
        pixels=np.full((720,1280,4),255,dtype=np.uint8)
        result=remove_enemy_hud(pixels)
        self.assertEqual(result[48,879,3],0)
        self.assertEqual(result[588,1273,3],0)
        self.assertEqual(result[590,1279,3],0,'Right-edge target separator must never survive')
        self.assertEqual(result[605,1150,3],255,'Player subsystem strip must remain')
        self.assertEqual(result[100,70,3],255)
        self.assertTrue(np.array_equal(result[:,:,:3],pixels[:,:,:3]))

    def test_window_frame_keeps_native_black_ink_and_discards_hud(self):
        pixels=np.zeros((720,1280,4),dtype=np.uint8)
        pixels[120:610,300:980,:3]=[120,180,190]
        pixels[135:595,315:965,:3]=0
        pixels[40:75,20:280,:3]=[100,200,180]
        result=native_window_frame(pixels)
        self.assertEqual(result[360,640,3],255)
        self.assertEqual(result[120,300,3],255)
        self.assertEqual(result[50,70,3],0)

    def test_sell_drop_box_and_item_tooltip_are_retained(self):
        pixels=np.zeros((720,1280,4),dtype=np.uint8)
        pixels[100:600,340:940,:3]=[160,190,185]
        pixels[115:585,355:925,:3]=0
        pixels[190:385,65:325,:3]=[160,190,185]
        pixels[202:372,77:313,:3]=0
        pixels[160:280,945:1265,:3]=[160,190,185]
        pixels[172:268,957:1253,:3]=0
        pixels[155:190,5:95,:3]=[20,36,30]
        pixels[610:710,240:650,:3]=[100,180,150]
        result=native_window_frame(pixels)
        self.assertEqual(result[300,195,3],255,'Native SELL drop target must remain visible')
        self.assertEqual(result[200,1100,3],255,'Native item tooltip must remain visible')
        self.assertEqual(result[200,50,3],0,'Separate crew HUD must be removed')
        self.assertEqual(result[640,400,3],0,'Separate weapon HUD must be removed')
        self.assertEqual(result[650,640,3],0)
        self.assertTrue(np.array_equal(result[:,:,:3],pixels[:,:,:3]))
        pixels[120:610,300:980,:3]=0
        self.assertFalse(np.any(native_window_frame(pixels)[:,:,3]))

    def test_sell_window_survives_transparent_center_and_separate_content(self):
        pixels=np.zeros((720,1280,4),dtype=np.uint8)
        pixels[120:126,300:980,:3]=[120,170,175]
        pixels[120:610,300:306,:3]=[120,170,175]
        pixels[120:610,974:980,:3]=[120,170,175]
        pixels[604:610,300:600,:3]=[120,170,175]
        pixels[420:450,600:700,:3]=[220,200,180]
        pixels[30:75,20:280,:3]=[100,200,180]
        result=native_window_frame(pixels)
        self.assertEqual(result[360,640,3],0)
        self.assertEqual(result[120,300,3],255)
        self.assertEqual(result[430,650,3],255)
        self.assertEqual(result[50,70,3],0)

    def test_cached_native_pause_glyph_is_removed_without_cutting_controls(self):
        pixels=np.full((720,1280,4),255,dtype=np.uint8)
        result=remove_pause_overlay(pixels)
        self.assertEqual(result[552,640,3],0)
        self.assertEqual(result[620,640,3],255)
        self.assertEqual(result[400,70,3],255)

    def test_panel_open_gap_does_not_retain_dim_native_pause_glyph(self):
        pixels=np.zeros((720,1280,4),dtype=np.uint8)
        pixels[100:550,340:930,:3]=[170,210,200]
        pixels[115:535,355:915,:3]=0
        pixels[540:598,790:915,:3]=[170,210,200]
        pixels[553:585,803:902,:3]=0
        pixels[560:577,550:730,:3]=[26,39,42]
        result=native_window_frame(pixels)
        self.assertFalse(np.any(result[560:577,550:730,3]))
        self.assertEqual(result[570,850,3],255,'Native close button ink must remain')

    def test_native_text_entry_requires_active_context_and_uses_text_events(self):
        state={'text_entry':{'active':True,'id':'entry-3','text':'Kestrel','max_length':16}}
        command={'action':'text_input','data':{'entry_id':'entry-3','op':'insert','text':'A é'}}
        result=translate_command(command,state)
        self.assertEqual([x['codepoint'] for x in result],[65,32,233])
        self.assertTrue(all(x['type']=='text' and x['entry_id']=='entry-3' for x in result))
        for op,value in [('backspace',3),('confirm',0)]:
            command['data']={'entry_id':'entry-3','op':op}
            self.assertEqual(translate_command(command,state)[0]['event'],value)
        command['data']={'entry_id':'entry-3','op':'cancel'}
        self.assertEqual(translate_command(command,state)[0]['type'],'text_cancel')
        command['data']['entry_id']='entry-2'
        with self.assertRaises(ValueError):translate_command(command,state)
        for entry_id in (None, ''):
            command['data']['entry_id']=entry_id
            with self.assertRaises(ValueError):translate_command(command,state)
        command['data'].pop('entry_id')
        with self.assertRaises(ValueError):translate_command(command,state)
        state['text_entry']['active']=False
        command['data']['entry_id']='entry-3'
        with self.assertRaises(ValueError):translate_command(command,state)

    def test_door_uses_native_center_and_rejects_locked_or_enemy_door(self):
        state={'ready':True,'ui_mode':'game','player_origin':{'x':380,'y':116},
               'player':{'doors':[{'id':4,'x':175,'y':192,'controllable':True}]}}
        command={'action':'door_toggle','data':{'door_id':4,'ship':'player'}}
        result=translate_command(command,state)
        self.assertEqual((result[0]['x'],result[0]['y']),(555,308))
        self.assertEqual(result[0]['phase'],'click')
        state['player']['doors'][0]['controllable']=False
        with self.assertRaises(ValueError): translate_command(command,state)
        command['data']['ship']='enemy'
        with self.assertRaises(ValueError): translate_command(command,state)

    def test_drone_render_space_is_independent_of_owning_ship(self):
        raw={'protocol':2,'source':'hyperspace',
             'player':{'drones':[{'id':'9','owner':0,'space':1,'is_space':True}]},
             'enemy':{'drones':{}}}
        state=decode_state_line('FTLVR_STATE '+json.dumps(raw))
        self.assertEqual(state['player']['drones'],[])
        self.assertEqual(state['enemy']['drones'][0]['owner'],0)
        self.assertEqual(state['player']['doors'],[])

    def test_event_wheel_rejects_stale_and_disabled_choices(self):
        state={'ready':True,'ui_mode':'game','event_open':True,
               'dialog':{'id':'7','choices':[{'enabled':True},{'enabled':False}]}}
        command={'action':'event_choice','data':{'index':0,'dialog_id':'7'}}
        self.assertEqual(translate_command(command,state)[0]['key'],49)
        command['data']['dialog_id']='6'
        with self.assertRaises(ValueError): translate_command(command,state)
        command['data'].update(dialog_id='7',index=1)
        with self.assertRaises(ValueError): translate_command(command,state)
        with self.assertRaises(ValueError): translate_command({'action':'select_crew','data':{'crew_id':'crew-1'}},state)

    def test_modifiers_reach_every_input_phase(self):
        commands=translate_command({'action':'ui_mouse','data':{'x':70,'y':30,'phase':'down',
            'modifiers':{'shift':True,'control':True}}},{})
        self.assertEqual(commands[0]['modifiers'],{'shift':True,'control':True})
        self.assertEqual(translate_command({'action':'key','data':{'key':49}}, {})[0]['modifiers'],
            {'shift':False,'control':False})
        with self.assertRaises(ValueError):
            translate_command({'action':'key','data':{'key':49,'modifiers':{'alt':True}}},{})

    def test_unavailable_navigation_is_rejected(self):
        state={'ready':True,'ui_mode':'game','navigation':{'jump':True,'store':False},
               'jump_button':{'x':530,'y':20}}
        with self.assertRaises(ValueError): translate_command({'action':'navigate','data':{'screen':'store'}},state)
        self.assertEqual(translate_command({'action':'navigate','data':{'screen':'jump'}},state)[0]['x'],555)

    def test_alpha_preserves_enclosed_black_ui_ink_and_rgb(self):
        pixels=np.zeros((20,30,4),dtype=np.uint8)
        pixels[4:16,6:24,:3]=[125,180,190]
        pixels[7:12,10:16,:3]=0
        result=clear_world_alpha(pixels)
        self.assertEqual(result[0,0,3],0)
        self.assertEqual(result[9,12,3],255)
        self.assertTrue(np.array_equal(result[:,:,:3],pixels[:,:,:3]))

    def test_supplemental_warning_keeps_text_and_native_faint_shadow_coverage(self):
        pixels=np.zeros((720,1280,4),dtype=np.uint8)
        # Native warning glyphs with a barely visible red-black texture fringe.
        pixels[210:270,675:785]=[1,0,0,2]
        pixels[215:223,690:770]=[86,18,10,43]
        pixels[235:243,683:777]=[86,18,10,43]
        pixels[255:263,683:777]=[86,18,10,43]
        result=clear_supplemental_hud_alpha(pixels)
        self.assertEqual(result[212,680,3],2,'Warning shadow must retain its faint native alpha')
        self.assertEqual(result[218,700,3],255,'Native warning text must retain its existing visibility')
        self.assertTrue(np.array_equal(result[:,:,:3],pixels[:,:,:3]))

    def test_supplemental_warning_fade_and_scaled_native_capture(self):
        pixels=np.zeros((720,1280,4),dtype=np.uint8)
        pixels[210:270,675:785]=[1,0,0,1]
        pixels[216:222,690:770]=[20,4,2,1]
        for sample in (pixels,pixels[::2,::2]):
            result=clear_supplemental_hud_alpha(sample)
            scale=pixels.shape[0]//sample.shape[0]
            self.assertEqual(result[212//scale,680//scale,3],1)
            self.assertEqual(result[218//scale,700//scale,3],255,'Faded warning glyph RGB must not be multiplied by raw alpha twice')
            self.assertTrue(np.array_equal(result[:,:,:3],sample[:,:,:3]))

    def test_supplemental_warning_conversion_preserves_controls_and_normal_frames(self):
        pixels=np.zeros((720,1280,4),dtype=np.uint8)
        pixels[15:65,15:200,:3]=[125,180,190]
        pixels[25:55,25:190,:3]=0
        pixels[620:690,295:700,:3]=[125,180,190]
        pixels[632:678,307:688,:3]=0
        pixels[212:222,345:355]=[1,0,0,2]
        pixels[190:200,610:760]=[1,0,0,2]
        pixels[195:198,640:690]=[150,180,190,255]
        expected=clear_world_alpha(pixels)
        result=clear_supplemental_hud_alpha(pixels)
        self.assertTrue(np.array_equal(result,expected),'A normal HUD must keep the legacy control alpha')
        self.assertEqual(result[40,70,3],255,'Black ink inside top controls must remain opaque')
        self.assertEqual(result[650,640,3],255,'Black weapon panel ink must remain opaque')

    def test_empty_lua_vectors_become_arrays(self):
        state=decode_state_line('FTLVR_STATE '+json.dumps({'protocol':2,'source':'hyperspace',
            'shots':{},'projectiles':{},'player':{'rooms':{},'crew':{},'weapons':{}}}))
        self.assertEqual(state['player']['crew'],[])
        self.assertEqual(state['shots'],[])

    def test_native_target_points_survive_empty_lua_vectors(self):
        targets=[{'x':102,'y':134},{'x':177,'y':134}]
        raw={'protocol':2,'source':'hyperspace','player':{'weapons':[
            {'slot':0,'targets':{},'target_ship':1},
            {'slot':1,'targets':targets,'target_ship':1}]}}
        state=decode_state_line('FTLVR_STATE '+json.dumps(raw))
        self.assertEqual(state['player']['weapons'][0]['targets'],[])
        self.assertEqual(state['player']['weapons'][1]['targets'],targets)

    def test_native_room_target_includes_enemy_screen_offset(self):
        state={'ready':True,'ui_mode':'game','combat':True,'weapon_selected':1,
            'enemy_origin':{'x':953,'y':105},
            'enemy':{'rooms':[{'id':3,'center':{'x':70,'y':192}}]}}
        result=translate_command({'action':'target_room','data':{'room_id':3}},state)
        self.assertEqual((result[0]['x'],result[0]['y']),(1023,297))
        state['weapon_selected']=-1
        with self.assertRaises(ValueError): translate_command({'action':'target_room','data':{'room_id':3}},state)

    def test_targeted_systems_and_tactical_use_native_room_inputs(self):
        state={'ready':True,'ui_mode':'screen','tactical':True,'combat':True,'weapon_selected':-1,
               'enemy_origin':{'x':950,'y':105},'player_origin':{'x':380,'y':115},
               'enemy':{'rooms':[{'id':3,'center':{'x':70,'y':192}}]},
               'player':{'rooms':[{'id':5,'center':{'x':175,'y':157}}]}}
        command={'action':'target_room','data':{'room_id':3,'ship':'enemy'}}
        for kind in ('mind','hacking','teleporter','weapon'):
            state['targeting']={'active':True,'kind':kind,'ships':['enemy']}
            result=translate_command(command,state)
            self.assertEqual((result[0]['x'],result[0]['y']),(1020,297))
            self.assertEqual(result[0]['type'],'mouse')
        state['targeting']={'active':True,'kind':'mind','ships':['player','enemy']}
        command['data']={'room_id':5,'ship':'player'}
        self.assertEqual(translate_command(command,state)[0]['x'],555)
        state['blocking_ui']=True
        with self.assertRaises(ValueError):translate_command(command,state)
        state['blocking_ui']=False;state['map_open']=True
        with self.assertRaises(ValueError):translate_command(command,state)
        state['map_open']=False;state['targeting']['active']=False
        with self.assertRaises(ValueError):translate_command(command,state)

    def test_system_power_uses_native_icons_and_never_forces_modifiers(self):
        state={'ready':True,'ui_mode':'screen','tactical':True,
               'player':{'system_status':[{'id':0,'key':'shields','powerable':True,
                   'power_button':{'x':90,'y':684}},{'id':8,'key':'doors','powerable':False}]}}
        command={'action':'system_power','data':{'system_id':0,'direction':1,
                                                'modifiers':{'shift':True,'control':True}}}
        result=translate_command(command,state)[0]
        self.assertEqual((result['x'],result['y'],result['button']),(90,684,'left'))
        self.assertEqual(result['modifiers'],{'shift':False,'control':False})
        command['data']={'system_key':'shields','direction':-1}
        self.assertEqual(translate_command(command,state)[0]['button'],'right')
        for data in ({'system_id':8,'direction':1},{'system_id':0,'direction':0}):
            command['data']=data
            with self.assertRaises(ValueError):translate_command(command,state)
        state['player']['system_status'][0].pop('power_button')
        command['data']={'system_id':0,'direction':1}
        with self.assertRaises(ValueError):translate_command(command,state)

    def test_ui_bounds_and_hotkey_whitelist(self):
        with self.assertRaises(ValueError): translate_command({'action':'ui_mouse','data':{'x':1280,'y':3}}, {})
        with self.assertRaises(ValueError): translate_command({'action':'key','data':{'key':9999}}, {})

    def test_boarding_crew_uses_current_ship_not_ownership(self):
        raw={'protocol':2,'source':'hyperspace','ready':True,'ui_mode':'game',
            'player':{'crew':[{'id':'crew-1','owner':0,'ship':1,'controllable':True,'x':70,'y':175}]},
            'enemy':{'rooms':[{'id':3,'center':{'x':70,'y':192}}]},
            'enemy_origin':{'x':953,'y':105}}
        state=decode_state_line('FTLVR_STATE '+json.dumps(raw))
        self.assertEqual(state['player']['crew'],[])
        self.assertEqual(state['enemy']['crew'][0]['owner'],0)
        commands=translate_command({'action':'move_crew','data':{'crew_id':'crew-1','room_id':3}},state)
        self.assertEqual((commands[-1]['x'],commands[-1]['y']),(1023,297))
        self.assertEqual(commands[-1]['button'],'right')


if __name__=='__main__': unittest.main()
