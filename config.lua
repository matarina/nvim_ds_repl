local defaults = {
    vsplit = true,
    spawn_command = {
        python = "ipython",
        r = "radian",
    }
}

local function set(_, key, value)
    defaults[key] = value
end

local function get(_, key)
    return defaults[key]
end

return {
    defaults = defaults,
    get = get,
    set = set
}
