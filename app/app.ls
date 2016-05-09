require! {
  'lodash': _
  'express': express
  'cors': cors
  './errorCollector': errorCollector
}

Args = require \yargs .argv
ListenPort = parseInt Args.port || 8001

app = express!
app.use cors!

outputs = new Set  # Will hold refs to all the clients

# Format a bunch of key/value pairs ('an event') in the normal SSE format.
#
formatLines = (keyValues)->
  string = _ keyValues
    .map (v,k)-> "#{k}: #{v}"
    .join '\n'
  return string + '\n\n'

# Helper to easily send an SSE key/value block to everyone.
# Usable for everything except the main error documents, for which outputs have custom filters.
#
yieldLinesToAll = (keyValues)!->
  string = formatLines keyValues
  outputs.forEach (output)!-> output string

formatError = (error)-> formatLines do
  event: \errorReport
  id: error._id
  data: JSON.stringify error  # TODO maybe we only need the [_source] object, or selected fields…

errorCollector.onNew (error)!->
  string = formatError error
  outputs.forEach (output)!->
    output string if output.errorFilter error

errorCollector.onErrorServiceError (error)!-> yieldLinesToAll do
  event: \error
  data: JSON.stringify error

errorCollector.onStatus (status)!-> yieldLinesToAll do
  event: \elasticsearchStatus
  data: JSON.stringify status


app.get '/', (req, res)!->
  req.socket.setTimeout 0
    # Ensure connection does not time out.
    # No decent docs on this but it seems to work! Browsers would automatically reconnect anyway if not.

  res.writeHead 200, do
    'Content-Type': 'text/event-stream'
    'Cache-Control': 'no-cache'
    'Connection': 'keep-alive'
  res.write '\n'

  output = (string)!-> res.write string
  output.errorFilter = -> true
    # Default to just outputting every incoming error

  # Apply custom filter if the client wants to only get errors/warnings for some services ('source' field)
  #
  if req.query.errorSources or req.query.warningSources
    errorSources = req.query.errorSources?.split ','
    warningSources = req.query.warningSources?.split ','
    output.errorFilter = (error)->
      if error._source.level == 'WARNING'
        !warningSources || _.includes warningSources, error._source.source
      else
        !errorSources || _.includes errorSources, error._source.source

  # Immediately send recent history if the client is interested in that.
  # Presence of a 'last-event-id' header, per SSE spec, indicates this is a browser which dropped and reconnected.
  #
  if req.headers.'last-event-id' or req.query.includeBackfill?
    backfillSize = 200
    hist = errorCollector.getHistory (req.headers.'last-event-id' || null)
    _ hist
      .filter output.errorFilter
      .takeRight backfillSize
      .value!
      .forEach (error)!-> output formatError error

  # Subscribe; and later, unsubscribe
  #
  outputs.add output
  req.on \close, !-> outputs.delete output


errorCollector.start!.then !->
  app.listen ListenPort
  console.info "Ready! Express server listening on port #{ListenPort} in #{app.settings.env} mode"


# Send periodic reassurance/info to every client
#
setInterval _, 5000 <| !->
  yieldLinesToAll do
    event: \heartbeat
    data: JSON.stringify do
      time: new Date
      listeners: outputs.size
