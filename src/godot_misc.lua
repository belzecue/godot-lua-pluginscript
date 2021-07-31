local node_path_methods = {
	tovariant = ffi.C.hgdn_new_node_path_variant,
	varianttype = GD.TYPE_NODE_PATH,
}
NodePath = ffi.metatype('godot_node_path', {
	__new = function(mt, text_or_nodepath)
		local self = ffi.new(mt)
		if ffi.istype(mt, text_or_nodepath) then
			api.godot_node_path_new_copy(self, text_or_nodepath)
		elseif ffi.istype(String, text_or_nodepath) then
			api.godot_node_path_new(self, text_or_nodepath)
		else
			api.godot_node_path_new(self, String(text_or_nodepath))
		end
		return self
	end,
	__gc = api.godot_node_path_destroy,
	__tostring = function(self)
		return tostring(api.godot_node_path_as_string(self))
	end,
	__index = node_path_methods,
	__concat = concat_gdvalues,
})

RID = ffi.metatype('godot_rid', {
	__new = function(mt, resource)
		local self = ffi.new(mt)
		if resource then
			api.godot_rid_new_with_resource(self, resource)
		else
			api.godot_rid_new(self)
		end
		return self
	end,
	__tostring = GD.tostring,
	__index = {
		tovariant = ffi.C.hgdn_new_rid_variant,
		varianttype = GD.TYPE_RID,
		get_id = api.godot_rid_get_id,
	},
	__concat = concat_gdvalues,
	__eq = api.godot_rid_operator_equal,
	__lt = api.godot_rid_operator_less,
})

ffi.cdef[[typedef struct lps_method_bind { godot_string method; } lps_method_bind]]
local MethodBind = ffi.metatype('lps_method_bind', {
	__new = function(mt, method)
		return ffi.new(mt, String(method))
	end,
	__call = function(self, var, ...)
		return var:call(self.method, ...)
	end,
})

local object_methods = {
	tovariant = ffi.C.hgdn_new_object_variant,
	varianttype = GD.TYPE_OBJECT,
	pcall = function(self, ...)
		return Variant(self):pcall(...)
	end,
	call = function(self, ...)
		return Variant(self):call(...)
	end,
}
Object = ffi.metatype('godot_object', {
	__tostring = GD.tostring,
	__index = function(self, key)
		local method = object_methods[key]
		if method then
			return method
		end
		local var = object_methods.tovariant(self)
		if self:call('has_method', key) then
			return MethodBind(key)
		else
			self:call('get', key)
		end
	end,
	__concat = concat_gdvalues,
})
