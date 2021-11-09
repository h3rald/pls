[![Nimble](https://raw.githubusercontent.com/yglukhov/nimble-tag/master/nimble.png)](https://nimble.directory/pkg/pls)

[![Release](https://img.shields.io/github/release/h3rald/pls.svg)]()
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://raw.githubusercontent.com/h3rald/pls/master/LICENSE)
![Build Status](https://github.com/h3rald/pls/actions/workflows/ci.yml/badge.svg)

# pls &mdash; A polite but determined task runner

_pls_ is a simple, general-purpose task runner that aims at making common tasks easier to manage and execute. It was inspired by some of the functionalities provided by the [nifty](https://h3rald.com/nifty) package manager, only without the package manager part.

## Main Features

_pls_ can be used to:

- Define a catalog of _actions_ to perform on _things_, which will result in _commands_ to be executed, each with the same simple syntax.
- Define a catalog of _things_, representing virtually anything that can be the object of a _shell command_ or referred within other _things_.
- Define a set of _dependencies_ among _commands_, in the form of _commands_.
- Manage aliases to commonly-used strings (_properties_) to use within other sections of the configuration.

## Hello, World!

Here's minimal but quite comprehensive example of how everything works with _pls_. Given the following <var>pls.yml</var> file (placed in <var>$HOME</var> or in <var>%USERPROFILE%</var> on Windows):

```
things:
  home:
    value: /home/h3rald
  bin:
    value: {{home.value}}/bin
  self:
    value: {{home.value}}/dev/pls
    exe: pls
    config: {{home.value}}/pls.yml
    nimble: true
actions:
  config:
    config: vim {\{config}}
  build:
    nimble+value: cd {\{value}} && nimble build -d:release
  publish:
    exe+value: cd {\{value}} && $(cp "{\{exe}}" "{{bin.value}}") &
deps:
  publish self:
    - build self
```

It will be possible to run the following _command_ to build the _pls_ program itself and copy it to the [/home/h3rald/bin](class:dir):

```
pls publish self
```

Similarly, to edit the <var>pls.yml</var> file using Vim, it will be sufficient to run:

```
pls config self
```

## More Information

For more information on how to configure and use _pls_, see the [Pls User Guide](https://h3rald.com/pls/Pls_UserGuide.htm).
