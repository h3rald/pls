import 
  os,
  parseopt,
  strutils,
  sequtils,
  pegs,
  tables

import
  plspkg/config

type ConfigParseError = ref object of ValueError
type RuntimeError = ref object of ValueError

let USAGE* = """  $1 v$2 - $3
  (c) 2021 $4

  Usage:
    pls <action> [<thing>]           Executes <action> (on <thing>).

  Options:
    --help,    -h           Displays this message.
    --actions, -a           Display all known actions.
    --things,  -t           Display all known things.
    --version, -v           Displays the version of the application.
""" % [pkgTitle, pkgVersion, pkgDescription, pkgAuthor]

let placeholder = peg"'{{' {[^}]+} '}}'"

var DATA = newTable[string, TableRef[string, TableRef[string, string]]]()
DATA["actions"] = newTable[string, TableRef[string, string]]()
DATA["things"] = newTable[string, TableRef[string, string]]()

const defaultConfig = """
actions:
  # Define actions here
things:
  # Define things here
"""

var CONFIG: string

if defined(windows):
  CONFIG = getenv("USERPROFILE") / "pls.yml"
else:
  CONFIG = getenv("HOME") / "pls.yml"

# Helper Methods

proc parseProperty(line: string, index: int): tuple[name: string, value: string] =
  let parts = line.split(":")
  if parts.len < 2:
    raise ConfigParseError(msg: "Line $1 - Invalid property.")
  result.name = parts[0].strip
  result.value = parts[1..parts.len-1].join(":").strip

proc load(cfg: string): void =
  var actions = false
  var things = false
  var section = ""
  var itemId = ""
  var indent = 0
  var count = 0
  for l in cfg.lines:
    count += 1
    if l.startsWith("    "):
      var line = l.strip
      if line.len == 0:
        raise ConfigParseError(msg: "Line $1 - Invalid empty line within item." % $count)
      if line[0] == '#':
        # comment
        continue
      if not (things or actions) or indent == 0:
        raise ConfigParseError(msg: "Line $1 - Invalid property indentation." % $count)
      if itemId == "":
        raise ConfigParseError(msg: "Line $1 - Invalid property indentation (not within an item)." % $count)
      let p = parseProperty(line, count)
      DATA[section][itemId][p.name] = p.value
      indent = 4
      continue
    if l.startsWith("  "):
      var line = l.strip
      if line.len == 0:
        raise ConfigParseError(msg: "Line $1 - Invalid empty line within section." % $count)
      if line[0] == '#':
        # comment
        continue
      if not (things or actions):
        raise ConfigParseError(msg: "Line $1 - Invalid item indentation." % $count)
      if line[line.len-1] != ':' or line == ":":
        raise ConfigParseError(msg: "Line $1 - Invalid item identifier." % $count)
      itemId = line[0..line.len-2]
      # Start new item
      DATA[section][itemId] = newTable[string, string]()
      indent = 2
      continue
    if l == "":
      itemId = ""
      continue
    if l == "actions:":
      if actions:
        raise ConfigParseError(msg: "Line $1 - Duplicated 'actions' section." % $count)
      actions = true
      section = "actions"
      continue
    if l == "things:":
      if things:
        raise ConfigParseError(msg: "Line $1 - Duplicated 'things' section." % $count)
      things = true
      section = "things"
      continue
    if l.strip.startsWith("#"):
      # comment
      continue
    else:
      raise ConfigParseError(msg: "Line $1 - Invalid line." % $count)

proc lookupTask(action: string, props: seq[string]): string =
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

proc execute*(action, thing: string): int {.discardable.} =
  if not DATA["things"].hasKey(thing):
    raise RuntimeError(msg: "Thing '$1' not found. Nothing to do." % thing)
  let props = DATA["things"][thing]
  var keys = newSeq[string](0)
  for key, val in props.pairs:
    keys.add key
  var cmd = lookupTask(action, keys)
  if cmd != "":
    cmd = cmd.replace(placeholder) do (m: int, n: int, c: openArray[string]) -> string:
      return props[c[0]]
    echo "Executing: $1" % cmd
    result = execShellCmd cmd
  else:
    echo "Action '$1' not available for thing '$2'" % [action, thing]

### MAIN ###

if not CONFIG.fileExists:
  CONFIG.writeFile(defaultConfig)

try:
  CONFIG.load()
except:
  echo "(!) Unable to parse pls.yml file: $1" % getCurrentExceptionMsg()

var args = newSeq[string](0)

for kind, key, val in getopt():
  case kind:
    of cmdArgument:
      args.add key 
    of cmdLongOption, cmdShortOption:
      case key:
        of "help", "h":
          echo USAGE
          quit(0)
        of "version", "v":
          echo pkgVersion
          quit(0)
        of "actions", "a":
          for action, props in DATA["actions"].pairs:
            echo "\n$1:" % action
            for key, val in props.pairs:
              echo "  $1: $2" % [key, val]
          quit(0)
        of "things", "t":
          for thing, props in DATA["things"].pairs:
            echo "\n$1:" % thing
            for key, val in props.pairs:
              echo "  $1: $2" % [key, val]
          quit(0)
        else:
          discard
    else:
      discard

if args.len == 0:
  echo USAGE 
  quit(0)
elif args.len < 1:
  echo USAGE
  quit(1)
elif args.len < 2:
  if DATA["things"].len == 0:
    echo "(!) No targets defined - nothing to do."
    quit(0)
  for key in DATA["things"].keys:
    execute(args[0], key) 
else:
  try:
    execute(args[0], args[1]) 
  except:
    echo "(!) " & getCurrentExceptionMsg()
