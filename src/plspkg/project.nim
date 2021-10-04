import
  os,
  json,
  logging,
  strutils,
  sequtils,
  pegs

type
  PlsProject* = object
    dir*: string
    tasks*: JsonNode
    targets*: JsonNode
    tasklists*: JsonNode


type PlsError = ref object of ValueError 

const plsTpl* = "pls.json".slurp
const systemHelp = "help.json".slurp

let placeholder = peg"'{{' {[^}]+} '}}'"

proc newPlsProject*(dir: string): PlsProject =
  result.dir = dir

proc configFile*(prj: PlsProject): string = 
  return prj.dir/"pls.json"

proc configured*(prj: PlsProject): bool =
  return fileExists(prj.configFile)

proc init*(prj: var PlsProject) =
  var o = parseJson(plsTpl)
  prj.configFile.writeFile(o.pretty)

proc load*(prj: var PlsProject) =
  if not prj.configFile.fileExists:
    fatal "Project not initialized - configuration file not found."
    quit(10)
  let cfg = prj.configFile.parseFile
  prj.tasks = cfg["tasks"]
  prj.targets = cfg["targets"]
  if cfg.hasKey("dir"):
    prj.dir = cfg["dir"].getStr

proc help*(prj: var PlsProject): JsonNode =
  result = newJObject()
  if prj.configured:
    prj.load
    for k, v in systemHelp.parseJson.pairs:
      result[k] = v
    for k, v in prj.tasks.pairs:
      if v.hasKey("_syntax") and v.hasKey("_description"):
        result[k] = ("""
          {
            "_syntax": "$1",
            "_description": "$2"
          }
        """ % [v["_syntax"].getStr, v["_description"].getStr]).parseJson

proc save*(prj: PlsProject) = 
  var o = newJObject()
  o["tasks"] = %prj.tasks
  o["targets"] = %prj.targets
  prj.configFile.writeFile(o.pretty)

proc defTarget*(prj: var PlsProject, alias: string, props: var JsonNode) =
  for k, v in props.mpairs:
    if v == newJNull():
      props.delete(k)
  prj.load
  if not prj.targets.hasKey alias:
    notice "Adding target '$1'..." % alias
    prj.targets[alias] = newJObject()
    prj.targets[alias]["name"] = %alias
  else:
    notice "Updating target '$1'..." % alias
    prj.targets[alias] = newJObject()
  for key, val in props.pairs:
    prj.targets[alias][key] = val
    notice "  $1: $2" % [key, $val]
  prj.save
  notice "Target '$1' saved." % alias

proc undefTarget*(prj: var PlsProject, alias: string) =
  prj.load
  prj.targets.delete(alias)
  prj.save
  notice "Target '$1' removed." % alias

proc defTask*(prj: var PlsProject, alias: string, props: var JsonNode) =
  for k, v in props.mpairs:
    if v == newJNull():
      props.delete(k):
    elif v.kind == JObject:
      for kk, vv in v.pairs:
        if vv == newJNull():
          v.delete(kk)
  prj.load
  if not prj.tasks.hasKey alias:
    notice "Adding task '$1'..." % alias
    prj.tasks[alias] = newJObject()
  else:
    notice "Updating task '$1'..." % alias
    prj.tasks[alias] = newJObject()
  for key, val in props.pairs:
    prj.tasks[alias][key] = val
    notice "  $1: $2" % [key, $val]
  prj.save
  notice "Task '$1' saved." % alias

proc undefTask*(prj: var PlsProject, alias: string) =
  prj.load
  prj.tasks.delete(alias)
  prj.save
  notice "Task '$1' removed." % alias

proc lookupTask(prj: PlsProject, task: string, props: seq[string], cmd: var JsonNode): bool =
  if not prj.tasks.hasKey task:
    warn "Task '$1' not found" % task
    return
  var cmds = prj.tasks[task]
  var score = 0
  # Cycle through task definitions
  for key, val in cmds:
    if key == "_syntax" or key == "_description":
      continue
    var params = key.split("+")
    # Check if all params are available
    var match = params.all do (x: string) -> bool:
      props.contains(x)
    if match and params.len > score:
      score = params.len
      cmd = val
  return score > 0
  
proc execute*(prj: var PlsProject, task, alias: string): int {.discardable.} =
  prj.load
  if not prj.targets.hasKey alias:
    raise PlsError(msg: "Target definition '$1' not found. Nothing to do." % [alias])
  notice "$1: $2" % [task, alias]
  let target = prj.targets[alias]
  var keys = newSeq[string](0)
  for key, val in target.pairs:
    keys.add key
  var res: JsonNode
  var cmd: string
  var pwd = prj.dir
  if target.hasKey("dir"):
    pwd = target["dir"].getStr
  if prj.lookupTask(task, keys, res):
    cmd = res["cmd"].getStr.replace(placeholder) do (m: int, n: int, c: openArray[string]) -> string:
      return target[c[0]].getStr
    if res.hasKey("pwd"):
      pwd = res["pwd"].getStr.replace(placeholder) do (m: int, n: int, c: openArray[string]) -> string:
        return target[c[0]].getStr
      pwd = prj.dir/pwd
    notice "Executing: $1" % cmd
    pwd.createDir()
    pwd.setCurrentDir()
    result = execShellCmd cmd
  else:
    debug "Task '$1' not available for target '$2'" % [task, alias]
  setCurrentDir(prj.dir)

proc executeRec*(prj: var PlsProject, task, alias: string) =
  prj.load
  let pwd = getCurrentDir()
  var dir = alias
  if (execute(prj, task, alias) != 0):
    return
  if prj.targets[alias].hasKey("dir"):
    dir = prj.targets[alias]["dir"].getStr
  var childProj = newPlsProject(pwd/prj.dir/dir)
  if childProj.configured:
    childProj.load()
    setCurrentDir(childProj.dir)
    for key, val in childProj.targets.pairs:
      childProj.executeRec(task, key)
    setCurrentDir(pwd)
