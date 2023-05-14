# ffi-threads
A thread library concept without using C module. Made for Windows x64, but easy to make for any other system or architecture.

# usage
```lua
local thread = require "thread"

-- create a new lua state and compile code for it.
local state = thread.new("print('Hello world')")

-- make it run on a different thread. you can do this many times with the same lua state.
local th = thread.run(state)
th:join()
```
