# Description
#   A hubot script that periodically checks whether a server is available or not.
#
# Configuration:
#   HUBOT_AVAILABLE_RETRIES (optional)
#   HUBOT_AVAILABLE_INTERVAL (optional)
#
# Commands:
#   hubot available[:help] - Show commands
#   hubot available:add <url> [interval=<interval>] - Add a job that checks the url if it is available with an optional interval (default is minutely)
#   hubot available:remove <url> - Remove a job
#   hubot available:list [all] - List all jobs in the room (or of all rooms)
#
# Notes:
#   Hubot's Brain is required for this script.
#   Namespace: hubot.brain.data.available.<actual-data>
#   This script is very similar to filipre/hubot-observe
#
# Author:
#   René Filip <renefilip@mail.com>

CronJob = require('cron').CronJob
async = require 'async'
moment = require 'moment'
HttpStatus = require 'http-status-codes'
normalizeUrl = require 'normalize-url'

myRobot = {}
robot = ->
  return myRobot

myJobs = {}     # Running "Cronjobs" by the npm cron package
jobs = ->
  return myJobs

myMemory = {}   # see "Namespace" above
memory = ->
  robot().brain.data.available ?= {}
  return robot().brain.data.available

reactions = [
  "He's dead, Jim: https://www.youtube.com/watch?v=MH7KYmGnj40",
  "Hello? Is there somebody who's responsible for? https://www.youtube.com/watch?v=PDZcqBgCS74",
  "The server is down. You could fix it.. Or you could watch this VHS recorder collection video: https://www.youtube.com/watch?v=-z4iw8Ppo1o",
  "RED ALERT https://www.youtube.com/watch?v=KUnHb2jnbpo",
  "http://i.imgur.com/wYqtu.jpg",
  "http://i.imgur.com/2Cw6NgH.jpg",
  "Time for a hard reset: http://i.imgur.com/BPGsKbc.jpg"
]

module.exports = (robo) ->
  initRobot robo
  robot().brain.on 'loaded', =>
    loadJobs()
    provideCommands()

initRobot = (robot) ->
  myRobot = robot

loadJobs = ->
  for roomName, roomObj of memory()
    for url, availableObj of roomObj
      myJobs[roomName] ?= {}
      myJobs[roomName][url] = createJob url, roomName

provideCommands = ->
  robot().respond /available(:help)?$/i, (msg) ->
    respondHelp msg

  robot().respond /available:add ([^\s\\]+)( interval=([^\"]+))?/i, (msg) ->
    respondAdd msg

  robot().respond /available:remove ([^\s\\]+)/i, (msg) ->
    respondRemove msg

  robot().respond /available:list( all)?/i, (msg) ->
    respondList msg

respondHelp = (msg) ->
  help = "List of commands:"
  help += "\n#{robot().name} available[:help] - Show commands"
  help += "\n#{robot().name} available:add <url> [interval=<interval>] - Add a job that checks the url if it is available with an optional interval (default is minutely)"
  help += "\n#{robot().name} available:remove <url> - Remove a job"
  help += "\n#{robot().name} available:list [all] - List all jobs in the room (or of all rooms)"
  msg.reply help

respondAdd = (msg) ->
  url = normalizeUrl msg.match[1]
  interval = msg.match[3] or "0 * * * * *" #default: minutely
  room = msg.message.room

  memory()[room] ?= {}
  if memory()[room].hasOwnProperty(url)
    msg.reply "URL already exists in ##{room}"
    return

  memory()[room][url] =
    interval: interval
    broken: false

  jobs()[room] ?= {}
  jobs()[room][url] = createJob url, room

  msg.reply "#{url} in ##{room} added"

respondRemove = (msg) ->
  url = normalizeUrl msg.match[1]
  room = msg.message.room

  memory()[room] ?= {}
  if not memory()[room].hasOwnProperty(url)
    msg.reply "#{url} in ##{room} does not exist"
    return

  jobs()[room][url].stop()
  delete jobs()[room][url]
  delete memory()[room][url]

  msg.reply "#{url} in ##{room} deleted"

respondList = (msg) ->
  formatJob = (room, url, interval, broken) ->
    brokenStr = if broken then "(broken)" else ""
    return "\n##{room}: #{url} [#{interval}] #{brokenStr}"

  all = if msg.match[1] then true else false
  room = msg.message.room

  if all
    reply = "All jobs from all rooms:"
    for room, roomObj of memory()
      for url, availableObj of roomObj
        reply += formatJob room, url, availableObj.interval, availableObj.broken
    msg.reply reply
    return

  reply = "All jobs from ##{room}:"
  memory()[room] ?= {}
  for url, availableObj of memory()[room]
    reply += formatJob room, url, availableObj.interval, availableObj.broken
  msg.reply reply

createJob = (url, room) ->
  return new CronJob(
    cronTime: memory()[room][url].interval # humanToCron interval
    onTick: ->
      checkUrl url, room
    start: true
  )

checkUrl = (url, room) ->

  performRequest = (callback, result) ->
    acceptCode = (code) ->
      acceptedCodes = [
        HttpStatus.OK,
        HttpStatus.CREATED,
        HttpStatus.ACCEPTED,
        HttpStatus.NON_AUTHORITATIVE_INFORMATION,
        HttpStatus.NO_CONTENT,
        HttpStatus.RESET_CONTENT,
        HttpStatus.PARTIAL_CONTENT,
        HttpStatus.MULTI_STATUS
      ]
      return code in acceptedCodes

    robot().http(url).get() (err, res, body) ->
      if err
        return callback err
      if not acceptCode res.statusCode
        return callback "Unsuccessful status code #{res.statusCode}: #{HttpStatus.getStatusText(res.statusCode)}"
      return callback null

  notifyUser = (err) ->
    random = (items) ->
      items[Math.floor(Math.random() * items.length)]

    # sometimes it happens that the user deletes a job that is still running.
    if not memory()[room][url]
      return

    # after some tries mark url as broken and notify user the first time
    if err
      if not memory()[room][url].broken
        memory()[room][url].broken = true
        memory()[room][url].downtime = moment()
        robot().messageRoom room, "#{url} is not working: #{err}"
        if Math.random() < (1/3) then robot().messageRoom room, random reactions
      return

    # notify the user if url works again
    if memory()[room][url].broken
      memory()[room][url].broken = false
      downtime = memory()[room][url].downtime
      duration = moment.duration(moment().diff(downtime)).humanize()
      robot().messageRoom room, "#{url} works again. Yeah! Downtime: #{duration}"

  async.retry {
    times: process.env.HUBOT_AVAILABLE_RETRIES or 5
    interval: process.env.HUBOT_AVAILABLE_INTERVAL or 5000
  }, performRequest, notifyUser
