function string:starts_with(prefix)
	return prefix == "" or self:sub(1, #prefix) == prefix
end

function string:ends_with(suffix)
	return suffix == "" or self:sub(-#suffix) == suffix
end
