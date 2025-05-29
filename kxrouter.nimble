# Package

version = "0.1.0"
author = "Esteban Castro Borsani (@nitely)"
description = "A karax router with life-time events"
license = "MIT"
skipDirs = @["tests", "examples"]

requires "nim >= 2.2.0"
requires "karax >= 1.5.0"

task test, "Test":
  exec "nim c -r kxrouter.nim"
  exec "nim js -r kxrouter.nim"
