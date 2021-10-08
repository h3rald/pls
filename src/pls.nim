
from sequtils import all
from pegs     import peg, match, replace
from os       import getenv, fileExists, execShellCmd, `/`
from parseopt import getopt, cmdLongOption, cmdShortOption, cmdArgument
from strutils import `%`, split, strip, join, startsWith, endsWith, replace, contains
from tables   import newTable, TableRef, `[]=`, `[]`, hasKey, pairs, len, keys

import
  plspkg/config

type ConfigParseError = ref object of ValueError
type RuntimeError = ref object of ValueError

let USAGE* = """$1 v$2 - $3
(c) 2021 $4

Usage:
  pls <action> [<thing>]   Executes <action> (on <thing>).

Options:
  --help,    -h            Displays this message.
  --actions, -a[:<query>]  Displays all known actions, optionally matching <query>.
                           <query> can contain start and/or leading * for simple searches.
  --things,  -t[:<query>]  Displays all known things, optionally matching <query>
                           <query> can contain start and/or leading * for simple searches.
  --full,    -f            If -a or -t are specified, display all properties for each
                           action or thing.
  --version, -v            Displays the version of the application.
""" % [pkgTitle, pkgVersion, pkgDescription, pkgAuthor]

# PEG strings used when parsing the configuration file.
let PEG_PLACEHOLDER* = peg"'{{' {[a-zA-Z0-9._-]+} '}}'"
let PEG_ID* = peg"^[a-z0-9][a-zA-Z0-9._-]+$"
let PEG_DEF* = peg"^[a-z0-9][a-zA-Z0-9._-]+ ('+' [a-z0-9][a-zA-Z0-9._-]+)*$"

# Hash containing all the actions and things saved in the configuration file.
var DATA* = newTable[string, TableRef[string, TableRef[string, string]]]()
DATA["actions"] = newTable[string, TableRef[string, string]]()
DATA["things"] = newTable[string, TableRef[string, string]]()

# Default configuration file, saved if no pls.yml is present on the system.
const DEFAULT_CFG = """
actions:
  # Define actions here
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
var OPT_FULL = false
var OPT_SHOW = ""
var OPT_SHOW_QUERY = ""

### Helper Methods ##

proc parseProperty(line: string, index: int): tuple[name: string, value: string] =
  let parts = line.split(":")
  if parts.len < 2:
    raise ConfigParseError(msg: "Line $1 - Invalid property." % $index)
  result.name = parts[0].strip
  result.value = parts[1..parts.len-1].join(":").strip

proc parseConfig(cfg: string): void =
  var section = ""
  var itemId = ""
  var indent = 0
  var count = 0
  for l in cfg.lines:
    count += 1
    if l.startsWith("    "):
      var line = l.strip
      var obj = ""
      if line.len == 0:
        raise ConfigParseError(msg: "Line $1 - Invalid empty line within item." % $count)
      if line[0] == '#':
        # comment
        continue
      if section == "actions":
        obj = "action ID"
      if section == "things":
        obj = "property name"
      if l.strip(true, false).len < l.strip(false, true).len-4:
        raise ConfigParseError(msg: "Line $1 - Invalid $2 indentation, expected 4 spaces." % [$count, obj])
      if section == "" or indent == 0:
        raise ConfigParseError(msg: "Line $1 - Invalid $2 indentation." % [$count, obj])
      if itemId == "":
        raise ConfigParseError(msg: "Line $1 - Invalid $2 indentation (not within an item)." % [$count, obj])
      let p = parseProperty(line, count)
      if (section == "actions" and not p.name.match(PEG_DEF)) or (section == "things" and not p.name.match(PEG_ID)):
        raise ConfigParseError(msg: "Line $1 - Invalid $2 '$3'" % [$count, obj, p.name])
      DATA[section][itemId][p.name] = p.value
      indent = 4
      continue
    if l.startsWith("  "):
      var line = l.strip
      var obj = ""
      if line.len == 0:
        raise ConfigParseError(msg: "Line $1 - Invalid empty line within section." % $count)
      if line[0] == '#':
        # comment
        continue
      if section == "actions":
        obj = "action"
      if section == "things":
        obj = "thing"
      if l.strip(true, false).len < l.strip(false, true).len-2:
        raise ConfigParseError(msg: "Line $1 - Invalid $2 indentationn, expected 2 spaces." % [$count, obj])
      if section == "":
        raise ConfigParseError(msg: "Line $1 - Invalid $2 indentation." % [$count, obj])
      if line[line.len-1] != ':' or line == ":":
        raise ConfigParseError(msg: "Line $1 - Invalid $2 identifier." % [$count, obj])
      itemId = line[0..line.len-2]
      if not itemId.match(PEG_ID):
        raise ConfigParseError(msg: "Line $1 - Invalid $2 identifier '$3'." % [$count, obj, itemId])
      # Start new item
      DATA[section][itemId] = newTable[string, string]()
      indent = 2
      continue
    if l == "":
      itemId = ""
      continue
    if l == "actions:":
      if section == "actions":
        raise ConfigParseError(msg: "Line $1 - Duplicated 'actions' section." % $count)
      section = "actions"
      continue
    if l == "things:":
      if section == "things":
        raise ConfigParseError(msg: "Line $1 - Duplicated 'things' section." % $count)
      section = "things"
      continue
    if l.strip.startsWith("#"):
      # comment
      continue
    else:
      raise ConfigParseError(msg: "Line $1 - Invalid line." % $count)

proc lookupActionDef(action: string, props: seq[string]): string =
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

proc execute*(action, thing: string): int {.discardable.} =
  if not DATA["things"].hasKey(thing):
    raise RuntimeError(msg: "Thing '$1' not found. Nothing to do." % thing)
  let props = DATA["things"][thing]
  var keys = newSeq[string](0)
  for key, val in props.pairs:
    keys.add key
  var cmd = lookupActionDef(action, keys)
  if cmd != "":
    cmd = cmd.replace(PEG_PLACEHOLDER) do (m: int, n: int, c: openArray[string]) -> string:
      return resolvePlaceholder(c[0], thing)
    result = execShellCmd cmd

proc show*(t, query="", full = false): void =
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
    if not s.filter():
      continue
    if OPT_FULL:
      echo "\n$1:" % s
      for key, val in props.pairs:
        echo "  $1: $2" % [key, val]
    else:
      echo "- $1" % s

### MAIN ###

if not CONFIG_FILE.fileExists():
  CONFIG_FILE.writeFile(DEFAULT_CFG)

try:
  CONFIG_FILE.parseConfig()
except:
  echo "(!) Unable to parse pls.yml file: $1" % getCurrentExceptionMsg()
  quit(1)

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

if ARGS.len < 1:
  if OPT_SHOW != "":
    show(OPT_SHOW, OPT_SHOW_QUERY, OPT_FULL)
    quit(0)
  else:
    echo USAGE
    quit(0)
elif ARGS.len < 2:
  if DATA["things"].len == 0:
    echo "(!) No targets defined - nothing to do."
    quit(0)
  for key in DATA["things"].keys:
    execute(ARGS[0], key) 
else:
  try:
    execute(ARGS[0], ARGS[1]) 
  except:
    echo "(!) " & getCurrentExceptionMsg()
