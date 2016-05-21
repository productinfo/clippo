# 00     00   0000000   000  000   000
# 000   000  000   000  000  0000  000
# 000000000  000000000  000  000 0 000
# 000 0 000  000   000  000  000  0000
# 000   000  000   000  000  000   000

electron      = require 'electron'
proc          = require 'child_process'
osascript     = require './tools/osascript'
resolve       = require './tools/resolve'
appIconSync   = require './tools/appiconsync'
prefs         = require './tools/prefs'
fs            = require 'fs'
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
debug         = false

log = () -> console.log ([].slice.call arguments, 0).join " "

# 0000000    0000000  000000000  000  000   000  00000000
#000   000  000          000     000  000   000  000     
#000000000  000          000     000   000 000   0000000 
#000   000  000          000     000     000     000     
#000   000   0000000     000     000      0      00000000

getActiveApp = () ->
    script = osascript """
    tell application "System Events"
        set n to name of first application process whose frontmost is true
    end tell
    do shell script "echo " & n
    """
    appName = proc.execSync "osascript #{script}"
    appName = String(appName).trim()    

updateActiveApp = () -> 
    appName = getActiveApp()
    if appName != app.getName() and appName != "Electron"
        activeApp = appName

activateApp = () ->
    if activeApp.length
        proc.execSync "osascript " + osascript """
        tell application "#{activeApp}" to activate
        """

# 0000000   00000000   00000000   000   0000000   0000000   000   000
#000   000  000   000  000   000  000  000       000   000  0000  000
#000000000  00000000   00000000   000  000       000   000  000 0 000
#000   000  000        000        000  000       000   000  000  0000
#000   000  000        000        000   0000000   0000000   000   000
        
saveAppIcon = (appName) ->
    iconPath = "#{iconDir}/#{appName}.png"
    try 
        fs.accessSync iconPath, fs.R_OK
    catch
        icn = appIconSync appName, iconDir, 64
        log 'gotAppIcon', appName, iconDir, icn
        
#000      000   0000000  000000000  00000000  000   000
#000      000  000          000     000       0000  000
#000      000  0000000      000     0000000   000 0 000
#000      000       000     000     000       000  0000
#0000000  000  0000000      000     00000000  000   000

listenClipboard = () ->
    text = clipboard.readText()
    image = clipboard.readImage()
    originApp = 'clippo' if buffers.length == 0
    isEmpty = buffers.length == 0
    if not isEmpty
        otherText = text != buffers[buffers.length-1].text
        otherImage = not image.isEmpty() and image.toPng().toString('base64') != buffers[buffers.length-1].image
    if isEmpty or otherText or otherImage
        info = 
            text: text
            app:  originApp ? getActiveApp()
        if not image.isEmpty()
            s = image.getSize()
            log "image of size #{s.width}x#{s.height}"
            info.image = image.toPng().toString('base64')
        log info.app
        
        buffers.push info
        saveAppIcon buffers[buffers.length-1].app
        originApp = undefined
        win?.webContents.send 'reload'
    setTimeout listenClipboard, 500

ipc.on 'get-buffers', (event, arg) => event.returnValue = buffers

#00000000    0000000    0000000  000000000  00000000
#000   000  000   000  000          000     000     
#00000000   000000000  0000000      000     0000000 
#000        000   000       000     000     000     
#000        000   000  0000000      000     00000000

ipc.on 'paste', (event, arg) => 
    clipboard.writeText buffers[arg].text
    if buffers[arg].image
        image = nativeImage.createFromBuffer new Buffer buffers[arg].image, 'base64'
        clipboard.writeImage image
    originApp = buffers.splice(arg, 1)[0].app
    win.close()
    paste = () ->
        proc.exec "osascript " + osascript """
        tell application "System Events" to keystroke "v" using command down
        """
    setTimeout paste, 10

#000   000  000  000   000  0000000     0000000   000   000
#000 0 000  000  0000  000  000   000  000   000  000 0 000
#000000000  000  000 0 000  000   000  000   000  000000000
#000   000  000  000  0000  000   000  000   000  000   000
#00     00  000  000   000  0000000     0000000   00     00

toggleWindow = () ->
    if win?.isVisible()
        win.hide()    
        app.dock.hide()        
    else
        showWindow()

showWindow = () ->
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
        minimizable:     false
        fullscreen:      false
        show:            true
        
    bounds = prefs.get 'bounds'
    win.setBounds bounds if bounds?
        
    win.loadURL "file://#{__dirname}/../index.html"
    win.webContents.openDevTools() if debug
    app.dock.show()
    win.on 'closed', -> win = null
    win.on 'close', (event) ->
        activateApp()
        win.hide()
        app.dock.hide()
        event.preventDefault()
    win

saveBounds = () ->
    if win?
        prefs.set 'bounds', win.getBounds()
        
saveBuffer = () ->
    json = JSON.stringify buffers.slice(- prefs.get('maxBuffers', 20)), null, '    '
    fs.writeFile "#{app.getPath('userData')}/clippo-buffers.json", json, encoding:'utf8' 
    
readBuffer = () ->
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
    
    Menu.setApplicationMenu Menu.buildFromTemplate [
        label: app.getName()
        submenu: [
            label: 'Close Window'
            accelerator: 'Command+W'
            click: () -> win.close()
        ,
            label: 'Quit'
            accelerator: 'Command+Q'
            click: () -> 
                saveBounds()
                saveBuffer()
                app.exit 0
        ]
    ]
        
    prefs.init "#{app.getPath('userData')}/clippo.json",
        maxBuffers: 20
        shortcut: 'Command+Alt+V'

    electron.globalShortcut.register prefs.get('shortcut'), showWindow
    electron.globalShortcut.register 'Command+Alt+I', () -> win?.webContents.openDevTools()

    readBuffer()

    iconDir = resolve "#{__dirname}/../icons"    
    try
        fs.accessSync iconDir, fs.R_OK
    catch
        try
            fs.mkdirSync iconDir
        catch
            log "can't create icon directory #{iconDir}"
    
    listenClipboard()
    