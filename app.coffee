bodyParser = require 'body-parser'
express = require 'express'
http = require 'http'
mime = require 'mime'
shortId = require 'shortid'

RepoManager = require './RepoManager'

process.on 'uncaughtException', (err) ->
    console.log err

# contains every alive managers, keyed by a unique ID.
managers = {}

app = express()
app.use bodyParser.urlencoded { extended: true }
app.use bodyParser.json()
app.use express.static(__dirname + '/public')

app.post '/explore/login', (req, res) ->
  ssh = req.body.ssh
  rm = new RepoManager ssh.host, ssh.port, ssh.username, ssh.password, ssh.baseDir
  rm.connect (err) ->
    res.status(400).end() if err
    uuid = shortId.generate()
    managers[uuid] = rm
    rm.getDists (err, dists) ->
      res.status(400).end() if err
      res.send
        'uuid': uuid
        'dists': dists
      res.end()

app.post '/explore/logout', (req, res) ->
  ssh = req.body.ssh
  if ssh.uuid of managers
    rm = managers[ssh.uuid]
    delete managers[ssh.uuid]
    rm.disconnect ->
      res.status(200).end()
  else
    res.status(200).end()

app.get '/explore/components', (req, res) ->
    if req.query.ssh_uuid of managers
      rm = managers[req.query.ssh_uuid]
      rm.getComponents req.query.dist, (err, components) ->
        res.status(400).end() if err
        res.send
          'components': components
        res.end()
    else
      res.status(400).end()

app.get '/explore/arches', (req, res) ->
    if req.query.ssh_uuid of managers
      rm = managers[req.query.ssh_uuid]
      rm.getArches req.query.dist, req.query.component, (err, arches) ->
        res.status(400).end() if err
        res.send
          'arches': arches
        res.end()
    else
      res.status(400).end()

app.get '/explore/packages', (req, res) ->
    if req.query.ssh_uuid of managers
      rm = managers[req.query.ssh_uuid]
      rm.getFiles req.query.dist, req.query.component, req.query.arch, (err, files) ->
        res.status(400).end() if err
        # make another call to get Packages content
        rm.getInfoFromIndex req.query.dist, req.query.component, req.query.arch, (err, versions, validPaths) ->
          packages = []
          unfoundPackages = []
          noPercentage3a = true
          files.forEach (file) ->
            if file.indexOf(".deb") > -1
              noPercentage3a = false if file.indexOf("%3a") > -1
              tokens = file.split('_')
              packages.push
                name: tokens[0]
                version: tokens[1]
                arch: tokens[2].replace('.deb', '')
              unless tokens[0] of versions and tokens[1] is versions[tokens[0]]
                unfoundPackages.push tokens[0]
          res.send
            'packages': packages
            'unfoundPackages': unfoundPackages
            'validPaths': validPaths
            'noPercentage3a': noPercentage3a
          res.end()
    else
      res.status(400).end()

app.post '/explore/rebuild_index', (req, res) ->
  ssh_uuid = req.body.ssh_uuid
  dist = req.body.dist
  component = req.body.component
  arch = req.body.arch
  if ssh_uuid of managers
    rm = managers[ssh_uuid]
    rm.rebuildIndex dist, component, arch, (err) ->
      if err
        console.log err
        res.status(400).end()
      res.status(200).end()
  else
    res.status(200).end()

app.post '/explore/remove_percentage3a', (req, res) ->
  ssh_uuid = req.body.ssh_uuid
  dist = req.body.dist
  component = req.body.component
  arch = req.body.arch
  if ssh_uuid of managers
    rm = managers[ssh_uuid]
    rm.removePercentage3a dist, component, arch, (err) ->
      if err
        console.log err
        res.status(400).end()
      res.status(200).end()
  else
    res.status(200).end()

app.get '/explore/download_file', (req, res) ->
  ssh_uuid = req.query.ssh_uuid
  dist = req.query.dist
  component = req.query.component
  arch = req.query.arch
  filename = req.query.filename
  if ssh_uuid of managers
    rm = managers[ssh_uuid]
    rm.downloadFile dist, component, arch, filename, (err, stream) ->
      res.setHeader 'Content-disposition', "attachment; filename=#{filename}"
      res.setHeader 'Content-type', (mime.lookup filename)
      stream.pipe res
  else
    res.status(200).end()

server = http.createServer app
server.listen 8888
