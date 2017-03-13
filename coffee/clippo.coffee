#  0000000  000      000  00000000   00000000    0000000 
# 000       000      000  000   000  000   000  000   000
# 000       000      000  00000000   00000000   000   000
# 000       000      000  000        000        000   000
#  0000000  0000000  000  000        000         0000000 

electron  = require 'electron'
keyname   = require './tools/keyname'
pkg       = require '../package.json'
clipboard = electron.clipboard
ipc       = electron.ipcRenderer
current   = 0
buffers   = []
encode    = require('html-entities').XmlEntities.encode

$ = (id) -> document.getElementById id
log = -> console.log ([].slice.call arguments, 0).join " "

doPaste = -> ipc.send 'paste', current

# 000   000  000   0000000   000   000  000      000   0000000   000   000  000000000
# 000   000  000  000        000   000  000      000  000        000   000     000   
# 000000000  000  000  0000  000000000  000      000  000  0000  000000000     000   
# 000   000  000  000   000  000   000  000      000  000   000  000   000     000   
# 000   000  000   0000000   000   000  0000000  000   0000000   000   000     000   

highlight = (index) =>
    $(current)?.classList.remove 'current'
    current = Math.max 0, Math.min index, buffers.length-1
    pre = $(current)
    pre.classList.add 'current'
    pre.scrollIntoViewIfNeeded()
    
window.highlight = highlight
window.onClick = (index) ->
    highlight index
    doPaste()

lineForElem = (elem) ->        
    if elem.classList?.contains('line-div') then return elem
    if elem.parentNode? then return lineForElem elem.parentNode
    
$('main').addEventListener "mouseover", (event) ->
    id = lineForElem(event.target)?.id
    highlight id if id?

# 000       0000000    0000000   0000000  
# 000      000   000  000   000  000   000
# 000      000   000  000000000  000   000
# 000      000   000  000   000  000   000
# 0000000   0000000   000   000  0000000  

ipc.on "loadBuffers", (event, buffs, index) -> loadBuffers buffs, index

loadBuffers = (buffs, index=0) ->
    buffers = buffs
    html = ""
    i = 0
    for buf in buffers
        
        icon = "<img  onClick='window.highlight(#{i});' class=\"appicon\" src=\"icons/#{buf.app}.png\"/>\n"
        if buf.image?
            pre  = "<img src=\"data:image/png;base64,#{buf.image}\"/>\n"
        else if buf.text?
            encl = ( encode(l) for l in buf.text.split("\n")  )
            pre  = "<pre>" + encl.join("<br>") + "</pre>\n"
        else
            pre = ""
        span = "<span class=\"line-span\">" + icon + pre + "</span>"
        div  = "<div id=#{i} class=\"line-div\" onClick='window.onClick(#{i});'>#{span}</div>"
        html = div + html
        i += 1
    html = "<center><p class=\"info\">clipboard is empty</p></center>" if html.length == 0
    $("main").innerHTML = html
    highlight index ? buffers.length-1

setTitleBar = ->
    html  = "<span class='titlebarName'>#{pkg.name}</span>"
    html += "<span class='titlebarDot'> ● </span>"
    html += "<span class='titlebarVersion'>#{pkg.version}</span>"
    $('titlebar').innerHTML = html
    $('titlebar').ondblclick = => ipc.send 'toggleMaximize'

setTitleBar()
loadBuffers ipc.sendSync "getBuffers"

window.onunload = ->
    document.onkeydown = null

# 000   000  00000000  000   000
# 000  000   000        000 000 
# 0000000    0000000     00000  
# 000  000   000          000   
# 000   000  00000000     000   

document.onkeydown = (event) ->
    key = keyname.ofEvent event
    switch key
        when 'esc'                then return ipc.send 'closeWin'
        when 'down', 'right'      then return highlight current-1
        when 'up'  , 'left'       then return highlight current+1
        when 'home', 'page up'    then return highlight buffers.length-1
        when 'end',  'page down'  then return highlight 0
        when 'enter', 'command+v' then return doPaste()
        when 'backspace', 'command+backspace', 'delete' then return ipc.send "del", current
