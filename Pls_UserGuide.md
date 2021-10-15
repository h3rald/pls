% pls User Guide
% Fabio Cevasco
% -

## Overview

{{p -> _pls_}} is a simple, general-purpose task runner that aims at making common tasks easier to manage and execute. It was inspired by some of the functionalities provided by the [nifty](https://h3rald.com/nifty) package manager, only without the package manager part.

### Main Features

{{p}} can be used to:

- Define a catalog of _actions_ to perform on _things_, which will result in _commands_ to be executed, each with the same simple syntax.
- Define a catalog of _things_, representing virtually anything that can be the object of a shell command or referred within other _things_.
- Define a set of dependencies among _commands_.
- Manage aliases to commonly-used strings to use within other sections of the configuration.

### Key Concepts

{{p}} is based on a few intuitive abstractions that are used for its configurations, as described in the following sections.

#### Command

A {{c -> _command_}} is an instruction given to {{p}} to execute a shell command. The syntax of a {{c}} is always the following:

_action-identifier_ _thing-identifier-1_ [... _thing-identifier-n_]

> %note%
> {{p}} Commands vs. Shell Commands
>
> The word {{c}} identifies a {{p}} command, while a command executed by the underlying operating system shell is referred to as a _shell command_.

#### Action

An {{a -> _action_}} identifies something that can be done with one or more things. Depending on the thing specified, the {{a}} can be configured to execute a different shell command.

#### Thing

A {{t -> _thing_}} identifies something that can be referenced by an {{a}}. There is virtually no restriction on what a {{t}} may represent: it can be a folder, a file, the name of a running process or service, and so on.

#### Property

A {{pr -> _property_}} identifies a trait of a {{t}}. It can be a simple flag or an attribute defining something about a {{t}} that can be used as part of the identifier of an {{ad}} or referenced via a {{pl}} in shell commands and other {{pr}} values.

#### Action Definition

An {{ad -> _action definition_}} is defined by an identifier composed by plus-separated _properties_ (e.g.: git+folder+value), and determines what shell command to execute when a {{c}} is run.

#### Dependency

A {{d -> _dependency_}} identifies a {{c}} that must be executed before another {{c}}. If the shell command specified as a dependency fails, no more _dependencies_ will be executed and neither will the {{c}} with the dependencies.

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

The first time you run the {{p}} command, a {{cfg -> [pls.yml](class:file)}} configuration file will be created in your <var>$HOME</var> (<var>%USERPROFILE%</var> on Windows) folder. This YAML configuration file will teach {{p}} everything it needs to know to execute commands and it will be parsed and processed every time {{p}} is executed, before running any {{c}}.

### Configuring {{p}}

The {{cfg}} file contains three sections:

- **actions**, where each {{a}} is defined.
- **things**, where each {{t}} is defined.
- **deps**, where each {{d}} is defined.

Consider the following sample {{cfg}} file:

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
    value: {{home.dev}}/pls
    conf: {{home.value}}/pls.yml
    exe: pls
    nimble: true
actions:
  config:
    conf: vim "{\{conf}}"
  edit:
    value: vim "{\{value}}"
  publish:
    exe+value: $(cp "{\{exe}}" "{{bin.value}}") &
  build:
    npm+value: cd "{\{value}}" && npm run build
    nimble+value: cd "{\{value}}" && nimble build -d:release
deps:
  publish self:
    - build self
```

This configuration file should give you an idea of how to configure {{p}} to execute your own custom commands. In this case, it is possible to execute commands like:

- pls publish self
- pls config self
- pls edit h3
- pls build self h3

...and so on. Let's see how to configure each section more in detail.

#### Configuring Things

#### Configuring Actions

#### Configuring Dependencies

### Executing {{p}} Commands

### Inspecting Commands

### Displaying Actions, Things, and Dependencies

## The {{p}} Configuration YAML Schema

The following schema is based on the [YAML Schema](https://asdf-standard.readthedocs.io/en/latest/schemas/yaml_schema.html#yaml-schema-draft-01) extension of [JSON Schema Draft 4](http://json-schema.org/draft-04/json-schema-validation.html) and describes the configuration of {{cfg}} files.

```
%YAML 1.1
---
$schema: "https://h3rald.com/pls/yaml-schema/v1.0.0"
id: "https://h3rald.com/schemas/pls/metadata-1.0.0"
tag: "tag:h3rald.com:pls/metadata-1.0.0"
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
"$defs":
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
