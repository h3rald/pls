import
  sequtils,
  pegs,
  os,
  parseopt,
  strutils,
  tables

import
  plspkg/config

type ConfigParseError = ref object of ValueError
type RuntimeError = ref object of ValueError

let USAGE* = """$1 v$2 - $3
(c) 2021 $4

Usage:
  pls <action> [<thing>, <thing2>, ...]   Executes <action> (on <thing>).
                                          <thing> can contain a start and/or leading * 
                                          to perform simple searches.

Options:
  --help,    -h            Displays this message.
  --actions, -a[:<query>]  Displays all known actions, optionally matching <query>.
                           <query> can contain a start and/or leading * for simple searches.
  --things,  -t[:<query>]  Displays all known things, optionally matching <query>
                           <query> can contain a start and/or leading * for simple searches.
  --inspect, -i            Display information on the specified command.
  --full,    -f            If -a or -t are specified, display all properties for item.
                           If -d is specified, outputs debug information for configuration parsing.
  --version, -v            Displays the version of the application.
""" % [pkgTitle, pkgVersion, pkgDescription, pkgAuthor]

# PEG strings used when parsing the configuration file.
let PEG_PLACEHOLDER* = peg"'{{' {[a-zA-Z0-9._-]+} '}}'"
let PEG_ID* = peg"^[a-z0-9][a-zA-Z0-9._-]+$"
let PEG_DEF* = peg"^[a-z0-9][a-zA-Z0-9._-]+ ('+' [a-z0-9][a-zA-Z0-9._-]+)*$"

# Hash containing all the actions and things saved in the configuration file.
var DATA* = newOrderedTable[string, OrderedTableRef[string, OrderedTableRef[string, string]]]()
DATA["actions"] = newOrderedTable[string, OrderedTableRef[string, string]]()
DATA["things"] = newOrderedTable[string, OrderedTableRef[string, string]]()
DATA["deps"] = newOrderedTable[string, OrderedTableRef[string, string]]()

# Default configuration file, saved if no pls.yml is present on the system.
const DEFAULT_CFG = """
actions:
  # Define actions here
deps:
  # Define dependencies here
things:
  # Define things here
"""

# The path to the pls.yml configuration file.
var CONFIG_FILE: string

if defined(windows):
  CONFIG_FILE = getenv("USERPROFILE") / "pls.yml"
else:
  CONFIG_FILE = getenv("HOME") / "pls.yml"

# Argument/option management
var ARGS = newSeq[string]()
var OPT_DEBUG = false
var OPT_FULL = false
var OPT_SHOW = ""
var OPT_SHOW_QUERY = ""

### Helper Methods ##

proc debug(s: string): void =
  if OPT_DEBUG:
    echo ". $1" % s

proc full_debug(s: string): void =
  if OPT_FULL:
    debug(s)

proc parseProperty(line: string, count: int): tuple[name: string, value: string] =
  let parts = line.split(":")
  if parts.len < 2:
    raise ConfigParseError(msg: "Line $1 - Invalid property." % $count)
  result.name = parts[0].strip
  result.value = parts[1..parts.len-1].join(":").strip

proc parseActionInstance(item: string, count: int = 0): tuple[action: string, things: seq[string]] =
  let parts = item.split(" ")
  result.action = ""
  result.things = newSeq[string]()
  if parts.len == 0:
    raise ConfigParseError(msg: "Line $1 - No action specified.")
  result.action = parts[0].strip
  if parts.len == 1:
    raise ConfigParseError(msg: "Line $1 - No thing specified for action '$2'." % [$count, result.action])
  if not result.action.match(PEG_ID):
    raise ConfigParseError(msg: "Line $1 - Invalid action '$2'." % [$count, result.action])
  for part in parts[1..parts.len-1]:
    let thing = part.strip
    if not thing.match(PEG_ID):
      raise ConfigParseError(msg: "Line $1 - Invalid thing '$2'." % [$count, thing])
    result.things.add(thing)

proc parseConfig(cfg: string): void =
  full_debug("=== Parsing Configuration Start ===")
  var section = ""
  var itemId = ""
  var indent = 0
  var count = 0
  var depCount = 0
  for l in cfg.lines:
    count += 1
    # Third level: items
    if l.startsWith("    "):
      var line = l.strip
      var obj = ""
      if line.len == 0:
        raise ConfigParseError(msg: "Line $1 - Invalid empty line within item." % $count)
      if line[0] == '#':
        # comment
        full_debug("# Comment: $1" % line)
        continue
      if section == "actions":
        obj = "action ID"
      if section == "things":
        obj = "property name"
      if section == "deps":
        obj = "dependency"
      if l.strip(true, false).len < l.strip(false, true).len-4:
        raise ConfigParseError(msg: "Line $1 - Invalid $2 indentation, expected 4 spaces." % [$count, obj])
      if section == "" or indent == 0:
        raise ConfigParseError(msg: "Line $1 - Invalid $2 indentation." % [$count, obj])
      if itemId == "":
        raise ConfigParseError(msg: "Line $1 - Invalid $2 indentation (not within an item)." % [$count, obj])
      if line[0] == '-':
        if section != "deps":
          raise ConfigParseError(msg: "Line $1 - Unexpected array in section '$2'" % [$count, section])
        let item = line[1..line.len-1].strip
        let dep = parseActionInstance(item, count)
        DATA[section][itemId][$depCount] = "$1 $2" % [dep.action, dep.things.join(" ")]
        depCount += 1
        continue
      let p = parseProperty(line, count)
      if (section == "actions" and not p.name.match(PEG_DEF)) or (section == "things" and not p.name.match(PEG_ID)):
        raise ConfigParseError(msg: "Line $1 - Invalid $2 '$3'" % [$count, obj, p.name])
      if DATA[section][itemId].hasKey(p.name):
        raise ConfigParseError(msg: "Line $1 - Duplicate property '$2'" % [$count, p.name])
      DATA[section][itemId][p.name] = p.value
      full_debug("    DATA.$1.$2.$3 = $4" % [section, itemId, p.name, p.value])
      indent = 4
      continue
    # Second level: definitions
    if l.startsWith("  "):
      var line = l.strip
      var obj = ""
      if line.len == 0:
        raise ConfigParseError(msg: "Line $1 - Invalid empty line within section." % $count)
      if line[0] == '#':
        # comment
        full_debug("# Comment: $1" % line)
        continue
      if section == "actions":
        obj = "action"
      elif section == "things":
        obj = "thing"
      elif section == "deps":
        obj = "dependency"
        depCount = 0
      if l.strip(true, false).len < l.strip(false, true).len-2:
        raise ConfigParseError(msg: "Line $1 - Invalid $2 indentation, expected 2 spaces." % [$count, obj])
      if section == "":
        raise ConfigParseError(msg: "Line $1 - Invalid $2 indentation." % [$count, obj])
      if line[line.len-1] != ':' or line == ":":
        raise ConfigParseError(msg: "Line $1 - Invalid $2 identifier." % [$count, obj])
      itemId = line[0..line.len-2]
      if section == "deps":
        let instance = parseActionInstance(itemId, count)
        itemId = "$1 $2" % [instance.action, instance.things.join(" ")]
      elif ["things", "actions"].contains(section):
        if not itemId.match(PEG_ID):
          raise ConfigParseError(msg: "Line $1 - Invalid $2 identifier '$3'." % [$count, obj, itemId])
      if DATA[section].hasKey(itemId):
        raise ConfigParseError(msg: "Line $1 - Duplicate item '$2'" % [$count, itemId])
      # Start new item
      DATA[section][itemId] = newOrderedTable[string, string]()
      full_debug("  DATA.$2.$3" % [obj, section, itemId])
      indent = 2
      continue
    if l == "":
      itemId = ""
      continue
    # First level: sections
    if l == "actions:":
      if section == "actions":
        raise ConfigParseError(msg: "Line $1 - Duplicated 'actions' section." % $count)
      section = "actions"
      full_debug("DATA.$1" % section)
      continue
    if l == "deps:":
      if section == "deps":
        raise ConfigParseError(msg: "Line $1 - Duplicated 'deps' section." % $count)
      section = "deps"
      full_debug("DATA.$1" % section)
      continue
    if l == "things:":
      if section == "things":
        raise ConfigParseError(msg: "Line $1 - Duplicated 'things' section." % $count)
      section = "things"
      full_debug("DATA.$1" % section)
      continue
    if l.strip.startsWith("#"):
      # comment
      full_debug("Comment: $1" % l)
      continue
    else:
      raise ConfigParseError(msg: "Line $1 - Invalid line." % $count)
  full_debug("=== Parsing Configuration End ===")

proc lookupActionDef(action, thing: string, props: seq[string]): string =
  result = ""
  if not DATA["actions"].hasKey(action):
    raise RuntimeError(msg: "Action '$1' not found" % action)
  var defs = DATA["actions"][action]
  var score = 0
  # Cycle through action definitions
  for key, val in defs.pairs:
    var params = key.split("+")
    # Check if all params are available
    var match = params.all do (x: string) -> bool:
      props.contains(x)
    if match and params.len > score:
      score = params.len
      result = val
      debug("$1\n  -> Score: $2 - Definition: $3\n  -> $4" % [thing, $score, key, val])

proc resolvePlaceholder(ident, initialThing: string): string = 
  var id = ident
  var thing = initialThing
  let parts = id.split(".")
  if parts.len > 2:
    raise RuntimeError(msg: "Invalid placeholder '$1'." % id)
  elif parts.len == 2:
    thing = parts[0]
    id = parts[1]
  if not DATA["things"].hasKey(thing):
    raise RuntimeError(msg: "Unable to access thing '$1' in placeholder '$2'." % [thing, ident])
  if not DATA["things"][thing].hasKey(id):
    raise RuntimeError(msg: "Unable to access property '$1' in thing '$2' within placeholder '$3'." % [id, thing, ident])
  result = DATA["things"][thing][id]
  result = result.replace(PEG_PLACEHOLDER) do (m: int, n: int, c: openArray[string]) -> string:
    return resolvePlaceholder(c[0], thing) 
  debug("   Resolving placeholder: $1 -> $2" % ["{{$1.$2}}" % [thing, id], result])

proc execute*(action, thing: string): int {.discardable.} =
  # Check and execute dependencies
  let depDef = "$1 $2" % [action, thing]
  if DATA["deps"].hasKey(depDef):
    for dep in DATA["deps"][depDef].values:
      let instance = parseActionInstance(dep)
      for instanceThing in instance.things:
        execute(instance.action, instanceThing)
  result = 0
  if not DATA["things"].hasKey(thing):
    raise RuntimeError(msg: "Thing '$1' not found. Action '$2' aborted." % [thing, action])
  let props = DATA["things"][thing]
  var keys = newSeq[string](0)
  for key, val in props.pairs:
    keys.add key
  var cmd = lookupActionDef(action, thing, keys)
  if cmd != "":
    cmd = cmd.replace(PEG_PLACEHOLDER) do (m: int, n: int, c: openArray[string]) -> string:
      return resolvePlaceholder(c[0], thing)
    if OPT_DEBUG:
      echo ".    Command to execute: $1" % cmd
    else:
      result = execShellCmd cmd

proc filterItems*(t: string, query=""): seq[string] =
  result = newSeq[string]()
  var endsWith = false
  var startsWith = false
  var contains = false
  if query.endsWith("*"):
    startsWith = true
  if query.startsWith("*"):
    endsWith = true
  if startsWith and endsWith:
    contains = true
  let  q = query.replace("*", "")
  let filter = proc (str: string): bool =
    if contains:
      return str.contains(q)
    elif endsWith:
      return str.endsWith(q)
    elif startsWith:
      return str.startsWith(q)
    elif q.len == 0:
      return true
    else:
      return str == q
  for s, props in DATA[t].pairs:
    if s.filter():
      result.add(s)

proc show*(t: string, query="", full = false): void =
  let keys = filterItems(t, query)
  for s in keys:
    if OPT_FULL:
      echo "\n$1:" % s
      for key, val in DATA[t][s].pairs:
        echo "  $1: $2" % [key, val]
    else:
      echo "- $1" % s

### MAIN ###

for kind, key, val in getopt():
  case kind:
    of cmdArgument:
      ARGS.add key 
    of cmdLongOption, cmdShortOption:
      case key:
        of "help", "h":
          echo USAGE
          quit(0)
        of "version", "v":
          echo pkgVersion
          quit(0)
        of "full", "f":
          OPT_FULL = true
        of "inspect", "i":
          OPT_DEBUG = true
        of "actions", "a":
          OPT_SHOW = "actions"
          OPT_SHOW_QUERY = val
        of "things", "t":
          OPT_SHOW = "things"
          OPT_SHOW_QUERY = val
        else:
          discard
    else:
      discard

if not CONFIG_FILE.fileExists():
  CONFIG_FILE.writeFile(DEFAULT_CFG)

try:
  CONFIG_FILE.parseConfig()
except:
  echo "(!) Unable to parse $1: $2" % [CONFIG_FILE, getCurrentExceptionMsg()]
  quit(1)

if ARGS.len < 1:
  if OPT_SHOW != "":
    show(OPT_SHOW, OPT_SHOW_QUERY, OPT_FULL)
    quit(0)
  else:
    echo USAGE
    quit(0)
elif ARGS.len < 2:
  stderr.writeLine "(!) Too few arguments - no thing(s) specified."
else:
  for arg in ARGS[1..ARGS.len-1]:
    for thing in filterItems("things", arg):
      try:
        execute(ARGS[0], thing) 
      except:
        stderr.writeLine "(!) " & getCurrentExceptionMsg()
