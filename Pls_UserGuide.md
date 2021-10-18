% pls User Guide
% Fabio Cevasco
% -

## Overview

{{p -> _pls_}} is a simple, general-purpose task runner that aims at making common tasks easier to manage and execute. It was inspired by some of the functionalities provided by the [nifty](https://h3rald.com/nifty) package manager, only without the package manager part.

### Main Features

{{p}} can be used to:

- Define a catalog of {{as -> _actions_}} to perform on {{ts -> _things_}}, which will result in {{cs -> _commands_}} to be executed, each with the same simple syntax.
- Define a catalog of {{ts}}, representing virtually anything that can be the object of a {{sc -> _shell command_}} or referred within other {{ts}}.
- Define a set of {{ds -> _dependencies_}} among {{cs}}.
- Manage aliases to commonly-used strings ({{prs -> _properties_}})to use within other sections of the configuration.

### Hello, World!

OK, not exactly the best example to show off some of {{p}} power, but here's minimal example of how everything works. Given the following {{cfg}} file:

```
things:
  home:
    value: /home/h3rald
  bin:
    value: {{home.value}}/bin
  self:
    value: {{home.value}}/dev/pls
    exe: pls
    nimble: true
actions:
  build:
    nimble+value: cd {\{value}} && nimble build -d:release
  publish:
    exe+value: cd {\{value}} && $(cp "{\{exe}}" "{{bin.value}}") &
deps:
  publish self:
    - build self
```

It will be possible to run the following {{c}} to build the {{p}} program and copy it to the [/home/h3rald/bin](class:dir):

> %terminal%
>
> pls publish self

### Key Concepts

{{p}} is based on a few intuitive abstractions that are used for its configurations, as described in the following sections.

#### Shell Command

A {{sc}} is simply a string that can be passed to the underlying system shell to be executed.

#### Command

A {{c -> _command_}} is an instruction given to {{p}} to execute a {{sc}}. The syntax of a {{c}} is always the following:

_action-identifier_ _thing-identifier-1_ [... _thing-identifier-n_]

> %note%
> {{p}} Commands vs. Shell Commands
>
> The word {{c}} identifies a {{p}} command, while a command executed by the underlying operating system shell is referred to as a {{sc}}.

#### Action

An {{a -> _action_}} identifies something that can be done with one or more {{ts}}. Depending on the {{t}} specified, the {{a}} can be configured to execute a different {{sc}}.

#### Thing

A {{t -> _thing_}} identifies something that can be referenced by an {{a}}. There is virtually no restriction on what a {{t}} may represent: it can be a folder, a file, the name of a running process or service, and so on.

#### Property

A {{pr -> _property_}} identifies a trait of a {{t}}. It can be a simple flag or an attribute defining something about a {{t}} that can be used as part of the identifier of an {{ad}} or referenced via a {{pl}} in {{ads}} and other {{pr}} values.

#### Action Definition

An {{ad -> _action definition_}} is defined by an identifier composed by plus-separated _properties_ (e.g.: git+folder+value), and determines what {{sc}} to execute when a {{c}} is run.

#### Dependency

A {{d -> _dependency_}} identifies a {{c}} that must be executed before another {{c}}. If the {{sc}} executed as a dependency fails, no more {{ds}} will be executed and neither will the {{c}} with the {{ds}}.

#### Placeholder

A {{pl -> _placeholder_}} is a reference to a {{pr}} wrapped in double curly brackets that can be used in {{pr}} values or shell commands.

## Getting Started

### Downloading Pre-built Binaries

{# release -> [pls for $1]({{release}}/dowload/{{$version}}/pls_v{{$version}}_$2.zip)#}

The easiest way to get {{p}} is by downloading one of the prebuilt binaries from the [Github Releases Page]({{release -> https://github.com/h3rald/pls/releases}}):

- {#release||Mac OS X (x64)||macosx_x64#}
- {#release||Windows (x64)||windows_x64#}
- {#release||Linux (x64)||linux_x64#}

### Building from Source

You can also build {{p}} from source, if there is no pre-built binary for your platform.

To do so, after installing the {{nim -> [Nim](https://nim-lang.org)}} programming language, you can:

3. Clone the pls [repository](https://github.com/h3rald/pls).
4. Navigate to the [pls](class:dir) repository local folder.
5. Run **nimble build -d:release**

## Using {{p}}

The first time you run {{p}}, a {{cfg -> [pls.yml](class:file)}} configuration file will be created in your <var>$HOME</var> (<var>%USERPROFILE%</var> on Windows) folder. This YAML configuration file will teach {{p}} everything it needs to know to execute {{cs}} and it will be parsed and processed every time {{p}} is executed.

### Configuring {{p}}

The {{cfg}} file contains three sections:

- **actions**, where each {{a}} is defined.
- **things**, where each {{t}} is defined.
- **deps**, where each {{d}} is defined.

Consider the following sample {{cfg}} file:

<a id="cfg-example"></a>

```
things:
  home:
    value: /home/h3rald
  dev:
    value: {{home.value}}/dev
  bin:
    value: {{home.value}}/bin
  h3:
    value: {{home.dev}}/h3
    npm: true
  self:
    value: {{home.dev}}/{\{exe}}
    conf: {{home.value}}/{\{exe}}.yml
    exe: pls
    nimble: true
actions:
  config:
    conf: vim "{\{conf}}"
  edit:
    value: vim "{\{value}}"
  publish:
    exe+value: cd "{\{value}}" && $(cp "{\{exe}}" "{{bin.value}}") &
  build:
    npm+value: cd "{\{value}}" && npm run build
    nimble+value: cd "{\{value}}" && nimble build -d:release
deps:
  publish self:
    - build self
```

This configuration file should give you an idea of how to configure {{p}} to execute your own custom {{cs}}. In this case, it is possible to execute {{cs}} like:

- pls publish self
- pls config self
- pls edit h3
- pls build self h3

...and so on. Let's see how to configure each section more in detail.

#### Configuring Things

Keep in mind that a {{t}} is going to be used as the object or target of your {{a}}, so it typically should represent a file, a folder, a URL, a service name, and so on. Also, it makes sense to define new {{ts}} if they are going to be used often in actions or referenced in other {{ts}}. In relation to the [configuration example](#cfg-example), note how the [home](class:kwd) {{t}} is re-used in [dev](class:kwd) and [bin](class:kwd).

A {{t}} is defined by one or more arbitrary {{prs}}. There are virtually no restrictions on what these {{prs}} can represent, but they must fit on one line and they will always be parsed as strings, no matter what the highlighting of your {{cfg}} says. Typically, it makes sense to define a [value](class:kwd) {{pr}} for the {{pr}} that most characterizes the {{t}}, but this is merely a convention, nothing more.

Any {{pr}} of any {{t}} can be reused via a {{pl}}:

- in {{as}}
- in other {{ts}}

> %sidebar%
> Relative vs. Absolute Placeholders
>
> Properties of {{ts}} can be referenced using a relative {{pl}} specifying just the identified of the referenced {{pr}} (e.g. [{\{value}}](class:kwd)) when used within a {{pr}} of the same {{t}} or (within an {{a}}) when referring to the {{t}} matched by an {{a}}.
>
> Otherwise, you can use absolute {{pls -> _placeholders_}} by prepanding the name of the {{t}} followed by a dot, and then the {{pr}} identifier, e.g. [{\{home.value}}](class:kwd).

#### Configuring Actions

While {{pr}} identifiers are just straightforward names, {{as}} are identified by a combination of plus-separated {{pr}} identifiers. Each {{a}} can have one or more {{ads -> _action definitions_}}, each specifying a different set of {{pr}} identifiers.

When an action is executed on one or more {{ts}}, {{p}} will try to match the appropriate {{ad}} based on the {{prs}} specified in the {{ad}}. Consider the [build](class:kwd) {{a}} in the [configuration example](#cfg-example); it is possible to run the following {{cs}}:

> %terminal%
>
> pls build self

which will result in [cd /home/h3rald/dev/pls && nimble build -d:release](class:cmd) being executed, and:

> %terminal%
>
> pls build h3

which will result in [cd /home/h3rald/dev/h3 && npm run build](class:cmd).

Note how a different {{ad}} is triggered depending on the {{prs}} of the specified {{t}}. If however you try running the following {{c}}:

> %terminal%
>
> pls build home

nothing will happen, as there is no matching {{ad}} for [home](class:kwd), which only contains a [value](class:kwd) {{pr}}.

> %tip%
> Tip
>
> If several {{ads}} match for the specified {{t}}, the one with the most matching {{prs}} will be used.

#### Configuring Dependencies

You can use the [dependencies](class:kwd) section to configure {{ds}} among commands. Essentially, for each {{c}} (comprised of an {{a}} followed by one or more {{t}}), you can specify a list comprised of one or more {{cs}} that will be executed beforehand.

In the [configuration example](#cfg-example), executing:

> %terminal%
>
> pls publish self

will cause the [build self](class:cmd) {{c}} to be executed beforehand.

> %note%
> Command execution and dependencies
>
> If {{ds}} are specified for a {{c}}:
>
> - all its {{ds}} are executed sequentially before the {{c}} is executed
> - if one dependent {{c}} fails, no more {{ds}} will be executed, and the {{c}} will not be executed

### Executing {{p}} Commands

The previous sections already contain a few examples on how to run {{cs}} with {{p}}. Essentially, the syntax is always the same:

[pls _action_ _thing-1_ [..._thing-n_]](class:cmd)

So, for example:

> %terminal%
>
> pls config self

will execute the [config](class:kwd) {{a}} on the [self](class:kwd) {{t}}, and:

> %terminal%
>
> pls build self h3

will execute execute the [build](class:kwd) {{a}} on the [self](class:kwd) {{t}}, and then on the [h3](class:kwd) {{t}}.

There are no built-in {{cs}}, so the first argument specified after {{p}} is interpreted as an {{a}}, and the following ones as things. If no things are specified, an error will be printed.

### Inspecting Commands

If you want to see what {{scs -> _shell commands_}} a particular {{c}} will execute, or how certain {{t}} properties will be matched or used, you can specify the [-i](class:arg) ([\-\-inspect](class:arg)) option to print some diagnostic messages and the resulting shell {{cs}}, without executing them:

> %terminal%
>
> pls build self -i
> . Command: build self
> . Thing: self
> . -> Matching Definition: nimble+value
> . -> Command Definition: cd {\{value}} && nimble build
> . Resolving placeholder: {\{home.value}} -> /home/h3rald
> . Resolving placeholder: {\{dev.value}} -> /home/h3rald/dev
> . Resolving placeholder: {\{self.value}} -> /home/h3rald/dev/pls
> . -> Resolved Command: cd /home/h3rald/dev/pls && nimble build -d:release

> %sidebar%
> Using the [-f](class:arg) ([\-\-full](class:arg)) option
>
> If you specify the [-f](class:arg) together with the [-i](class:arg) option, additional messages will be printed related to the processing of the {{cfg}} file.
> If you specify only the [-f](class:arg) when executing a {{c}}, the resulting {{sc}} will be printed before being executed.

### Displaying Actions, Things, and Dependencies

If you want to quickly display the {{as}}, {{ts}} or {{ds}} that are available without opening the {{cfg}} file, you can use the [-a](class:arg) ([\-\-actions](class:arg)), [-t](class:arg) ([\-\-things](class:arg)), and [-d](class:arg) ([\-\-deps](class:arg)) respectively. Unless the [-f](class:arg) ([\-\-full](class:arg)) option is specified as well, a simply list of {{as}}, {{ts}}, or {{ds}} will be displayed.

If you specify the [-f](class:arg) ([\-\-full](class:arg)) option as well:

- {{ads}} will be displayed for each {{a}}
- {{prs}} will be displayed for each {{t}}
- dependent {{cs}} will be displayed for each {{d}}

## The {{p}} Configuration YAML Schema

The following schema is based on the [YAML Schema](https://asdf-standard.readthedocs.io/en/latest/schemas/yaml_schema.html#yaml-schema-draft-01) extension of [JSON Schema Draft 4](http://json-schema.org/draft-04/json-schema-validation.html) and describes the configuration of {{cfg}} files.

```
%YAML 1.1
---
$schema: https://h3rald.com/pls/yaml-schema/v1.0.0
id: https://h3rald.com/schemas/pls/metadata-1.0.0
tag: tag:h3rald.com:pls/metadata-1.0.0
title: pls Configuration File
type: object
  properties:
    things:
      type: object
      patternProperties:
        ^[a-z0-9][a-zA-Z0-9_-]+$:
          $ref: #/$defs/thing
    actions:
      type: object
      patternProperties:
        ^[a-z0-9][a-zA-Z0-9_-]+$:
          $ref: #/$defs/action
    deps:
      type: object
      patternProperties:
        ^[a-z0-9][a-zA-Z0-9_-]+)( [a-z0-9][a-zA-Z0-9_-]+)+$:
          $ref: #/$defs/dependencies
required: [things, actions]
additionalProperties: false
$defs:
  thing:
    type: object
    patternProperties:
      ^[a-z0-9][a-zA-Z0-9_-]+$: string
  action:
    type: object
    patternProperties:
      ^[a-z0-9][a-zA-Z0-9_-]+(\+[a-z0-9][a-zA-Z0-9_-]+)*$: string
  dependencies:
    type: array
    items:
      type:
        $ref: #/$defs/command
  command:
    type: string
    pattern: |
      ^[a-z0-9][a-zA-Z0-9_-]+( [a-z0-9][a-zA-Z0-9_-]+)+$
```
