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
    commands*: JsonNode
    targets*: JsonNode
    tasklists*: JsonNode

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
  prj.commands = cfg["commands"]
  prj.targets = cfg["targets"]
  if cfg.hasKey("dir"):
    prj.dir = cfg["dir"].getStr

proc help*(prj: var PlsProject): JsonNode =
  result = systemHelp.parseJson
  if prj.configured:
    prj.load
    for k, v in prj.tasklists.pairs:
      let syntax = "$$$1" % k
      let description = "Executes: $1" % v.elems.mapIt(it.getStr).join(", ")
      result["$"&k] = ("""
        {
          "_syntax": "$1",
          "_description": "$2"
        }
      """ % [syntax, description]).parseJson  
    for k, v in prj.commands.pairs:
      if v.hasKey("_syntax") and v.hasKey("_description"):
        result[k] = ("""
          {
            "_syntax": "$1",
            "_description": "$2"
          }
        """ % [v["_syntax"].getStr, v["_description"].getStr]).parseJson

proc save*(prj: PlsProject) = 
  var o = newJObject()
  o["commands"] = %prj.commands
  o["targets"] = %prj.targets
  prj.configFile.writeFile(o.pretty)

proc def*(prj: var PlsProject, alias: string, props: var JsonNode) =
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

proc undef*(prj: var PlsProject, alias: string) =
  prj.load
  prj.targets.delete(alias)
  prj.save
  notice "Target '$1' removed." % alias

proc lookupCommand(prj: PlsProject, command: string, props: seq[string], cmd: var JsonNode): bool =
  if not prj.commands.hasKey command:
    warn "Command '$1' not found" % command
    return
  var cmds = prj.commands[command]
  var score = 0
  # Cycle through command definitions
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
  
proc execute*(prj: var PlsProject, command, alias: string): int =
  prj.load
  if not prj.targets.hasKey alias:
    warn "Package definition '$1' not found within $2. Nothing to do." % [alias, prj.dir]
    return
  notice "$1: $2" % [command, alias]
  let target = prj.targets[alias]
  var keys = newSeq[string](0)
  for key, val in target.pairs:
    keys.add key
  var res: JsonNode
  var cmd: string
  var pwd = prj.dir
  if target.hasKey("dir"):
    pwd = target["dir"].getStr
  if prj.lookupCommand(command, keys, res):
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
    debug "Command '$1' not available for target '$2'" % [command, alias]
  setCurrentDir(prj.dir)

proc executeRec*(prj: var PlsProject, command, alias: string) =
  prj.load
  let pwd = getCurrentDir()
  var dir = alias
  if (execute(prj, command, alias) != 0):
    return
  if prj.targets[alias].hasKey("dir"):
    dir = prj.targets[alias]["dir"].getStr
  var childProj = newPlsProject(pwd/prj.dir/dir)
  if childProj.configured:
    childProj.load()
    setCurrentDir(childProj.dir)
    for key, val in childProj.targets.pairs:
      childProj.executeRec(command, key)
    setCurrentDir(pwd)
