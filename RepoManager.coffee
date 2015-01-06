exec = require 'ssh2-exec'
ssh2 = require 'ssh2'


class RepoManager
  constructor: (@host, @port, @username, @password, @baseDir) ->
    @ssh = new ssh2()
    @sftp = undefined

  connect: (callback) ->
    @ssh.on 'ready', =>
      @ssh.sftp (err, sftp) =>
        callback err if err
        @sftp = sftp
        callback null
    @ssh.on 'error', (err) ->
      callback err
    @ssh.connect
      host: @host
      port: @port
      username: @username
      password: @password

  disconnect: (callback) ->
    @ssh.on 'close', ->
      callback()
    @ssh.end()

  listFiles: (dir, callback) ->
    exec { cmd: "ls -1 #{dir}", ssh: @ssh }, (err, stdout, stderr) ->
      callback err if err
      console.log stdout
      stdout = stdout.replace /\s+$/, ''
      callback null, if stdout.length > 0 then stdout.split('\n') else []

  getDists: (callback) ->
    @listFiles "#{@baseDir}/dists", callback

  getComponents: (dist, callback) ->
    @listFiles "#{@baseDir}/dists/#{dist}", callback

  getArches: (dist, component, callback) ->
    @listFiles "#{@baseDir}/dists/#{dist}/#{component}", callback

  getFiles: (dist, component, arch, callback) ->
    @listFiles "#{@baseDir}/dists/#{dist}/#{component}/#{arch}", callback

  getInfoFromIndex: (dist, component, arch, callback) ->
    stream = @sftp.createReadStream("#{@baseDir}/dists/#{dist}/#{component}/#{arch}/Packages")
    stdout = ''
    stream.on 'data', (chunk) ->
      stdout += chunk
    stream.on 'end', ->
      stdout = stdout.replace /\s+$/, ''
      versions = {}
      validPaths = false
      if stdout.length > 0
        pkg = undefined
        validPaths = true
        stdout.split('\n').forEach (line) ->
          if line.length > 0
            tokens = line.split ' '
            switch tokens[0]
              when "Package:"
                pkg = tokens[1]
              when "Version:"
                versions[pkg] = tokens[1].replace(/.+:/g, "");
              when "Filename:"
                validPaths = validPaths && tokens[1].indexOf("dists/#{dist}/#{component}/#{arch}/") is 0 && tokens[1].indexOf('%3a') < 0
      callback null, versions, validPaths

  rebuildIndex: (dist, component, arch, callback) ->
    exec { cmd: "cd #{@baseDir} && dpkg-scanpackages -m dists/#{dist}/#{component}/#{arch} > dists/#{dist}/#{component}/#{arch}/Packages", ssh: @ssh }, (err, stdout, stderr) =>
      callback err if err
      exec { cmd: "cd #{@baseDir} && gzip -9c dists/#{dist}/#{component}/#{arch}/Packages > dists/#{dist}/#{component}/#{arch}/Packages.gz", ssh: @ssh }, (err, stdout, stderr) ->
        callback err if err
        callback null

  removePercentage3a: (dist, component, arch, callback) ->
    exec { cmd: "for file in #{@baseDir}/dists/#{dist}/#{component}/#{arch}/*%3a*.deb; do mv \"$file\" \"`echo $file| sed -r 's/[0-9]+\%3a//'`\"; done", ssh: @ssh }, (err, stdout, stderr) ->
      callback err if err
      callback null

  downloadFile: (dist, component, arch, filename, callback) ->
    callback null, @sftp.createReadStream("#{@baseDir}/dists/#{dist}/#{component}/#{arch}/#{filename}")

module.exports = RepoManager