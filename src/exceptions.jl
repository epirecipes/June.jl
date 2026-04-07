"""Exception types for June.jl"""

struct GroupException <: Exception
    msg::String
end

struct PolicyError <: Exception
    msg::String
end

struct HospitalError <: Exception
    msg::String
end

struct SimulatorError <: Exception
    msg::String
end

struct InteractionError <: Exception
    msg::String
end

struct DemographyError <: Exception
    msg::String
end

Base.showerror(io::IO, e::GroupException) = print(io, "GroupException: ", e.msg)
Base.showerror(io::IO, e::PolicyError) = print(io, "PolicyError: ", e.msg)
Base.showerror(io::IO, e::HospitalError) = print(io, "HospitalError: ", e.msg)
Base.showerror(io::IO, e::SimulatorError) = print(io, "SimulatorError: ", e.msg)
Base.showerror(io::IO, e::InteractionError) = print(io, "InteractionError: ", e.msg)
Base.showerror(io::IO, e::DemographyError) = print(io, "DemographyError: ", e.msg)
