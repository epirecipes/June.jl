"""
    Activities

Mutable container for the subgroups a person belongs to in each activity
slot.  All fields start as `nothing` and are assigned to `Subgroup`
instances once groups are built.

Mirrors the Python `Activities(dataobject)`.
"""
mutable struct Activities
    residence::Any
    primary_activity::Any
    medical_facility::Any
    commute::Any
    rail_travel::Any
    leisure::Any
end

Activities() = Activities(nothing, nothing, nothing, nothing, nothing, nothing)

"""Return the activity field names as a tuple of `Symbol`s."""
activity_fields() = (:residence, :primary_activity, :medical_facility,
                      :commute, :rail_travel, :leisure)

function Base.show(io::IO, a::Activities)
    active = [f for f in activity_fields() if getfield(a, f) !== nothing]
    print(io, "Activities(", join(active, ", "), ")")
end
