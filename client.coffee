http = require 'http'
util = require 'util'
parse_template = require('uri-template').parse

exports.LazyAppClient = class LazyAppClient
  constructor: (@config, cb) ->
    request.call @, 'GET', '/', null, (err, routes) =>
      if not err and routes.statusCode != 200
        err = new Error res.error or res.warning
      if err
        if cb then return cb err else throw err

      for route in routes.data
        installRoute.call @, route

      cb() if cb

  ##
  # A hook for subclasses to alter the request (e.g. add special headers)
  # before sending it off.
  ##
  pre_request: (request_opts, body) -> undefined

  ##
  # A hook for subclasses to alter the response data
  ##
  post_request: (data) -> undefined

  ##
  # Convenience method for .request('GET', ...)
  ##
  get: (path, cb) -> request.call @, 'GET', path, null, cb

  ##
  # Convenience method for .request('POST', ...)
  ##
  post: (path, body, cb) -> request.call @, 'POST', path, body, cb



##
# Convert a response object to a JSON string
##
exports.toJSON = toJSON = ->
  src = @
  dest = {}

  uniqid = -> return 'x' + (new Date).getTime() + Math.floor(Math.random() * 10000)

  # walk the object, replacing duplicate instance of the same object
  # with string-based reference markers that point to the location
  # of the "real" data within the object
  walk = (src, dst, path, crumbs) ->
    for k,v of src
      if v is null or typeof v isnt 'object'
        dst[k] = v unless k == '_crumb'
        continue
      if v._crumb
        # seen this object already, so replace it with a reference marker
        dst[k] = 'ref:' + crumbs[v._crumb]
      else
        # first time we've seen this object - add a crumb
        id = uniqid()
        crumbs[id] = path + k
        v._crumb = id
        # and recurse...
        dst[k] = if util.isArray(v) then [] else {}
        walk v, dst[k], path + k + '/', crumbs

  # clean up any leftover '_crumb' properties in the source object
  clean = (obj) ->
    for k,v of obj
      continue unless typeof v is 'object'
      continue if v is null
      if v._crumb
        delete v._crumb
        clean v

  walk src, dest, '/', []
  clean src
  return dest

##
# Convert a JSON string into a response object
##
exports.fromJSON = fromJSON = (str) ->
  obj = JSON.parse str

  # convert a string-based reference marker into the real object data
  get_ref = (path, data) ->
    # lose the 'ref:/' and split
    parts = path.substr(5).split '/'
    val = data
    for p in parts
      val = val[p]
    return val

  # walk the object, converting ref markers into real object data,
  # possibly creating circular references as we go.
  walk = (my_data, data) ->
    for k,v of my_data
      if v? and typeof v is 'object'
        walk v, data
        continue
      if typeof v is 'string' and v.substr(0, 4) == 'ref:'
        my_data[k] = get_ref v, data

  # if an array, then we assume each element is a response object, so
  # dereference the markers individually
  if util.isArray obj
    for v in obj
      walk v, v
  else
    walk obj, obj
  return obj

##
# Setup a new route handler that can be called as a method
# of a LazyAppClient instance.
##
installRoute = (route) ->
  shortName = route.shortName
  shortName = shortName.substring(0,1).toUpperCase() + shortName.substring(1)
  for method in route.methods then do (method) =>
    tpl = parse_template(route.template)
    methodName = method.toLowerCase() + shortName
    @[methodName] = (opts, cb) ->
      vars    = opts.vars or {}
      body    = opts.body or null
      inlines = opts.inlines or []
      recurse = opts.recurse or false
      url     = tpl.expand(vars)
      if inlines.length > 0
        url = url + (if url.indexOf('?') == -1 then '?' else '&')
        url = url + 'inline=' + inlines.join(',')
        if recurse then url = url + '&inlineRecursive=true'
      request.call @, method, url, body, (err, data) =>
        return cb(err) if err?
        if data.data?
          if util.isArray data.data
            for o in data.data
              Object.defineProperty o, 'toJSON', {value: toJSON}
          else
            Object.defineProperty data.data, 'toJSON', {value: toJSON}
        cb(err, data)

##
# Send a single request to the API and return the JSON-decoded
# response.
##
request = (method, path, body, cb) ->
  if not cb
    cb = body
    body = null
  headers = {accept: 'application/json'}
  if body
    body = JSON.stringify body if typeof body is "object"
    headers['content-type'] = 'application/json'
    headers['content-length'] = body.length

  opts =
    host:    @config.host
    port:    @config.port
    path:    path
    method:  method
    headers: headers

  @pre_request opts, body
  req = http.request opts, (res) => recv.call @, res, (err, data) =>
    return cb err if err?
    return cb data.error if data.error?
    @post_request data
    cb null, data
  req.on 'error', (e) -> console.log e.stack; cb e
  req.write body if body
  req.end()
  return @

recv = (res, cb) ->
  res.setEncoding 'UTF8'
  body = []
  if res.headers['x-version']
    @api_version = res.headers['x-version']

  res.on 'data', (chunk) -> body.push chunk
  res.on 'end', =>
    try
      data = JSON.parse body.join("")
      data.statusCode = res.statusCode
    catch e
      return cb e
    cb null, data


# vim: expandtab:
