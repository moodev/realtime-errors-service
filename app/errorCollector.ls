require! {
  'lodash': _
  'moment': moment
  'bluebird': Promise
  'request-promise': request
}

moment := moment.utc  # quite important (sadly) to avoid 'daylight saving' nonsense etc.

# These are some highly dubious tuning parameters:
#   Obviously it's important to load at least as many errors as a client might feasibly deal with seeing at once.
#   It's also important to cache enough that a client gets an interesting amount of history on joining
#     – even if they've set a ridiculous filter.
#   In our case, these choices perform fine, so I haven't really worried about whether they make real sense.
#
CacheSize = 6000  # items to cache in memory
LoadLimit = 1000  # max items to accept from elasticsearch in one request.

# This also doesn't seem too bad on our cluster.
# Note that this delay is after the previous request's success – not a relentless interval despite sluggishness.
#
DelayBetweenPolls = 500ms


# These are initially no-op placeholder consumers, to be replaced with real consumers by the importer.
#
emitNewError = -> false  # emit an error from our application logs
emitDisaster = -> false  # emit an error with the realtime error service itself
emitStatus = -> false    # emit a notification that we sent a request to, or got a response from, ElasticSearch

got = new Set  # Cache of IDs of events we've already received, to de-duplicate them.
events = []    # History of events, ready to re-emit to newly-joining clients.

haveAClearOut = !->
  loseBefore = events.length - CacheSize
  if loseBefore > 0
    _.each (_.slice events, 0, loseBefore), (e)!-> got.delete e._id
    events := _.slice(events, loseBefore)


# TODO for approximate exactly-once behaviour (who cares, we rarely restart):
# At shutdown:
#   wait for a reasonable estimate of max. end-to-end log forwarder latency before dying
#   meanwhile keep yielding new errors if they are older than the last one sent when shutdown requested
#   otherwise anything that arrived after the last doc, but was timestamped before it, will be lost


getHistory = (sinceId)->
  toSend = null
  if sinceId
    lastSeen = _.findIndex(events, (e)-> e._id == sinceId)
    if lastSeen > -1
      toSend = _.slice(events, lastSeen + 1)
  else
    toSend = _.clone(events)
  return toSend


indicesForTimeRange = (since, upTo)->
  everyDayBetween = (since, upTo)->
    step = moment since .set { h:0, m:0, s:0, ms:0 }
    days = []
    do
      days.push step
      step := moment step .add(1, \d)  # TODO wtf am i doing here
    until step.isAfter upTo
    days

  _.map (everyDayBetween since, upTo), -> "logstash-error-logs-#{it.format('YYYY.MM.DD')}"


askElasticSearch = (sinceTime, loadLimit)->
  indices = indicesForTimeRange(sinceTime, moment!).join(',')
  EsUrl = "http://logstash-es.internal.moo.com:9201/#{indices}/_search"

  emitStatus {requestSent: new Date}
  request do
    method: \POST
    uri: EsUrl
    json: true
    timeout: 50*1000ms
    body: do
      size: loadLimit
      sort: [{ '@timestamp': { order: \desc } }]
      query: {
        bool: { must: [
          {range: {
            '@timestamp': { gt: sinceTime.format! }
          }},
          {term: { environment: 'production' }}
        ] }
      }
  .then (data)->
    return data.hits.hits
  .then (errors)->
    emitStatus {responseReceived: new Date}
    return errors
  .catch (err)->
    console.error err.error.code
    if err.error.code == \ETIMEDOUT or err.error.code == \ESOCKETTIMEDOUT
      return askElasticSearch(sinceTime, loadLimit)
    else
      return Promise.delay 8000ms, askElasticSearch(sinceTime, loadLimit)

processIncomingResults = (errors, emit=null)!->
  _.eachRight errors, (e)!->
    unless got.has e._id
      events.push e
      got.add e._id
      emit e if emit
  haveAClearOut!

pollAndUpdate = ->
  askElasticSearch moment!.subtract(5, \minutes), LoadLimit
  .then (errors)->
    processIncomingResults errors, emitNewError
  .then ->
    setTimeout pollAndUpdate, DelayBetweenPolls  # do it again
  .catch (e)->
    emitDisaster e

firstLoad = ->
  askElasticSearch moment!.subtract(30, \minutes), CacheSize
  .then (errors)->
    processIncomingResults errors, null  # no point in emitting if no clients will yet be connected
    console.info "First load: got #{_.size(errors)} events from ElasticSearch"
  .then ->
    setTimeout pollAndUpdate, DelayBetweenPolls  # commence normality
  .then ->
    true  # we've started! and that's all the information you're getting, importer!
  .catch (e)->
    emitDisaster e


export do

  # we can expose this directly – the since-id from a SSE consumer is just an ES document _id
  #
  getHistory: getHistory

  # trivial event handler binding (only one handler at a time)
  # trying to name errors-we-are-serving vs errors-with-the-service is a hilarious game
  #
  onNew: (f)!-> emitNewError := f
  onErrorServiceError: (f)!-> emitDisaster := f
  onStatus: (f)!-> emitStatus := f

  # must be called, and returns a promise which must resolve, before the service can be ready to deal with requests
  #
  start: firstLoad

  # for nodeunit
  #
  tests: do
    testIndicesForTimeRange: (test)->
      test.deepEqual do
        (indicesForTimeRange (moment '2008-02-08T00:02:00Z'), (moment '2008-02-08T00:02:00Z'))
        [ 'logstash-error-logs-2008.02.08' ]
        "Index names for single instant"
      test.deepEqual do
        (indicesForTimeRange (moment '2008-02-06T23:59:00Z'), (moment '2008-02-08T00:02:00Z'))
        [ 'logstash-error-logs-2008.02.06', 'logstash-error-logs-2008.02.07', 'logstash-error-logs-2008.02.08' ]
        "Index names for a range of days"
      test.deepEqual do
        (indicesForTimeRange (moment '2008-02-08T23:02:00Z'), (moment '2008-02-09T00:04:00+0100'))
        [ 'logstash-error-logs-2008.02.08' ]
        "Timezones aren't ruining everything"  # note this makes sense as all our error timestamps are UTC
      test.done!
