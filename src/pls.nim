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
  plspkg/project,
  plspkg/messaging

let usage* = """  $1 v$2 - $3
  (c) 2021 $4

  Usage:
    pls <task> [<target>]           Executes <task> (on <target>).

    => For more information on available tasks, run: pls help

  Options:
    --help,    -h           Displays this message.
    --force,   -f           Do not ask for confirmation when executing the specified task.
    --global,  -g           Execute task within the global project instead of the local one.
    --log,     -l           Specifies the log level (debug|info|notice|warn|error|fatal).
                            Default: info
    --version, -h           Displays the version of the application.
""" % [pkgTitle, pkgVersion, pkgDescription, pkgAuthor]

var force = false
var global = false

# Helper Methods

proc addProperty(parentObj: JsonNode, name = ""): tuple[key: string, value: JsonNode] =
  var done = false
  while (not done):
    if name == "":
      result.key = editValue("Name")
    elif name == "name":
      warn "Property identifier 'name' cannot be modified."
    else:
      printValue(" Name", name)
      result.key = name
    var ok = false
    while (not ok):
      var value = ""
      if parentObj.hasKey(result.key):
        value = $parentObj[result.key]
      try:
        result.value = editValue("Value", value).parseJson
        if (result.value == newJNull()):
          ok = confirm("Remove property '$1'?" % result.key)
          done = true
        else:
          ok = true
      except:
        warn("Please enter a valid JSON value.")
    done = done or confirm("OK?")
    
proc addProperties(obj: var JsonNode) =
  var done = false
  while (not done):
    let prop = addProperty(obj)
    obj[prop.key] = prop.value
    done = not confirm("Do you want to add/remove more properties?")

proc addTaskDefinition(parentObj: JsonNode, name = ""): tuple[key: string, value: JsonNode] =
  # TODO: validate name of task definition! (not _syntax or _description, etc.)
  if name == "":
    result.key = editValue("Task Definition Matcher")
  else:
    printValue(" Task Definition Matcher", name)
    result.key = name
  result.value = newJObject()
  result.value["cmd"] = addProperty(parentObj[name], "cmd").value
  result.value["pwd"] = addProperty(parentObj[name], "pwd").value
  # TODO: delete task definition matcher if all properties are null.

proc addTaskDefinitions(obj: var JsonNode) =
  var done = false
  while (not done):
    let prop = addTaskDefinition(obj)
    obj[prop.key] = prop.value
    done = not confirm("Do you want to add/remove more task definitions?") 

proc changeValue(oldv: tuple[label: string, value: JsonNode], newv: tuple[label: string, value: JsonNode]): bool =
  if oldv.value != newJNull():
    printDeleted(oldv.label, $oldv.value)
  if newv.value != newJNull():
    printAdded(newv.label, $newv.value)
  return confirm("Confirm change?")

proc updateDefinitions(prj: var PlsProject): bool =
  result = false
  let sysTasks = plsTpl.parseJson["tasks"]
  for k, v in sysTasks.pairs:
    if prj.tasks.hasKey(k):
      let sysTask = sysTasks[k]
      var prjTask = prj.tasks[k]
      for prop, val in sysTask.pairs:
        let sysProp = sysTask[prop]
        var prjProp = newJNull()
        if prjTask.hasKey(prop):
          prjProp = prjTask[prop]
        if prjProp != newJNull():
          if prjProp != sysProp:
            let sysVal = (label: k & "." & prop, value: sysProp)
            let prjVal = (label: k & "." & prop, value: prjProp)
            if changeValue(prjVal, sysVal):
              prjTask[prop] = sysProp
              result = true
        else:
          result = true
          # Adding new property
          printAdded("$1.$2" % [k, prop], $sysProp)
          prjTask[prop] = sysProp
    else:
      result = true
      # Adding new task
      printAdded(k, $sysTasks[k])
      prj.tasks[k] = sysTasks[k]

### MAIN ###

var args = newSeq[string](0)

for kind, key, val in getopt():
  case kind:
    of cmdArgument:
      args.add key 
    of cmdLongOption, cmdShortOption:
      case key:
        of "force", "f":
          force = true
        of "global", "g":
          global = true
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

var localPrj = newPlsProject(getCurrentDir())

var globalPrj: PlsProject

if defined(windows):
  globalPrj = newPlsProject(getenv("USERPROFILE"))
if not defined(windows):
  globalPrj = newPlsProject(getenv("HOME"))

if not globalPrj.configured:
  globalPrj.init()

globalPrj.load()

var prj = localPrj

if global:
  prj = globalPrj 

if args.len == 0:
  echo usage
  quit(0)
case args[0]:
  of "init":
    if prj.configured:
      fatal "Project already configured."
      quit(2)
    prj.init()
    notice "Project initialized."
  of "def":
    if args.len < 3:
      fatal "No alias specified."
      quit(3)
    let kind = args[1]
    let alias = args[2]
    var props = newJObject()
    if not ["target", "task"].contains(kind):
      fatal "Unknown definition type $1" % kind
      quit(6)
    prj.load
    if kind == "target":
      if prj.targets.hasKey(alias):
        notice "Redefining existing target: " & alias
        warn "Specify properties for target '$1':" % alias
        props = prj.targets[alias]
        for k, v in props.mpairs:
          if k == "name":
            continue
          let prop = addProperty(props, k)
          props[prop.key] = prop.value
        if confirm "Do you want to add/remove more properties?":
          addProperties(props)
      else:
        notice "Definining new target: " & alias
        warn "Specify properties for target '$1':" % alias
        addProperties(props)
      prj.defTarget(alias, props) 
    else: # task
      if prj.tasks.hasKey(alias):
        notice "Redefining existing task: " & alias
        warn "Specify properties for task '$1':" % alias
        props = prj.tasks[alias]
        for k, v in props.mpairs:
          if ["_syntax", "_description"].contains(k):
            let prop = addProperty(props, k)
            props[prop.key] = prop.value
          else:
            let prop = addTaskDefinition(props, k)
            props[prop.key] = prop.value
        if confirm "Do you want to add/remove more task definitions?":
          addTaskDefinitions(props)
      else:
        props["_syntax"] = addProperty(props, "_syntax").value
        props["_description"] = addProperty(props, "_description").value
        addTaskDefinitions(props)
      prj.defTask(alias, props)
  of "undef":
    if args.len < 3:
      fatal "No alias specified."
      quit(3)
    let kind = args[1]
    let alias = args[2]
    if not ["target", "task"].contains(kind):
      fatal "Unknown definition type $1" % kind
      quit(6)
    prj.load
    if kind == "target":
      if not prj.targets.hasKey(alias):
        fatal "Target '$1' not defined." % [alias]
        quit(4)
      if force or confirm("Remove definition for target '$1'?" % alias):
        prj.undefTarget(alias) 
    else: # task
      if not prj.tasks.hasKey(alias):
        fatal "Task '$1' not defined." % [alias]
        quit(4)
      if force or confirm("Remove definition for task '$1'?" % alias):
        prj.undefTask(alias) 
  of "info":
    prj.load
    if args.len < 2:
      for t, props in prj.targets.pairs:
        echo "$1:" % [t]
        for k, v in props.pairs:
          echo " - $1:\t$2" % [k, $v]
    else:
      let alias = args[1]
      if not prj.targets.hasKey(alias):
        fatal "Target '$1' not defined." % [alias]
        quit(4)
      let data = prj.targets[alias]
      for k, v in data.pairs:
        echo "$1:\t$2" % [k, $v]
  of "update":
    prj.load
    if updateDefinitions(prj):
      prj.save
  of "help":
    echo ""
    if args.len < 2:
      var sortedKeys = toSeq(prj.help.keys)
      sortedKeys.sort(cmp[string])
      for k in sortedKeys:
        printGreen "   pls $1" % prj.help[k]["_syntax"].getStr
        echo "\n      $1\n" % prj.help[k]["_description"].getStr
    else:
      let cmd = args[1]
      let help = prj.help[cmd]
      if not prj.help.hasKey(cmd):
        fatal "Task '$1' is not defined." % cmd
        quit(5)
      printGreen "   pls " & help["_syntax"].getStr
      echo "\n      $1\n" % help["_description"].getStr
  else:
    if args.len < 1:
      echo usage
      quit(1)
    if args.len < 2:
      prj.load
      var targets = toSeq(prj.targets.pairs)
      if targets.len == 0:
        warn "No targets defined - nothing to do."
        quit(0)
      for key, val in prj.targets.pairs:
        prj.execute(args[0], key) 
    else:
      try:
        prj.execute(args[0], args[1]) 
      except:
        # Fallback to global project
        if prj == localPrj:
          try:
            globalPrj.execute(args[0], args[1])
          except:
            warn getCurrentExceptionMsg()
        else:
          warn getCurrentExceptionMsg()
