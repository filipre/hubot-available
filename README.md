# hubot-available

A hubot script that periodically checks whether a server is available or not.

See [`src/available.coffee`](src/available.coffee) for full documentation.

![example](https://raw.githubusercontent.com/filipre/hubot-available/master/example.png)

## Installation

In hubot project repo, run:

`npm install hubot-available --save`

Then add **hubot-available** to your `external-scripts.json`:

```json
[
  "hubot-available"
]
```

## Commands

- `hubot available[:help]`: Show commands
- `hubot available:add <url> [interval=<interval>]`: Add a job that checks the url if it is available with an optional interval (default is minutely)
- `hubot available:remove <url>`: Remove a job by url
- `hubot available:list [all]`: List all jobs in the room (or of all rooms)
