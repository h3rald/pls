import
  os,
  tables,
  json,
  logging,
  strutils,
  sequtils,
  pegs

type
  PlsProject* = object
    version*: int
    dir*: string
    tasks*: JsonNode
    targets*: JsonNode


type PlsError = ref object of ValueError 
type SystemTask = proc (params: string): void 

const plsTpl* = "pls.json".slurp
const systemHelp = "help.json".slurp

let systemProps = @["$$os:$1" % hostOS, "$$cpu:$1" % hostCPU]
let placeholder = peg"'{{' {[^}]+} '}}'"
var systemTasks = initTable[string, SystemTask]()
systemTasks["$setCurrentDir"] = proc (params: string) = setCurrentDir(params)

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
  prj.version = cfg["version"].getInt
  prj.tasks = cfg["tasks"]
  prj.targets = cfg["targets"]
  # Set system properties

proc help*(prj: var PlsProject): JsonNode =
  result = newJObject()
  if prj.configured:
    prj.load
    for k, v in systemHelp.parseJson.pairs:
      result[k] = v
    for k, v in prj.tasks.pairs:
      if v.hasKey("$syntax") and v.hasKey("$description"):
        result[k] = ("""
          {
            "$$syntax": "$1",
            "$$description": "$2"
          }
        """ % [v["$syntax"].getStr, v["$description"].getStr]).parseJson

proc save*(prj: PlsProject) = 
  var o = newJObject()
  o["version"] = %prj.version
  o["tasks"] = %prj.tasks
  o["targets"] = %prj.targets
  prj.configFile.writeFile(o.pretty)

proc defTarget*(prj: var PlsProject, alias: string, props: var JsonNode) =
  for k, v in props.mpairs:
    if v == newJNull():
      props.delete(k)
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

proc lookupTask(prj: PlsProject, task: string, ps: seq[string], cmd: var JsonNode): bool =
  let props = ps.concat(systemProps);
  if not prj.tasks.hasKey task:
    warn "Task '$1' not found" % task
    return
  var cmds = prj.tasks[task]
  var score = 0
  # Cycle through task definitions
  for key, val in cmds:
    if key == "$syntax" or key == "$description":
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
  if prj.lookupTask(task, keys, res):
    cmd = res["cmd"].getStr.replace(placeholder) do (m: int, n: int, c: openArray[string]) -> string:
      return target[c[0]].getStr
    notice "Executing: $1" % cmd
    if cmd[0] == '$':
      let parts = cmd.split(" ")
      if systemTasks.hasKey(parts[0]):
        systemTasks[parts[0]](parts[1..parts.len-1].join(" "))
      else:
        result = execShellCmd cmd
  else:
    debug "Task '$1' not available for target '$2'" % [task, alias]
  setCurrentDir(prj.dir)
