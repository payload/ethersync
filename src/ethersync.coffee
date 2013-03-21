#!./node_modules/coffee-script/bin/coffee
io      = require 'socket.io-client'
request = require 'request'
https   = require 'https'
fs      = require 'fs'
util    = require 'util'
getopt  = require 'node-getopt'
child   = require 'child_process'
Path    = require 'path'
Url     = require 'url'
Changeset = require './src/Changeset'

jar = request.jar()

main = ->
  patchSocketIo()
  
  me = process.argv[1]
  me = Path.basename me, Path.extname me

  defaults =
    host  : "http://127.0.0.1:9001/"
    pad   : randomString 10
    path  : me+'.txt'
    secure: false

  for arg in process.argv[2..]
    if arg in ['--help', '-h']
      help(me)
    else if arg in ['--version', '-V']
      version()

  [ path, pad, host, secure ] = process.argv[2..]
  path   or= defaults.path
  pad    or= defaults.pad
  host   or= defaults.host
  secure or= defaults.secure
  { pathname, href } = url = Url.parse pad
  if pathname != href
    pad  = pathname.split('/')[-1..]
    host = (url.protocol or 'http') + '//' + url.host + '/'
  url = Url.parse host
  host = (url.protocol or 'http') + '//' + url.host + '/'
  opts = { host, pad, path, secure }
  
  https.globalAgent.options.rejectUnauthorized = !opts.secure
  ethersync = new EtherSync opts
  ethersync.openPad()

help = (me) ->
  P "Usage: #{process.argv[0]} #{process.argv[1]} [-hV] [PATH] [PAD] [HOST] [SECURE]"
  P ""
  P "PATH defaults to #{me}.txt"
  P "PAD  defaults to a random string"
  P "HOST defaults to #{defaultHost}"
  P "SECURE defaults to false"
  process.exit 0
  
version = ->
  P "ethersync 0.0.0"

class EtherSync

  constructor: ({ @path, @pad, @host }={}) ->
    @timer  = null
    @rev    = -1
    @socket = null
    try @text   = ""+fs.readFileSync @path
    catch err
      @text = ""

  openPad: =>
    url = @host + 'p/' + @pad
    P "open", url
    child.exec 'xdg-open '+url
    request.get { jar, url }, @connect

  connect: =>
    @socket = socket = io.connect @host, {
      resource: 'socket.io'
      'max reconnection attempts': 3
      'sync disconnect on unload' : false
    }
    socket.on 'error'   , (err) => throw err
    socket.on 'message' , @handleMessage
    @sendClientReady()
    
  handleMessage: (msg) =>
    return unless msg.type and msg.data
    switch msg.type
      when 'CLIENT_VARS'
        vars = msg.data?.collab_client_vars
        text = vars?.initialAttributedText?.text[...-1]
        if @rev != vars.rev
          @rev = vars.rev
          if @rev == 0
            @pushFile text
          else if @text and text and @text != text
            @fileAndPadNotEmpty()
          else
            @writeFile text
      when 'COLLABROOM'
        { type, newRev, changeset } = msg.data
        if type == 'NEW_CHANGES' and newRev > @rev
          @rev = newRev
          # XXX there is an off-by-one-error and
          # I don't know who is inserting or missing a newline
          try text = Changeset.applyToText changeset, @text
          catch err
              text = Changeset.applyToText changeset, @text+'\n'
          @writeFile text
      else
        P msg
  
  fileAndPadNotEmpty: =>
    util.error """Oh no!
    
    Your file and the pad is not empty. You could loose data
    somewhere, so I stopped and let you fix the situation. Make the file or the
    pad empty, give me another filer or pad or whatever."""
    process.exit 1
  
  pushFile: (oldText) =>
    cs = Changeset.makeSplice oldText, 0, oldText.length, @text, '', null
    @socket.json.send
      component     : "pad"
      type          : "COLLABROOM"
      data          :
        type        : "USER_CHANGES"
        baseRev     : 0
        changeset   : cs
        apool       :
          numToAttrib: { 0: [ "author", "a."+randomString(16) ] }
          nextNum    : 1
  
  writeFile: (text) =>
    fs.stat @path, (err, stat) =>
      fs.writeFile @path, text, mode: stat?.mode, (err) =>
        return if err
        @text = text
  
  sendClientReady: =>
    @socket.json.send
      component       : "pad"
      type            : "CLIENT_READY"
      padId           : @pad
      sessionID       : null
      password        : null
      token           : "t."+randomString(20)
      protocolVersion : 2

patchSocketIo = ->
  mod = require('socket.io-client/node_modules/xmlhttprequest')
  XMLHttpRequestOrig = mod.XMLHttpRequest
  mod.XMLHttpRequest = ->
    XMLHttpRequestOrig.apply this, arguments
    @setDisableHeaderCheck true
    openOrig = @open
    @open = (method, url) ->
      openOrig.apply this, arguments
      header = jar.get({ url }).map(({ name, value }) ->
        name + "=" + value
      ).join "; "
      @setRequestHeader 'cookie', header
    return
  
randomString = (len) ->
  len ?= 20
  chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  randomstring = ''
  for i in [0..len]
    rnum = Math.floor Math.random() * chars.length
    randomstring += chars.substring rnum, rnum + 1
  randomstring
  
P = (o, keys...) ->
  if typeof o in ['string', 'number']
    console.log o, keys...
  else
    if Array.isArray keys[0]
      keys = keys[0] or Object.keys o
      for k in keys
        if typeof k in ['string', 'number']
          console.log "#{k}: #{o[k]}"
    else
      console.log o
      
do main
