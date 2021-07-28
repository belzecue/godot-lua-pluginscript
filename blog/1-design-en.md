# Designing a Godot PluginScript for Lua
`#Godot #Lua #GDNative #PluginScript #languageBindings`

This is the first article in a series about how I'm approaching the development
of a PluginScript for the [Lua](https://www.lua.org/) language in
[Godot](https://godotengine.org/).

Lua is a simple and small, yet powerful and flexible, scripting language.
Although it [isn't fit for every scenario](https://docs.godotengine.org/en/stable/about/faq.html#what-were-the-motivations-behind-creating-gdscript),
it is certainly a great tool for scripting.
Combining that with the power of [LuaJIT](https://luajit.org/),
one of the fastest dynamic language implementations out there, we can also
[call external C functions via the Foreign Function Interface (FFI)](https://luajit.org/ext_ffi.html)!

With the extensible nature of scripting in Godot, all supported languages
can seamlessly communicate with each other and thus we can choose to use the
language that best fits the task in hand for each script.
By the means of [signals](https://docs.godotengine.org/en/stable/getting_started/step_by_step/signals.html)
and the methods [call](https://docs.godotengine.org/en/stable/classes/class_object.html#class-object-method-call),
[get](https://docs.godotengine.org/en/stable/classes/class_object.html#id1)
and [set](https://docs.godotengine.org/en/stable/classes/class_object.html#id4),
any object can communicate with another one, regardless of the
source language.

To make Lua be recognized as one of the supported scripting languages for Godot
objects, we will create a PluginScript, which is one of the uses of
[GDNative](https://docs.godotengine.org/en/stable/getting_started/step_by_step/scripting.html#gdnative-c),
the native plugin C API provided by the engine to extend all sorts of
engine systems, such as the scripting one.
Another plus in this approach is that only the plugin have to be compiled,
so anyone with a standard prebuilt version of Godot can use it! =D

As a side note, since interfacing with C using LuaJIT's FFI is substantially
easier than with the Lua/C API and most people will likely want to use
it for the increased speed, LuaJIT support will be implemented first.
Using [cffi-lua](https://github.com/q66/cffi-lua) and similar modules
may make this first implementation portable to vanilla Lua as well.


## Goals
- Provide support for the Lua language in Godot in a way that does not require
  compiling the engine from scratch
- Be able to seamlessly communicate with any other language supported by Godot,
  like GDScript, Visual Script and C#, in an idiomatic way
- Simple script definition interface that doesn't need `require`ing anything,
  with an empty file being a valid script
- Support for Lua 5.1+ and LuaJIT
- Have a simple build process, where anyone with the cloned source code and
  installed build system + toolchain can build the project


## Non-goals
- Provide calls to core Godot classes' methods via native method bindings
- Support multithreading on the Lua side


## Script example
This is an example of how a Lua script will look like. There are comments regarding
some design decisions, which may change during development.

```lua
-- Optional: set script as tool
tool()

-- Optional: set base class by name, defaults to 'Reference'
extends 'Node'

-- Optional: give your class a name
class_name 'MyClass'

-- Declare signals
signal("something_happened")
signal("something_happened_with_args", "arg1", "arg2")

-- Values defined in _ENV are registered as properties of the script
some_prop = 42

-- Local variables and global ones are **not** registered properties
-- Notice that script environment **is not the global _G table**
local some_lua_local = false
_G.some_lua_global = false

-- calling `property` adds metadata to defined properties,
-- like setter and getter functions
some_prop_with_details = property {
  -- [1] or ["default"] or ["default_value"] = property default value
  5,
  -- [2] or ["type"] = variant type, optional, inferred from default value
  -- All Godot variant type names are defined globally as written in
  -- GDScript, like bool, int, float, String, Array, Vector2, etc...
  -- Notice that Lua <= 5.2 does not differentiate integers from float
  -- numbers, so you may want to always specify `int` where appropriate
  type = int,
  -- ["set"] or ["setter"] = setter function, optional
  set = function(self, value)
    self.some_prop_with_details = value
    -- Indexing self with keys undefined in script will search base
    -- class for methods and properties, respectively
    self:emit_signal("something_happened_with_args", "some_prop_with_details", value)
  end,
  -- ["get"] or ["getter"] = getter function, optional
  get = function(self)
    return self.some_prop_with_details
  end,
  -- ["export"] = export flag, optional, defaults to false
  export = false,
  -- TODO: usage, hint/hint_text, rset_mode
}
-- `export` is an alias for `property` with `export = true`
some_exported_prop = export { "hello world!" }

-- Functions defined in _ENV are public methods
function some_prop_doubled(self)
  return self.some_prop * 2
end

function _init(self)
  -- Singletons are available globally
  local os_name = OS:get_name()
  print("MyClass instance initialized! Running on a " .. os_name .. " system")
end
```


## Implementation design details
PluginScripts have three important concepts: the Language description,
Script Manifest and Instances.
Let's check out what each layer is and how they will behave from a high
level perspective:


### Language description
The language description tells Godot how to initialize and finalize our
language runtime, as well as how to load script manifests from source
files.

When initializing the runtime, a new
[lua_State](https://www.lua.org/manual/5.4/manual.html#lua_State)
will be created and Godot functionality setup in it.
The Lua VM will use engine memory management routines, so that memory is
tracked by the performance monitors in debug builds of the
game/application.
All scripts will share this same state.

There will be a global table named `GD` with some Godot specific
functions, such as [load](https://docs.godotengine.org/en/stable/classes/class_%40gdscript.html#class-gdscript-method-load),
[print](https://docs.godotengine.org/en/stable/classes/class_%40gdscript.html#class-gdscript-method-print),
[push_error](https://docs.godotengine.org/en/stable/classes/class_%40gdscript.html#class-gdscript-method-push-error),
[push_warning](https://docs.godotengine.org/en/stable/classes/class_%40gdscript.html#class-gdscript-method-push-warning)
and [yield](https://docs.godotengine.org/en/stable/classes/class_%40gdscript.html#class-gdscript-method-yield).
Lua's global `print` function will be set to `GD.print` and
[Lua 5.4 warning function](https://www.lua.org/manual/5.4/manual.html#lua_WarnFunction)
will behave like a `push_warning` call.

The absolute path for [res://](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html#resource-path)
will be added to Lua's [package.path](https://www.lua.org/manual/5.4/manual.html#pdf-package.path)
and [package.cpath](https://www.lua.org/manual/5.4/manual.html#pdf-package.cpath).
Functions that expect file names, like [loadfile](https://www.lua.org/manual/5.4/manual.html#pdf-loadfile)
and [io.open](https://www.lua.org/manual/5.4/manual.html#pdf-io.open),
will be patched to accept paths like `res://*` and `user://*`.

Language finalization will simply [lua_close](https://www.lua.org/manual/5.4/manual.html#lua_close) the state.


### Script manifest
Script manifests hold metadata about classes, such as defined signals,
properties and methods, whether class is tool and its base class name.

In Lua, this information will be stored in Lua tables indexed by the
scripts' path.

When initializing a script, its source code will be loaded in the VM,
have its environment patched with a newly created table, then run.
Using a new environment for each manifest makes scripts look more self
contained and similar to GDScript.

Functions declared in the manifest are registered as public class
methods and other variables are declared as properties.
Notice that local (`local var = value`) values are not registered in
script manifests.  The same is true for values stored in the global
table (`_G.var = value`).

Script finalization will destroy the manifest table.


### Instances
When a script is attached to an object, the engine will call our
PluginScript to initialize the instance data and when the object gets
destroyed or gets another script attached, we get to finalize the
data.

Each instance will be a table that `__index`es the script, so that
default values and methods can be found, falling back to searching
for methods and properties in the base class.
This table will be passed to methods as their first argument, in a
fashion like `instance:method(...)`.
This table will be indexed by the instance owner object's pointer.

Instance finalization will destroy the data table.


## Wrapping up
With this high level design in place, we can now start implementing the
project! I have already created a Git repository hosted at GitHub:
[gilzoide/godot-lua-pluginscript](https://github.com/gilzoide/godot-lua-pluginscript).

In the next post I'll discuss how to build the necessary infrastructure
for the PluginScript to work, with stubs to the callbacks and a build
system that correctly manages all dependencies.

See you there ;D