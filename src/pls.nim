import 
  json,
  os,
  parseopt,
  logging,
  algorithm,
  strutils,
  sequtils

import
  plspkg/plslogger

newPlsLogger().addHandler()
setLogFilter(lvlInfo)

import
  plspkg/config,
  plspkg/project

let usage* = """  $1 v$2 - $3
  (c) 2021 $4

  Usage:
    pls <task> [<target>]           Executes <task> (on <target>).

    => For more information on available tasks, run: pls help

  Options:
    --help,    -h           Displays this message.
    --log,     -l           Specifies the log level (debug|info|notice|warn|error|fatal).
                            Default: info
    --version, -h           Displays the version of the application.
""" % [pkgTitle, pkgVersion, pkgDescription, pkgAuthor]


# Helper Methods

proc update(PROJECT: var PlsProject, sysProject: JsonNode): bool {.discardable.} =
  result = false
  let sysTasks = sysProject["tasks"]
  for k, v in sysTasks.pairs:
    if PROJECT.tasks.hasKey(k):
      let sysTask = sysTasks[k]
      var prjTask = PROJECT.tasks[k]
      for prop, val in sysTask.pairs:
        let sysProp = sysTask[prop]
        var prjProp = newJNull()
        if prjTask.hasKey(prop):
          prjProp = prjTask[prop]
        if prjProp == newJNull():
          result = true
          # Adding new property
          prjTask[prop] = sysProp
    else:
      result = true
      # Adding new task
      PROJECT.tasks[k] = sysTasks[k]

### MAIN ###

var args = newSeq[string](0)

for kind, key, val in getopt():
  case kind:
    of cmdArgument:
      args.add key 
    of cmdLongOption, cmdShortOption:
      case key:
        of "log", "l":
          var val = val
          setLogLevel(val)
        of "help", "h":
          echo usage
          quit(0)
        of "version", "v":
          echo pkgVersion
          quit(0)
        else:
          discard
    else:
      discard


var PROJECT: PlsProject

if defined(windows):
  PROJECT = newPlsProject(getenv("USERPROFILE"))
if not defined(windows):
  PROJECT = newPlsProject(getenv("HOME"))

if not PROJECT.configured:
  PROJECT.init()

PROJECT.load()
let sysProject = plsTpl.parseJson()
let version = sysProject["version"].getInt
if PROJECT.version < version:
  notice "Updating pls.json file..."
  PROJECT.update(sysProject)
  PROJECT.version = version 
  PROJECT.save()
  notice "Done."

if args.len == 0:
  echo usage
  quit(0)
case args[0]:
  of "info":
    if args.len < 2:
      for t, props in PROJECT.targets.pairs:
        echo "\n   $1:" % [t]
        for k, v in props.pairs:
          echo "   - $1:\t$2" % [k, $v]
    else:
      let alias = args[1]
      if not PROJECT.targets.hasKey(alias):
        fatal "Target '$1' not defined." % [alias]
        quit(4)
      let data = PROJECT.targets[alias]
      for k, v in data.pairs:
        echo "\n   $1:\t$2" % [k, $v]
  of "help":
    echo ""
    if args.len < 2:
      var sortedKeys = toSeq(PROJECT.help.keys)
      sortedKeys.sort(cmp[string])
      for k in sortedKeys:
        echo "   pls $1" % PROJECT.help[k]["$syntax"].getStr
        echo "      $1\n" % PROJECT.help[k]["$description"].getStr
    else:
      let cmd = args[1]
      let help = PROJECT.help[cmd]
      if not PROJECT.help.hasKey(cmd):
        fatal "Task '$1' is not defined." % cmd
        quit(5)
      echo "   pls " & help["$syntax"].getStr
      echo "\n      $1\n" % help["$description"].getStr
  else:
    if args.len < 1:
      echo usage
      quit(1)
    if args.len < 2:
      var targets = toSeq(PROJECT.targets.pairs)
      if targets.len == 0:
        warn "No targets defined - nothing to do."
        quit(0)
      for key, val in PROJECT.targets.pairs:
        PROJECT.execute(args[0], key) 
    else:
      try:
        PROJECT.execute(args[0], args[1]) 
      except:
        warn getCurrentExceptionMsg()
