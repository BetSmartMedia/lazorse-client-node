http = require 'http'
util = require 'util'
parse_template = require('uri-template').parse
{EventEmitter} = require 'events'


exports.LazyAppClient = class LazyAppClient extends EventEmitter
  constructor: (@config, cb) ->
    request.call @, 'GET', '/', null, (err, routes) =>
      if not err and routes.statusCode != 200
        err = new Error routes?.error or routes?.warning or "Failed to get index"
      if err
        if cb then return cb err else throw err

      for route in routes.data
        installMethods.call @, route

      @emit 'ready'
      cb() if cb

  pre_request: (request_opts, body) ->
    ### A hook for subclasses to alter request options before sending it off. ###
    undefined

  post_request: (data, opts, res) ->
    ### A hook for subclasses to alter response data ###
    undefined

  get: (path, cb) ->
    ### Convenience method for .request('GET', ...) ###
    request.call @, 'GET', path, null, cb

  post: (path, body, cb) ->
    ### Convenience method for .request('POST', ...) ###
    request.call @, 'POST', path, body, cb

deref = (obj) ->
  ### Convert string refs back into circular refs ###
 
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

installMethods = (resource) ->
  ###
  Setup a new route handler that can be called as a method
  of a LazyAppClient instance.
  ###
  shortName = resource.shortName
  shortName = shortName.substring(0,1).toUpperCase() + shortName.substring(1)
  for method in resource.methods then do (method) =>
    tpl = parse_template(resource.template)
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
        cb(err, data)

request = (method, path, body, cb) ->
  ###
  Send a single request to the API and return the JSON-decoded
  response.
  ###
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
    deref data
    @post_request data, opts, res
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
