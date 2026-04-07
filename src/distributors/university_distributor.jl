# ---------------------------------------------------------------------------
# UniversityDistributor — assign students to universities
# ---------------------------------------------------------------------------

struct UniversityDistributor
    universities::Any
end

"""
    distribute_students_to_universities!(ud::UniversityDistributor; areas, people)

Assign 19–24 year-olds to nearby universities.
"""
function distribute_students_to_universities!(ud::UniversityDistributor;
                                              areas=nothing, people=nothing)
    isnothing(ud.universities) && return
    isnothing(areas) && return

    for area in areas.members
        for person in area.people
            person.dead && continue
            (19 <= person.age <= 24) || continue
            !isnothing(person.subgroups.primary_activity) && continue

            # Assign to first non-full university (simplified — real version
            # uses spatial proximity)
            for uni in ud.universities.members
                uni.group.external == true && continue
                if !is_full(uni)
                    add!(uni, person)
                    break
                end
            end
        end
    end
end
