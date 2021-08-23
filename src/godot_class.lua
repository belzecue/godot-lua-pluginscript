-- @file godot_class.lua  Method Binds and generic Godot Class definitions
-- This file is part of Godot Lua PluginScript: https://github.com/gilzoide/godot-lua-pluginscript
--
-- Copyright (C) 2021 Gil Barbosa Reis.
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the “Software”), to
-- deal in the Software without restriction, including without limitation the
-- rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
-- sell copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
-- IN THE SOFTWARE.
local ClassDB = api.godot_global_get_singleton("ClassDB")

local Variant_p_array = ffi_typeof('godot_variant *[?]')
local const_Variant_pp = ffi_typeof('const godot_variant **')
local VariantCallError = ffi_typeof('godot_variant_call_error')

local _Object  -- forward local declaration
local Object_call = api.godot_method_bind_get_method('Object', 'call')
local Object_get = api.godot_method_bind_get_method('Object', 'get')
local Object_has_method = api.godot_method_bind_get_method('Object', 'has_method')
local Object_is_class = api.godot_method_bind_get_method('Object', 'is_class')

local function Object_gc(obj)
	if Object_call(obj, 'unreference') then
		api.godot_object_destroy(obj)
	end
end

local MethodBind = ffi.metatype('godot_method_bind', {
	__call = function(self, obj, ...)
		local argc = select('#', ...)
		local argv = ffi_new(Variant_p_array, argc)
		for i = 1, argc do
			local arg = select(i, ...)
			argv[i - 1] = Variant(arg)
		end
		local r_error = ffi_new(VariantCallError)
		local value = ffi_gc(api.godot_method_bind_call(self, _Object(obj), ffi_cast(const_Variant_pp, argv), argc, r_error), api.godot_variant_destroy)
		if r_error.error == GD.CALL_OK then
			return value:unbox()
		else
			return nil
		end
	end,
})

local MethodBindByName = {
	new = function(self, method)
		return setmetatable({ method = method }, self)
	end,
	__call = function(self, obj, ...)
		return obj:call(self.method, ...)
	end,
}

local class_methods = {
	new = function(self, ...)
		local obj = self.constructor()
		if Object_call(obj, 'init_ref') then
			ffi_gc(obj, Object_gc)
		end
		Object_call(obj, '_init', ...)
		return obj
	end,
}
local Class = {
	new = function(self, class_name)
		return setmetatable({
			class_name = class_name,
			constructor = api.godot_get_class_constructor(class_name),
		}, self)
	end,
	__index = function(self, key)
		local method = class_methods[key]
		if method then return method end
		local varkey = Variant(key)
		if ClassDB:class_has_integer_constant(self.class_name, varkey) then
			local constant = ClassDB:class_get_integer_constant(self.class_name, varkey)
			rawset(self, key, constant)
			return constant
		end
	end,
}

local instance_methods = {
	fillvariant = function(var, self)
		api.godot_variant_new_object(var, rawget(self, '__owner'))
	end,
	pcall = function(self, ...)
		return rawget(self, '__owner'):pcall(...)
	end,
	call = function(self, ...)
		return rawget(self, '__owner'):call(...)
	end,
}
local Instance = {
	__index = function(self, key)
		local script_value = instance_methods[key] or rawget(self, '__script')[key]
		if script_value ~= nil then return script_value end
		return rawget(self, '__owner')[key]
	end,
}
