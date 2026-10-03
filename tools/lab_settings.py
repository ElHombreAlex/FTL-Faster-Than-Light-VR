"""Set only the isolated lab's canvas and reserved virtual store hotkey."""
import re


def configure(lab):
    path=lab/'settings.ini'
    text=path.read_text() if path.exists() else ''
    values={'fullscreen':0,'last_fullscreen':0,'manual':1,'screen_x':1280,
            'screen_y':720,'windowed':1,'stretched':0,'store':291,'pause':32,
            'weapon1':49,'weapon2':50,'weapon3':51,'weapon4':52,
            'crew_all':113,'loadPositions':13,'savePositions':47,'autofire':118,
            'open':122,'close':120,'force_autofire':306,
            'shields':97,'engines':115,'oxygen':102,'medbay':100,'weapons':119,'drones':101,
            'teleporter':103,'cloaking':104,'mind':107,'hacking':108,'artillery':121,
            'activate_cloak':99,'send_tele':116,'ret_tele':114,'start_hacking':110,
            'mindControl':109,'activate_battery':98}
    for key,value in values.items():
        pattern=rf'(?m)^{key}=.*$'
        if re.search(pattern,text): text=re.sub(pattern,f'{key}={value}',text)
        else: text+=f'\n{key}={value}\n'
    path.write_text(text)
