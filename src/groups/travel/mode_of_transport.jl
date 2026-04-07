# ---------------------------------------------------------------------------
# ModeOfTransport — registry of transport modes
# ---------------------------------------------------------------------------

const _MODE_REGISTRY = Dict{String, Any}()

struct ModeOfTransport
    description::String
    is_public::Bool
end

"""
    register_mode!(description, is_public) -> ModeOfTransport

Register a new transport mode in the global registry.
"""
function register_mode!(description::String, is_public::Bool)
    mot = ModeOfTransport(description, is_public)
    _MODE_REGISTRY[description] = mot
    return mot
end

"""
    get_mode_of_transport(description) -> ModeOfTransport

Retrieve a registered transport mode by name.
"""
function get_mode_of_transport(description::String)
    if haskey(_MODE_REGISTRY, description)
        return _MODE_REGISTRY[description]
    end
    error("Unknown transport mode: $description")
end

is_private(m::ModeOfTransport) = !m.is_public

# ---------------------------------------------------------------------------
# ModeOfTransportGenerator — weighted sampling of transport modes
# ---------------------------------------------------------------------------

struct ModeOfTransportGenerator
    modes::Vector{ModeOfTransport}
    probabilities::Vector{Float64}
end

"""
    generate_mode(gen::ModeOfTransportGenerator) -> ModeOfTransport

Sample a transport mode from the weighted distribution.
"""
function generate_mode(gen::ModeOfTransportGenerator)
    return sample(gen.modes, Weights(gen.probabilities))
end
