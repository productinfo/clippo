# 00     00   0000000   000  000   000
# 000   000  000   000  000  0000  000
# 000000000  000000000  000  000 0 000
# 000 0 000  000   000  000  000  0000
# 000   000  000   000  000  000   000

electron      = require 'electron'
chokidar      = require 'chokidar'
childp        = require 'child_process'
noon          = require 'noon'
fs            = require 'fs'
osascript     = require './tools/osascript'
resolve       = require './tools/resolve'
appIconSync   = require './tools/appiconsync'
prefs         = require './tools/prefs'
log           = require './tools/log'
pkg           = require '../package.json'
app           = electron.app
BrowserWindow = electron.BrowserWindow
Tray          = electron.Tray
Menu          = electron.Menu
clipboard     = electron.clipboard
ipc           = electron.ipcMain
nativeImage   = electron.nativeImage
win           = undefined
tray          = undefined
buffers       = []
iconDir       = ""
activeApp     = ""
originApp     = null
clippoWatch   = null
debug         = false

# 000  00000000    0000000
# 000  000   000  000     
# 000  00000000   000     
# 000  000        000     
# 000  000         0000000

ipc.on 'getBuffers', (event)  -> event.returnValue = buffers
ipc.on 'toggleMaximize',      -> if win?.isMaximized() then win?.unmaximize() else win?.maximize()
ipc.on 'closeWin',            -> win?.close()

# 0000000    0000000  000000000  000  000   000  00000000
#000   000  000          000     000  000   000  000     
#000000000  000          000     000   000 000   0000000 
#000   000  000          000     000     000     000     
#000   000   0000000     000     000      0      00000000

getActiveApp = ->
    script = osascript """
    tell application "System Events"
        set n to name of first application process whose frontmost is true
    end tell
    do shell script "echo " & n
    """
    appName = childp.execSync "osascript #{script}"
    appName = String(appName).trim()    
    # log 'getActiveApp', appName
    appName

updateActiveApp = -> 
    appName = getActiveApp()
    if appName != app.getName()
        activeApp = appName

activateApp = ->
    if activeApp.length
        try
            childp.execSync "osascript " + osascript """
            tell application "#{activeApp}" to activate
            """
        catch
            return

# 0000000   00000000   00000000   000   0000000   0000000   000   000
#000   000  000   000  000   000  000  000       000   000  0000  000
#000000000  00000000   00000000   000  000       000   000  000 0 000
#000   000  000        000        000  000       000   000  000  0000
#000   000  000        000        000   0000000   0000000   000   000
        
saveAppIcon = (appName) ->
    # log 'saveAppIcon', appName
    iconPath = "#{iconDir}/#{appName}.png"
    try 
        fs.accessSync iconPath, fs.R_OK
    catch
        png = appIconSync appName, iconDir, 128
        # log "appIconSync #{iconPath} -> png: #{png}"
        appName = "clippo" if not png
    appName

# 000   000   0000000   000000000   0000000  000   000
# 000 0 000  000   000     000     000       000   000
# 000000000  000000000     000     000       000000000
# 000   000  000   000     000     000       000   000
# 00     00  000   000     000      0000000  000   000

readPBjson = (path) ->

    obj = noon.load path
    
    isEmpty = buffers.length == 0
    
    return if not obj.text? and not obj.image?
    return if buffers.length and obj.count == buffers[buffers.length-1].count
                
    currentApp = getActiveApp()
    currentApp = 'clippo' if currentApp == 'Electron'
    originApp  = 'clippo' if (not originApp) and (not currentApp)
    saveAppIcon originApp ? currentApp

    if obj.image? 
        buffers.push 
            app:   currentApp
            image: obj.image
            count: obj.count

    if obj.text? 
        buffers.push 
            app:   currentApp
            text:  obj.text
            count: obj.count

    maxBuffers = prefs.get 'maxBuffers', 50
    while buffers.length > maxBuffers
        buffers.shift()

    originApp = undefined        
    reload buffers.length-1

watchClipboard = ->

    clippoWatch = childp.spawn "#{__dirname}/../bin/clippo-watch", [], 
        cwd: "#{__dirname}/../bin"
        detached: false

    watcher = chokidar.watch "#{__dirname}/../bin/pb.json", persistent: true
    watcher.on 'add',    (path) => readPBjson path
    watcher.on 'change', (path) => readPBjson path
        
# 0000000   0000000   00000000   000   000
#000       000   000  000   000   000 000 
#000       000   000  00000000     00000  
#000       000   000  000           000   
# 0000000   0000000   000           000   

copyIndex = (index) ->
    return if (index < 0) or (index > buffers.length-1)
    if buffers[index].image
        image = nativeImage.createFromBuffer new Buffer buffers[index].image, 'base64'
        if not image.isEmpty() and (image.getSize().width * image.getSize().height > 0)
            clipboard.writeImage image,  'image/png'
    if buffers[index].text? and (buffers[index].text.length > 0) 
        clipboard.writeText buffers[index].text, 'text/plain' 

#00000000    0000000    0000000  000000000  00000000
#000   000  000   000  000          000     000     
#00000000   000000000  0000000      000     0000000 
#000        000   000       000     000     000     
#000        000   000  0000000      000     00000000

ipc.on 'paste', (event, arg) => 
    copyIndex arg
    originApp = buffers.splice(arg, 1)[0].app
    win.close()
    paste = () ->
        childp.exec "osascript " + osascript """
        tell application "System Events" to keystroke "v" using command down
        """
    setTimeout paste, 10
    
#0000000    00000000  000    
#000   000  000       000    
#000   000  0000000   000    
#000   000  000       000    
#0000000    00000000  0000000

ipc.on 'del', (event, arg) =>
    if arg == buffers.length-1
        clipboard.clear()
        copyIndex buffers.length-2
    buffers.splice(arg, 1)
    reload arg-1
    
#000   000  000  000   000  0000000     0000000   000   000
#000 0 000  000  0000  000  000   000  000   000  000 0 000
#000000000  000  000 0 000  000   000  000   000  000000000
#000   000  000  000  0000  000   000  000   000  000   000
#00     00  000  000   000  0000000     0000000   00     00

toggleWindow = ->
    if win?.isVisible()
        win.hide()    
        app.dock.hide()        
    else
        showWindow()

showWindow = ->
    updateActiveApp()
    if win?
        win.show()
        app.dock.show()
    else
        createWindow()
    
createWindow = ->
    win = new BrowserWindow
        width:           1000
        height:          1200
        titleBarStyle:   'hidden'
        backgroundColor: '#181818'
        maximizable:     true
        minimizable:     true
        fullscreen:      false
        show:            true
        
    bounds = prefs.get 'bounds'
    win.setBounds bounds if bounds?
        
    win.loadURL "file://#{__dirname}/../index.html"
    win.webContents.openDevTools() if debug
    app.dock.show()
    win.on 'ready-to-show', -> win.show()
    win.on 'closed', -> win = null
    win.on 'close', (event) ->
        activateApp()
        win.hide()
        app.dock.hide()
        event.preventDefault()
    win

saveBounds = ->
    if win?
        prefs.set 'bounds', win.getBounds()
    
reload = (index=0) -> win?.webContents.send 'loadBuffers', buffers, index
    
clearBuffer = ->
    buffers = []
    saveBuffer()
    reload()
        
saveBuffer = ->
    json = JSON.stringify buffers.slice(- prefs.get('maxBuffers', 50)), null, '    '
    fs.writeFile "#{app.getPath('userData')}/clippo-buffers.json", json, encoding:'utf8' 
    
readBuffer = ->
    buffers = [] 
    try
        buffers = JSON.parse fs.readFileSync "#{app.getPath('userData')}/clippo-buffers.json", encoding:'utf8'
    catch
        return

#00000000   00000000   0000000   0000000    000   000
#000   000  000       000   000  000   000   000 000 
#0000000    0000000   000000000  000   000    00000  
#000   000  000       000   000  000   000     000   
#000   000  00000000  000   000  0000000       000   

app.on 'ready', -> 
    
    tray = new Tray "#{__dirname}/../img/menu.png"
    tray.on 'click', toggleWindow
    app.dock.hide() if app.dock
    
    app.setName 'clippo'
    
    # 00     00  00000000  000   000  000   000
    # 000   000  000       0000  000  000   000
    # 000000000  0000000   000 0 000  000   000
    # 000 0 000  000       000  0000  000   000
    # 000   000  00000000  000   000   0000000 
    
    Menu.setApplicationMenu Menu.buildFromTemplate [
        label: app.getName()
        submenu: [
            label: "About #{pkg.name}"
            click: -> clipboard.writeText "#{pkg.name} v#{pkg.version}"
        ,            
            label: 'Clear Buffer'
            accelerator: 'Command+K'
            click: -> clearBuffer()
        ,
            label: 'Save Buffer'
            accelerator: 'Command+S'
            click: -> saveBuffer()
        ,
            type: 'separator'
        ,
            label:       "Hide #{pkg.productName}"
            accelerator: 'Cmd+H'
            click:        -> win?.hide()
        ,
            label:       'Hide Others'
            accelerator: 'Cmd+Alt+H'
            role:        'hideothers'
        ,
            type: 'separator'
        ,
            label: 'Quit'
            accelerator: 'Command+Q'
            click: -> 
                saveBounds()
                saveBuffer()
                clippoWatch?.kill()
                app.exit 0
        ]
    ,
        # 000   000  000  000   000  0000000     0000000   000   000
        # 000 0 000  000  0000  000  000   000  000   000  000 0 000
        # 000000000  000  000 0 000  000   000  000   000  000000000
        # 000   000  000  000  0000  000   000  000   000  000   000
        # 00     00  000  000   000  0000000     0000000   00     00
        
        label: 'Window'
        submenu: [
            label:       'Minimize'
            accelerator: 'Alt+Cmd+M'
            click:       -> win?.minimize()
        ,
            label:       'Maximize'
            accelerator: 'Cmd+Shift+m'
            click:       -> if win?.isMaximized() then win?.unmaximize() else win?.maximize()
        ,
            type: 'separator'
        ,                            
            label:       'Close Window'
            accelerator: 'Cmd+W'
            click:       -> win?.close()
        ,
            type: 'separator'
        ,                            
            label:       'Bring All to Front'
            accelerator: 'Alt+Cmd+`'
            click:       -> win?.show()
        ,
            type: 'separator'
        ,   
            label:       'Reload Window'
            accelerator: 'Ctrl+Alt+Cmd+L'
            click:       -> win?.webContents.reloadIgnoringCache()
        ,                
            label:       'Toggle DevTools'
            accelerator: 'Cmd+Alt+I'
            click:       -> win?.webContents.openDevTools()
        ]
    ]
        
    prefs.init "#{app.getPath('userData')}/clippo.json",
        maxBuffers: 50
        shortcut: 'Command+Alt+V'

    electron.globalShortcut.register prefs.get('shortcut'), showWindow

    readBuffer()

    iconDir = resolve "#{__dirname}/../icons"    
    try
        fs.accessSync iconDir, fs.R_OK
    catch
        try
            fs.mkdirSync iconDir
        catch
            log "can't create icon directory #{iconDir}"
    
    watchClipboard()
    