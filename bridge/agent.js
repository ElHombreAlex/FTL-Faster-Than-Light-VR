// Runs only inside the fingerprinted, owned FTL lab process.
// RVAs are resolved from the Hyperspace project's documented CApp signatures.
const config = CONFIG_PLACEHOLDER;
if (Process.arch !== 'ia32') throw new Error('FTL lab must be x86');
const base = Process.mainModule.base;
// Hyperspace 1.23.2 mistakenly matches its supported --force-opengl flag
// against the legacy -opengl warning. Acknowledge only that lab-owned dialog.
const user = Process.getModuleByName('user32.dll');
const enumWindows = new NativeFunction(user.getExportByName('EnumWindows'),'int',['pointer','pointer'],'stdcall');
const enumChildren = new NativeFunction(user.getExportByName('EnumChildWindows'),'int',['pointer','pointer','pointer'],'stdcall');
const windowPid = new NativeFunction(user.getExportByName('GetWindowThreadProcessId'),'uint',['pointer','pointer'],'stdcall');
const windowText = new NativeFunction(user.getExportByName('GetWindowTextW'),'int',['pointer','pointer','int'],'stdcall');
const dialogId = new NativeFunction(user.getExportByName('GetDlgCtrlID'),'int',['pointer'],'stdcall');
const sendMessage = new NativeFunction(user.getExportByName('SendMessageW'),'pointer',['pointer','uint','pointer','pointer'],'stdcall');
let warningText = '', warningButton = null;
const visitChild = new NativeCallback((h,l) => {
    const text=Memory.alloc(4096); windowText(h,text,2048);
    warningText += text.readUtf16String();
    if (dialogId(h)===100 && text.readUtf16String()==='OK') warningButton=h;
    return 1;
},'int',['pointer','pointer'],'stdcall');
const visitWindow = new NativeCallback((h,l) => {
    const pid=Memory.alloc(4); windowPid(h,pid);
    if (pid.readU32()!==Process.id) return 1;
    warningText=''; warningButton=null; enumChildren(h,visitChild,ptr(0));
    if (warningButton!==null && warningText.includes('Startup argument `-opengl` is no longer supported!')) {
        sendMessage(warningButton,0xF5,ptr(0),ptr(0));
        send({type:'renderer_warning_acknowledged'});
    }
    return 1;
},'int',['pointer','pointer'],'stdcall');
let warningChecks=0;
const warningTimer=setInterval(()=>{
    enumWindows(visitWindow,ptr(0));
    if (++warningChecks>=30) clearInterval(warningTimer);
},200);
const queue = [];
let nextInputTime = 0;
const methods = {};
for (const name of ['OnLButtonDown','OnLButtonUp','OnRButtonDown','OnRButtonUp','OnKeyDown','OnKeyUp','OnTextInput','OnTextEvent']) {
    const types = name.startsWith('OnKey') || name.startsWith('OnText') ? ['pointer','int'] : ['pointer','int','int'];
    methods[name] = new NativeFunction(base.add(config.rvas[name]), 'void', types, 'thiscall');
}
methods.OnMouseMove = new NativeFunction(base.add(config.rvas.OnMouseMove), 'void',
    ['pointer','int','int','int','int','bool','bool','bool'], 'thiscall');
let lastMouse = [0, 0];
let leftHeld = false, rightHeld = false;
let app = null;
const capturePerformance={started_ms:Date.now(),native_loops:0,native_swaps:0,frames:0,hud_frames:0,
    capture_ms:0,hud_ms:0,read_ms:0,loop_ms:0,bytes_sent:0};
let activeText = null, textGeneration = 0, lastTextReport = 0, textWasActive = false;
const textStartCounter=Memory.alloc(4);
textStartCounter.writeU32(0);
const originalTextStart=Memory.alloc(Process.pointerSize);
// With self as the only argument, x86 fastcall and thiscall both use ECX.
// A direct native replacement also counts starts during input-handler reentry,
// where attached listeners are suppressed by the main-loop interceptor.
const textModule=new CModule(`
extern unsigned int entry_starts;
extern void *original_start;
typedef void (__attribute__((fastcall)) *StartFunction)(void *self);
void __attribute__((fastcall)) text_started(void *self) {
    ++entry_starts;
    ((StartFunction)original_start)(self);
}
void *__attribute__((fastcall)) text_abi_probe(void *self) { return self; }
`,{entry_starts:textStartCounter,original_start:originalTextStart});
function textSnapshot() {
    if (activeText === null) return {active:false};
    try {
        if (activeText.start!==textStartCounter.readU32() || activeText.pointer.add(0x38).readU8() === 0) return {active:false};
        const start=activeText.pointer.add(0x18).readPointer();
        const end=activeText.pointer.add(0x1c).readPointer();
        const length=end.sub(start).toInt32()/4;
        const maximum=activeText.pointer.add(0x40).readS32();
        if (!Number.isInteger(length) || length<0 || length>512 || maximum<0 || maximum>512) throw new Error('Invalid native text bounds');
        const characters=[];
        for (let i=0;i<length;i++) {
            const ch=start.add(i*4).readU32();
            if (ch>0x10ffff || (ch>=0xd800 && ch<=0xdfff)) throw new Error('Invalid native text codepoint');
            characters.push(ch);
        }
        return {active:true,id:activeText.id,kind:activeText.font===24?'ship':'crew',
            text:String.fromCodePoint(...characters),original_text:activeText.original_text ?? '',max_length:maximum,
            start_generation:activeText.start,
            cursor:Math.max(0,Math.min(length,activeText.pointer.add(0x30).readS32()))};
    } catch (_) { activeText=null; return {active:false}; }
}
function reportText() {
    const value=textSnapshot();
    const now=Date.now();
    if (now-lastTextReport>=100 || value.active!==textWasActive) {
        send({type:'text_entry',value}); lastTextReport=now; textWasActive=value.active;
    }
}
function attachText() {
    if (!config.rvas.TextInputOnRender || !config.rvas.TextInputStart) throw new Error('Update lab hook manifest for native text entry');
    const probe=new NativeFunction(textModule.text_abi_probe,'pointer',['pointer'],'thiscall');
    if (!probe(textStartCounter).equals(textStartCounter)) throw new Error('Native TextInput start ABI mismatch');
    originalTextStart.writePointer(Interceptor.replaceFast(base.add(config.rvas.TextInputStart),textModule.text_started));
    Interceptor.attach(base.add(config.rvas.TextInputOnRender), {
        onEnter() {
            const pointer=this.context.ecx;
            if (pointer.add(0x38).readU8()!==0) {
                const start=textStartCounter.readU32();
                if (activeText===null || !pointer.equals(activeText.pointer) || activeText.start!==start || !textWasActive) {
                    activeText={pointer,id:'entry-'+(++textGeneration),font:0,start};
                    activeText.original_text=textSnapshot().text ?? '';
                }
                activeText.font=this.context.esp.add(4).readS32();
                reportText();
            }
        }
    });
}
let inputModifiers = null;
const modifierMask = Memory.alloc(4);
modifierMask.writeS32(-1);
const originalShiftGetter = Memory.alloc(Process.pointerSize);
const originalCtrlGetter = Memory.alloc(Process.pointerSize);
// Use native stubs: JS callbacks are suppressed when re-entering native code
// from the main-loop Interceptor. The original getters run outside our input.
const modifierModule = new CModule(`
extern int modifier_mask;
extern void *original_shift;
extern void *original_ctrl;
int shift_state(void) {
    if (modifier_mask >= 0) return (modifier_mask & 1) != 0;
    return ((int (*)(void))original_shift)();
}
int ctrl_state(void) {
    if (modifier_mask >= 0) return (modifier_mask & 2) != 0;
    return ((int (*)(void))original_ctrl)();
}
`, {modifier_mask:modifierMask, original_shift:originalShiftGetter, original_ctrl:originalCtrlGetter});
const focus = new NativeFunction(base.add(config.rvas.OnInputFocus), 'void', ['pointer'], 'thiscall');
function move(x, y, left, right) {
    methods.OnMouseMove(app, x, y, x-lastMouse[0], y-lastMouse[1], left ? 1 : 0, right ? 1 : 0, 0);
    lastMouse = [x,y];
}
function attachInput() {
    if (!config.rvas.GetShiftState || !config.rvas.GetCtrlState || !config.rvas.ForceAutofireFlag) throw new Error('Update lab hook manifest for modifier support');
    originalShiftGetter.writePointer(Interceptor.replaceFast(base.add(config.rvas.GetShiftState), modifierModule.shift_state));
    originalCtrlGetter.writePointer(Interceptor.replaceFast(base.add(config.rvas.GetCtrlState), modifierModule.ctrl_state));
    Interceptor.attach(base.add(config.rvas.OnLoop), {
    onEnter() {
        this.perfStart=Date.now();capturePerformance.native_loops++;
        app = this.context.ecx;
        reportText();
        // Execute FTL input handlers on its main thread without taking over desktop input.
        const pending = queue.length && queue[0].ready_at <= Date.now() ? queue.splice(0, 1) : [];
        if (pending.length) focus(app);
        for (const command of pending) {
            // Native input may already have opened a rename field while a
            // controller command is queued. Check again at execution, before
            // changing modifiers or calling any gameplay handler.
            let nativeTextActive=textSnapshot().active;
            if (!nativeTextActive && activeText!==null) {
                try { nativeTextActive=activeText.pointer.add(0x38).readU8()!==0; } catch (_) {}
            }
            const textCommand=['text','text_event','text_cancel'].includes(command.type);
            const release=command.phase==='up' && ['mouse','move'].includes(command.type);
            const exit=command.type==='key' && command.key===290;
            if (nativeTextActive && !textCommand && !release && !exit) {
                send({type:'ack',id:command.id,ignored:'native_text_entry_active'});
                continue;
            }
            // CApp::OnLButtonDown reads shift_held at +5 in this fingerprinted
            // build. Scope both the field and getters to our input handler only.
            const originalShift = app.add(5).readU8();
            const originalForce = config.rvas.ForceAutofireFlag ? base.add(config.rvas.ForceAutofireFlag).readU8() : null;
            try {
                inputModifiers = command.modifiers || {shift:false,control:false};
                modifierMask.writeS32((inputModifiers.shift ? 1 : 0) | (inputModifiers.control ? 2 : 0));
                app.add(5).writeU8(inputModifiers.shift ? 1 : 0);
                // FTL also remembers force_autofire as a key-held flag.
                if (inputModifiers.control) methods.OnKeyDown(app,306);
                if (command.type === 'mouse') {
                    move(command.x,command.y,leftHeld,rightHeld);
                    const prefix = command.button === 'right' ? 'OnRButton' : 'OnLButton';
                    if (command.phase !== 'up') {
                        methods[prefix+'Down'](app,command.x,command.y);
                        if (command.button === 'right') rightHeld=true; else leftHeld=true;
                    }
                    if (command.phase !== 'down') {
                        methods[prefix+'Up'](app,command.x,command.y);
                        if (command.button === 'right') rightHeld=false; else leftHeld=false;
                    }
                } else if (command.type === 'move') {
                    move(command.x,command.y,command.left ?? leftHeld,command.right ?? rightHeld);
                } else if (command.type === 'key') {
                    methods.OnKeyDown(app,command.key);
                    methods.OnKeyUp(app,command.key);
                } else if (command.type === 'text' || command.type === 'text_event' || command.type === 'text_cancel') {
                    const entry=textSnapshot();
                    if (!entry.active || !command.entry_id || command.entry_id!==entry.id) throw new Error('Native text entry changed');
                    if (command.type === 'text') methods.OnTextInput(app,command.codepoint);
                    else if (command.type === 'text_cancel') {
                        // FTL's Escape commits the edited name. Restore the
                        // immutable initial text before its native cancel event.
                        // Keep the whole rollback on this native loop iteration.
                        methods.OnTextEvent(app,2);
                        for (const character of entry.original_text) methods.OnTextInput(app,character.codePointAt(0));
                        methods.OnTextEvent(app,1);
                    } else methods.OnTextEvent(app,command.event);
                }
                send({type:'ack', id:command.id, modifiers:inputModifiers,
                    force_autofire_held:config.rvas.ForceAutofireFlag ? base.add(config.rvas.ForceAutofireFlag).readU8()!==0 : null});
            } catch (error) { send({type:'input_error',error:String(error),id:command.id}); }
            finally {
                if (inputModifiers && inputModifiers.control) methods.OnKeyUp(app,306);
                if (originalForce !== null) base.add(config.rvas.ForceAutofireFlag).writeU8(originalForce);
                app.add(5).writeU8(originalShift); modifierMask.writeS32(-1); inputModifiers=null;
            }
        }
    },
    onLeave() { capturePerformance.loop_ms+=Date.now()-this.perfStart; }
}); }
rpc.exports = {
    start() { attachWorldClip(); attachText(); attachHudPass(); attachInput(); attachCapture(); },
    capturemode(mode) {
        hudEnabled=Boolean(mode.enabled);
        capturePresentation=['game','tactical','window'].includes(mode.presentation)?mode.presentation:'window';
        nextScreenCapture=0; nextHudCapture=0;
    },
    command(command) {
        if (queue.length >= 120) throw new Error('Input queue full');
        let due=Math.max(Date.now(),nextInputTime);
        if (command.type === 'mouse') {
            // FTL computes some button hover states in OnLoop, between events.
            queue.push({...command, type:'move',ready_at:due});
            due+=100;
            if (!command.phase || command.phase === 'click') {
                queue.push({...command, phase:'down',ready_at:due}, {...command, phase:'up',ready_at:due+40});
                due+=60;
            } else queue.push({...command,ready_at:due});
        } else queue.push({...command,ready_at:due});
        nextInputTime=due+10;
    },
    status() { return {pid:Process.id,mainThreadReady:app!==null,hudEnabled,gui:gui===null?null:String(gui),
        hudFramebuffer,powerButtons,performance:{...capturePerformance,elapsed_ms:Date.now()-capturePerformance.started_ms}}; }
};

function attachWorldClip() {
    // These signatures are from the 1.6.9 loader definitions. The Python
    // bridge verifies the entire executable fingerprint before loading us.
    const module = Process.mainModule;
    function unique(pattern) {
        const matches = Memory.scanSync(module.base, module.size, pattern);
        if (matches.length !== 1) throw new Error('World clip signature is not unique: ' + pattern);
        return matches[0].address;
    }
    const translate = unique('55 66 0f ef c0 b9');
    const push = unique('8d 4c 24 04 83 e4 f0 ff 71 fc 55 89 e5 51 83 ec 24 a1 ?? ?? ?? ?? 3b 05 ?? ?? ?? ?? 66 0f 6e 49');
    const pushScissor = new NativeFunction(push, 'void', ['int','int','int','int'], 'mscdecl');
    Interceptor.attach(translate, {
        onEnter(args) {
            // Float arguments occupy four-byte stack slots in this x86 ABI.
            const x = this.context.esp.add(4).readFloat();
            const y = this.context.esp.add(8).readFloat();
            // ftlvr_bridge.lua's matching after callback pops this scissor.
            if (x === -100000 && y === -100000) pushScissor(0, 0, 0, 0);
        }
    });
    send({type:'world_clip_ready'});
}

let gl = null;
let gui = null, hudEnabled = false, hudRender = null;
const hudPassFlag = Memory.alloc(4);
hudPassFlag.writeU32(0);
const powerButtons = {};
let hudFramebuffer = 0, hudTexture = 0, hudDepthStencil = 0, hudWidth = 0, hudHeight = 0;
let hudModule = null;
let loadFramebufferGL = null;
let pixels = null;
let capacity = 0;
let capturePresentation='window';
let nextScreenCapture=0,nextHudCapture=0;
let screenFramebuffer=0,screenTexture=0,screenWidth=0,screenHeight=0;
let sending = false;
let restoreVerified = false;
let screenRestoreVerified = false;
const viewport = Memory.alloc(16);
function initializeGL() {
    if (gl !== null) return true;
    const module = Process.findModuleByName('opengl32.dll');
    if (module === null) return false;
    gl = {
        get: new NativeFunction(module.getExportByName('glGetIntegerv'),'void',['uint','pointer'],'stdcall'),
        read: new NativeFunction(module.getExportByName('glReadPixels'),'void',['int','int','int','int','uint','uint','pointer'],'stdcall'),
        readBuffer: new NativeFunction(module.getExportByName('glReadBuffer'),'void',['uint'],'stdcall'),
        getFloat: new NativeFunction(module.getExportByName('glGetFloatv'),'void',['uint','pointer'],'stdcall'),
        pushAttrib: new NativeFunction(module.getExportByName('glPushAttrib'),'void',['uint'],'stdcall'),
        popAttrib: new NativeFunction(module.getExportByName('glPopAttrib'),'void',[],'stdcall'),
        matrixMode: new NativeFunction(module.getExportByName('glMatrixMode'),'void',['uint'],'stdcall'),
        pushMatrix: new NativeFunction(module.getExportByName('glPushMatrix'),'void',[],'stdcall'),
        popMatrix: new NativeFunction(module.getExportByName('glPopMatrix'),'void',[],'stdcall'),
        clearColor: new NativeFunction(module.getExportByName('glClearColor'),'void',['float','float','float','float'],'stdcall'),
        clear: new NativeFunction(module.getExportByName('glClear'),'void',['uint'],'stdcall'),
        colorMask: new NativeFunction(module.getExportByName('glColorMask'),'void',['uchar','uchar','uchar','uchar'],'stdcall'),
        disable: new NativeFunction(module.getExportByName('glDisable'),'void',['uint'],'stdcall'),
        drawBuffer: new NativeFunction(module.getExportByName('glDrawBuffer'),'void',['uint'],'stdcall'),
        genTextures: new NativeFunction(module.getExportByName('glGenTextures'),'void',['int','pointer'],'stdcall'),
        bindTexture: new NativeFunction(module.getExportByName('glBindTexture'),'void',['uint','uint'],'stdcall'),
        texImage: new NativeFunction(module.getExportByName('glTexImage2D'),'void',['uint','int','int','int','int','int','uint','uint','pointer'],'stdcall'),
        texParameter: new NativeFunction(module.getExportByName('glTexParameteri'),'void',['uint','uint','int'],'stdcall'),
        viewport: new NativeFunction(module.getExportByName('glViewport'),'void',['int','int','int','int'],'stdcall')
    };
    const lookup=new NativeFunction(module.getExportByName('wglGetProcAddress'),'pointer',['pointer'],'stdcall');
    function extension(name,result,args) {
        let address=lookup(Memory.allocUtf8String(name));
        if (address.isNull() || address.toInt32()===-1 || address.toUInt32()<=3) {
            address=lookup(Memory.allocUtf8String(name+'EXT'));
        }
        if (address.isNull() || address.toInt32()===-1 || address.toUInt32()<=3) throw new Error('Missing native HUD framebuffer function '+name);
        return new NativeFunction(address,result,args,'stdcall');
    }
    loadFramebufferGL=()=>{
        if (gl.bindFramebuffer) return;
        gl.genFramebuffers=extension('glGenFramebuffers','void',['int','pointer']);
        gl.bindFramebuffer=extension('glBindFramebuffer','void',['uint','uint']);
        gl.framebufferTexture=extension('glFramebufferTexture2D','void',['uint','uint','uint','uint','int']);
        gl.checkFramebuffer=extension('glCheckFramebufferStatus','uint',['uint']);
        gl.genRenderbuffers=extension('glGenRenderbuffers','void',['int','pointer']);
        gl.bindRenderbuffer=extension('glBindRenderbuffer','void',['uint','uint']);
        gl.renderbufferStorage=extension('glRenderbufferStorage','void',['uint','uint','int','int']);
        gl.framebufferRenderbuffer=extension('glFramebufferRenderbuffer','void',['uint','uint','uint','uint']);
        gl.blitFramebuffer=extension('glBlitFramebuffer','void',['int','int','int','int','int','int','int','int','uint','uint']);
    };
    return true;
}

function attachHudPass() {
    if (!config.rvas.CommandGuiRenderStatic || !config.offsets) throw new Error('Update lab hooks for isolated native HUD rendering');
    hudRender=new NativeFunction(base.add(config.rvas.CommandGuiRenderStatic),'void',['pointer'],'thiscall');
    Interceptor.attach(base.add(config.rvas.CommandGuiRenderStatic),{onEnter() {
        if (hudPassFlag.readU32()===0) gui=this.context.ecx;
    }});
    // Native stubs remain active when reentering from the render interceptor.
    // Only supplemental draw calls are suppressed; the normal game draw runs.
    const symbols={hud_pass:hudPassFlag};
    let code='extern unsigned int hud_pass;\n';
    // Esc and Options are separate render methods from the ship/store tabs.
    // They belong only to the normal screen capture used by the world panel.
    const names=['TabbedWindowOnRender','ChoiceBoxOnRender','MouseControlOnRender','CommandGuiRenderPause','StarMapOnRender','MenuScreenOnRender','OptionsScreenOnRender'];
    for (let i=0;i<names.length;i++) {
        if (!config.rvas[names[i]]) throw new Error('Missing native HUD method '+names[i]);
        symbols['original_'+i]=Memory.alloc(Process.pointerSize);
        code+='extern void *original_'+i+';\nvoid __attribute__((fastcall)) draw_'+i+'(void *self) { if (!hud_pass) ((void (__attribute__((fastcall)) *)(void *))original_'+i+')(self); }\n';
    }
    hudModule=new CModule(code,symbols);
    names.forEach((name,i)=>symbols['original_'+i].writePointer(Interceptor.replaceFast(base.add(config.rvas[name]),hudModule['draw_'+i])));
}

function nativePowerButtons(width,height) {
    const buttons={};
    if (app===null || !hudEnabled) return buttons;
    gui=app.add(config.offsets.app_gui).readPointer();
    if (gui.isNull()) throw new Error('Native gameplay GUI is absent');
    const control=gui.add(config.offsets.gui_system_control);
    const origin=control.add(config.offsets.system_control_position);
    const list=control.add(config.offsets.system_control_boxes);
    const start=list.readPointer(),end=list.add(4).readPointer();
    const count=end.sub(start).toInt32()/Process.pointerSize;
    if (!Number.isInteger(count) || count<0 || count>64) throw new Error('Invalid native power controls vector');
    for (let i=0;i<count;i++) {
        const box=start.add(i*Process.pointerSize).readPointer();
        if (box.isNull()) continue;
        const system=box.add(config.offsets.system_box_system).readPointer();
        if (system.isNull()) continue;
        const id=system.add(config.offsets.system_id).readS32();
        if (id<0 || id>15) continue;
        const position=box.add(config.offsets.system_box_position);
        // Native power allocation responds on the system icon, below its bars.
        // This center was verified against actual add/remove native clicks.
        const point={x:origin.readS32()+position.readS32()+32,
                     y:origin.add(4).readS32()+position.add(4).readS32()+33};
        if (point.x>=0 && point.y>=0 && point.x<1280 && point.y<720) {
            buttons[String(id)]={x:point.x*width/1280,y:point.y*height/720};
        }
    }
    Object.keys(powerButtons).forEach(id=>delete powerButtons[id]);
    Object.assign(powerButtons,buttons);
    return buttons;
}

function captureHud(width,height,size) {
    if (!hudEnabled || gui===null || hudRender===null) return false;
    loadFramebufferGL(); // wglGetProcAddress requires this game's current render context.
    const previous=Memory.alloc(16);
    gl.get(0x8CA6,previous); // framebuffer binding
    gl.get(0x8CA7,previous.add(4)); // renderbuffer binding
    gl.get(0x0BA0,previous.add(8)); // matrix mode
    gl.pushAttrib(0x000fffff); // all server state, including viewport, buffers and texture bindings
    gl.matrixMode(0x1700); gl.pushMatrix();
    gl.matrixMode(0x1701); gl.pushMatrix();
    try {
        const generated=Memory.alloc(4);
        if (!hudFramebuffer) {
            gl.genFramebuffers(1,generated);hudFramebuffer=generated.readU32();
            gl.genTextures(1,generated);hudTexture=generated.readU32();
            gl.genRenderbuffers(1,generated);hudDepthStencil=generated.readU32();
        }
        gl.bindFramebuffer(0x8D40,hudFramebuffer);
        gl.bindTexture(0x0DE1,hudTexture);
        if (hudWidth!==width || hudHeight!==height) {
            gl.texImage(0x0DE1,0,0x8058,width,height,0,0x1908,0x1401,ptr(0)); // RGBA8
            gl.texParameter(0x0DE1,0x2801,0x2600);gl.texParameter(0x0DE1,0x2800,0x2600);
            gl.framebufferTexture(0x8D40,0x8CE0,0x0DE1,hudTexture,0);
            gl.bindRenderbuffer(0x8D41,hudDepthStencil);
            gl.renderbufferStorage(0x8D41,0x88F0,width,height); // depth24 stencil8
            gl.framebufferRenderbuffer(0x8D40,0x821A,0x8D41,hudDepthStencil);
            hudWidth=width;hudHeight=height;
        }
        if (gl.checkFramebuffer(0x8D40)!==0x8CD5) throw new Error('Native HUD framebuffer is incomplete');
        gl.viewport(0,0,width,height);gl.drawBuffer(0x8CE0);gl.readBuffer(0x8CE0);
        gl.disable(0x0C11); // scissor
        gl.colorMask(1,1,1,1);gl.clearColor(0,0,0,0);gl.clear(0x00004500);
        gl.matrixMode(0x1700);
        hudPassFlag.writeU32(1);
        methods.OnKeyDown(app,287); // scoped F6: supplemental Lua render context
        hudRender(gui);
        gl.read(0,0,width,height,0x1908,0x1401,pixels);
        send({type:'hud_frame',width,height,captured_at:Date.now()/1000},pixels.readByteArray(size));
        capturePerformance.hud_frames++;capturePerformance.bytes_sent+=size;
        return true;
    } finally {
        methods.OnKeyDown(app,288); // scoped F7: always restore normal Lua rendering
        hudPassFlag.writeU32(0);
        gl.matrixMode(0x1701);gl.popMatrix();gl.matrixMode(0x1700);gl.popMatrix();
        gl.bindFramebuffer(0x8D40,previous.readU32());
        gl.bindRenderbuffer(0x8D41,previous.add(4).readU32());
        gl.popAttrib();gl.matrixMode(previous.add(8).readU32());
    }
}

function readScreen(width,height,reduced) {
    const outputWidth=reduced?960:width,outputHeight=reduced?540:height;
    const previous=Memory.alloc(12);
    gl.get(0x8CA6,previous);gl.get(0x8CAA,previous.add(4));gl.get(0x0C02,previous.add(8));
    const verify=reduced && config.verify_capture_restore && !screenRestoreVerified;
    let original=null;
    const originalViewport=Memory.alloc(16),originalScissor=Memory.alloc(16),originalScissorEnabled=Memory.alloc(4);
    if (verify) {
        gl.get(0x0BA2,originalViewport);gl.get(0x0C10,originalScissor);gl.get(0x0C11,originalScissorEnabled);
        gl.readBuffer(0x0405);gl.read(0,0,width,height,0x1908,0x1401,pixels);
        original=pixels.readByteArray(width*height*4);gl.readBuffer(previous.add(8).readU32());
    }
    gl.pushAttrib(0x000fffff);
    try {
        if (reduced) {
            loadFramebufferGL();
            const generated=Memory.alloc(4);
            if (!screenFramebuffer) {
                gl.genFramebuffers(1,generated);screenFramebuffer=generated.readU32();
                gl.genTextures(1,generated);screenTexture=generated.readU32();
            }
            gl.bindFramebuffer(0x8CA9,screenFramebuffer); // draw framebuffer only
            gl.bindTexture(0x0DE1,screenTexture);
            if (screenWidth!==outputWidth || screenHeight!==outputHeight) {
                gl.texImage(0x0DE1,0,0x8058,outputWidth,outputHeight,0,0x1908,0x1401,ptr(0));
                gl.texParameter(0x0DE1,0x2801,0x2600);gl.texParameter(0x0DE1,0x2800,0x2600);
                gl.framebufferTexture(0x8CA9,0x8CE0,0x0DE1,screenTexture,0);
                screenWidth=outputWidth;screenHeight=outputHeight;
            }
            if (gl.checkFramebuffer(0x8CA9)!==0x8CD5) throw new Error('Tactical framebuffer is incomplete');
            gl.bindFramebuffer(0x8CA8,0);gl.readBuffer(0x0405);gl.drawBuffer(0x8CE0);
            gl.disable(0x0C11); // native world clip must not crop this full-screen blit
            gl.blitFramebuffer(0,0,width,height,0,0,outputWidth,outputHeight,0x00004000,0x2600);
            gl.bindFramebuffer(0x8CA8,screenFramebuffer);gl.readBuffer(0x8CE0);
        } else {
            gl.readBuffer(0x0405);
        }
        const started=Date.now();
        gl.read(0,0,outputWidth,outputHeight,0x1908,0x1401,pixels);
        capturePerformance.read_ms+=Date.now()-started;
        return {width:outputWidth,height:outputHeight,binary:pixels.readByteArray(outputWidth*outputHeight*4)};
    } finally {
        // A HUD pass binds both targets; preserve them independently here.
        if (gl.bindFramebuffer) {
            gl.bindFramebuffer(0x8CA9,previous.readU32());
            gl.bindFramebuffer(0x8CA8,previous.add(4).readU32());
        }
        gl.popAttrib();gl.readBuffer(previous.add(8).readU32());
        if (verify) {
            const bindings=Memory.alloc(12),restoredViewport=Memory.alloc(16),restoredScissor=Memory.alloc(16),restoredScissorEnabled=Memory.alloc(4);
            gl.get(0x8CA6,bindings);gl.get(0x8CAA,bindings.add(4));gl.get(0x0C02,bindings.add(8));
            gl.get(0x0BA2,restoredViewport);gl.get(0x0C10,restoredScissor);gl.get(0x0C11,restoredScissorEnabled);
            let stateDifferences=0;
            for (let i=0;i<3;i++) if (bindings.add(i*4).readU32()!==previous.add(i*4).readU32()) stateDifferences++;
            for (let i=0;i<4;i++) {
                if (restoredViewport.add(i*4).readS32()!==originalViewport.add(i*4).readS32()) stateDifferences++;
                if (restoredScissor.add(i*4).readS32()!==originalScissor.add(i*4).readS32()) stateDifferences++;
            }
            if (restoredScissorEnabled.readU32()!==originalScissorEnabled.readU32()) stateDifferences++;
            gl.readBuffer(0x0405);gl.read(0,0,width,height,0x1908,0x1401,pixels);gl.readBuffer(previous.add(8).readU32());
            const before=new Uint8Array(original),after=new Uint8Array(pixels.readByteArray(width*height*4));
            let differences=0;for (let i=0;i<before.length;i++) if (before[i]!==after[i]) differences++;
            send({type:'tactical_restore_proof',byte_differences:differences,state_differences:stateDifferences,native_width:width,native_height:height,transport_width:outputWidth,transport_height:outputHeight});
            screenRestoreVerified=true;
        }
    }
}

// Capture on the render thread before the backbuffer is swapped. No desktop screenshots.
function attachCapture() { const timer = setInterval(function() {
    const gdi = Process.findModuleByName('gdi32.dll');
    if (gdi === null || !initializeGL()) return;
    clearInterval(timer);
    Interceptor.attach(gdi.getExportByName('SwapBuffers'), {
        onEnter() {
            const now = Date.now();
            capturePerformance.native_swaps++;
            const screenDue=capturePresentation!=='game' && now>=nextScreenCapture;
            const hudDue=hudEnabled && now>=nextHudCapture;
            if ((!screenDue && !hudDue) || sending) return;
            try {
                gl.get(0x0BA2,viewport); // GL_VIEWPORT
                const width=viewport.add(8).readS32(), height=viewport.add(12).readS32();
                if (width < 1 || height < 1 || width > 2560 || height > 1440) return;
                const size = width*height*4;
                if (size>capacity) { pixels=Memory.alloc(size); capacity=size; }
                sending=true;
                let original=null;
                const verify=hudDue && config.verify_capture_restore && !restoreVerified;
                if (screenDue || verify) original=readScreen(width,height,capturePresentation==='tactical' && !verify);
                if (hudDue) {
                    const hudStart=Date.now();
                    captureHud(width,height,size);
                    capturePerformance.hud_ms+=Date.now()-hudStart;
                    nextHudCapture=Math.max(nextHudCapture+100,now+1);
                    send({type:'system_power_buttons',buttons:nativePowerButtons(width,height),width,height});
                }
                if (verify) {
                    const previousRead=Memory.alloc(4);gl.get(0x0C02,previousRead);
                    gl.readBuffer(0x0405);gl.read(0,0,width,height,0x1908,0x1401,pixels);gl.readBuffer(previousRead.readU32());
                    const before=new Uint8Array(original.binary),after=new Uint8Array(pixels.readByteArray(size));
                    let differences=0;for (let i=0;i<size;i++) if (before[i]!==after[i]) differences++;
                    send({type:'hud_restore_proof',byte_differences:differences,width,height});
                    restoreVerified=true;
                }
                if (screenDue) {
                    send({type:'frame',width:original.width,height:original.height,native_width:width,native_height:height,
                        captured_at:now/1000,supplemental_hud:hudEnabled},original.binary);
                    capturePerformance.frames++;capturePerformance.bytes_sent+=original.binary.byteLength;
                    const interval=capturePresentation==='tactical'?1000/30:config.capture_interval_ms;
                    nextScreenCapture=Math.max(nextScreenCapture+interval,now+1);
                }
                sending=false;
            } catch (error) { sending=false; send({type:'capture_error',error:String(error)}); }
            capturePerformance.capture_ms+=Date.now()-now;
        }
    });
    send({type:'hooks_ready',pid:Process.id});
},100); }
