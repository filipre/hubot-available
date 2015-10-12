# Description
#   A hubot script that periodically checks whether a server is available or not.
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
# humanToCron = require('human-to-cron')

# Running "Cronjobs" by the npm cron package
jobs = {}


checkUrl = (url, room, robot) ->

  performRequest = (callback, result) ->
    robot.http(url).get() (err, res, body) ->
      # HTTP error
      if err
        return callback err, null

      # JSON Parsing Error (maybe not a json)
      try
        result = JSON.parse body
      catch err
        return callback err, null

      # # no 'text' property
      # if not result.hasOwnProperty 'text'
      #   err = "JSON does not have a 'text' property at root"
      #   return callback err, null

      # TODO
      # return error or result depending on HTTP status code

      return callback null, result.text

  notifyUser = (err, text) ->
    # after 3 tries mark url as broken and notify user the first time
    if err
      if not robot.brain.data.available[room][url].broken
        robot.messageRoom room, "#{url} is not working: #{err}"
      robot.brain.data.available[room][url].broken = true
      return

    # URL is working (again)

    # TODO
    # notify the user that it is working again

    # robot.brain.data.available[room][url].broken = false
    # if robot.brain.data.available[room][url].text isnt text
    #   robot.brain.data.available[room][url].text = text
    #   robot.messageRoom room, "#{text}"

    # TODO
    # think of better reply message (with error code, message, status, date, gist?, ...)

  async.retry {
    times: 3  # TODO: maybe ENV?
    interval: 5000 # TODO: maybe ENV?
  }, performRequest, notifyUser


createJob = (url, room, robot) ->
  return new CronJob(
    cronTime: robot.brain.data.available[room][url].interval # humanToCron interval
    onTick: ->
      checkUrl url, room, robot
    start: true
  )


provideCommands = (robot) ->

  robot.respond /available(:help)?$/i, (msg) ->

    help = "List of commands:"
    help += "\n#{robot.name} available[:help] - Show commands"
    help += "\n#{robot.name} available:add <url> [interval=<interval>] - Add a job that checks the url if it is available with an optional interval (default is minutely)"
    help += "\n#{robot.name} available:remove <url> - Remove a job"
    help += "\n#{robot.name} available:list [all] - List all jobs in the room (or of all rooms)"

    msg.reply help


  robot.respond /available:add ([^\s\\]+)( interval=([^\"]+))?/i, (msg) ->

    url = msg.match[1]
    interval = msg.match[3] || "0 * * * * *" #default: minutely
    room = msg.message.room

    robot.brain.data.available[room] ?= {}

    if robot.brain.data.available[room].hasOwnProperty(url)
      msg.reply "URL already exists in ##{room}"
      return

    # source of truth
    robot.brain.data.available[room][url] =
      interval: interval
      broken: false

    jobs[room] ?= {}
    jobs[room][url] = createJob url, room, robot

    msg.reply "#{url} in ##{room} added"


  robot.respond /available:remove ([^\s\\]+)/i, (msg) ->

    url = msg.match[1]
    room = msg.message.room

    robot.brain.data.available[room] ?= {}

    if !robot.brain.data.available[room].hasOwnProperty(url)
      msg.reply "#{url} in ##{room} does not exist"
      return

    jobs[room][url].stop()
    delete jobs[room][url]
    delete robot.brain.data.available[room][url]

    msg.reply "#{url} in ##{room} deleted"


  robot.respond /available:list( all)?/i, (msg) ->

    formatJob = (room, url, interval, broken) ->
      brokenStr = if broken then "(broken)" else ""
      return "\n##{room}: #{url} [#{interval}] #{brokenStr}"

    all = if msg.match[1] then true else false
    room = msg.message.room

    if all
      reply = "All jobs from all rooms:"
      for room, roomObj of robot.brain.data.available
        for url, availableObj of roomObj
          reply += formatJob room, url, availableObj.interval, availableObj.broken
      msg.reply reply
      return

    reply = "All jobs from ##{room}:"
    robot.brain.data.available[room] ?= {}
    for url, availableObj of robot.brain.data.available[room]
      reply += formatJob room, url, availableObj.interval, availableObj.broken
    msg.reply reply


module.exports = (robot) ->

  robot.brain.on 'loaded', =>
    robot.brain.data.available ?= {}

    # load existing jobs from the brain
    for roomName, roomObj of robot.brain.data.available
      for url, availableObj of roomObj
        jobs[roomName] ?= {}
        jobs[roomName][url] = createJob url, roomName, robot

    # only provide methods if brain is loaded
    provideCommands robot
