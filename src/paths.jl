"""
    Path resolution for June.jl

Mirrors Python JUNE's paths.py — searches CWD, then package directory for
`data/` and `configs/` folders.
"""

const PROJECT_DIR = @__DIR__
const PACKAGE_DIR = dirname(PROJECT_DIR)

function find_default(name::String; look_in_package::Bool=true)::String
    candidates = [pwd(), dirname(pwd())]
    if look_in_package
        push!(candidates, PROJECT_DIR)
        push!(candidates, PACKAGE_DIR)
    end
    for dir in candidates
        path = joinpath(dir, name)
        if isdir(path) || isfile(path)
            return path
        end
    end
    error("Could not find a default path for '$name'")
end

function resolve_path(name::String; look_in_package::Bool=true)::String
    return find_default(name; look_in_package)
end

# Lazily resolved — these will be populated when data is available
function data_path()
    try
        return resolve_path("data"; look_in_package=true)
    catch
        @warn "Data directory not found. Place the required JUNE input files under a local data/ directory or pass explicit file paths."
        return ""
    end
end

function configs_path()
    return resolve_path("configs"; look_in_package=true)
end

function default_data_path(subpath::String="")
    dp = data_path()
    isempty(dp) && return ""
    return isempty(subpath) ? dp : joinpath(dp, subpath)
end

function default_config_path(subpath::String="")
    cp = configs_path()
    return isempty(subpath) ? cp : joinpath(cp, subpath)
end
