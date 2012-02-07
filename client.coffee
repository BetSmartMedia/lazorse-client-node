http = require 'http'
parse_template = require('uri-template').parse

module.exports = class LazyAppClient
  constructor: (@config, cb) ->
    request.call @, 'GET', '/', (err, routes) =>
      if err
        if cb then return cb err else throw err
      if routes.statusCode != 200
        throw new Error res.error or res.warning
      
      for route in routes then do (route) =>
        shortName = route.shortName
        shortName = shortName.substring(0,1).toUpperCase() + shortName.substring(1)
        for method in route.methods then do (method) =>
          methodName = method.toLowerCase() + shortName
          tpl = parse_template(route.template)
          @[methodName] = (tpl_vars={}, body=null, cb) =>
            request.call(@, method, tpl.expand(tpl_vars), body, cb)
      # Don't collect loop results

      cb() if cb
      return null

  ###
  A hook for subclasses to alter the request (e.g. add special headers)
  before sending it off.
  ###
  pre_request: (request_opts, body) -> undefined

  ###
  A hook for subclasses to alter the response data
  ###
  post_request: (data) -> undefined

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

    @pre_request opts
    req = http.request opts, (res) => recv.call @, res, cb
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
      @post_request data
      cb null, data

# vim: expandtab:
