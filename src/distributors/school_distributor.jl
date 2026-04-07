# ---------------------------------------------------------------------------
# SchoolDistributor — assign children to schools
# ---------------------------------------------------------------------------

struct SchoolDistributor
    schools::Any  # Supergroup of schools
end

"""
    distribute_kids_to_school!(sd::SchoolDistributor, areas)

For each area, assign school-age children to the nearest appropriate school.
"""
function distribute_kids_to_school!(sd::SchoolDistributor, areas)
    isnothing(sd.schools) && return

    for area in areas.members
        for person in area.people
            person.dead && continue
            for school in sd.schools.members
                school.group.external == true && continue
                if school.age_min <= person.age <= school.age_max && !is_full(school)
                    add!(school, person)
                    break
                end
            end
        end
    end
end

"""
    distribute_teachers_to_schools!(sd::SchoolDistributor, super_areas)

Assign teachers to schools based on teacher-student ratios.
"""
function distribute_teachers_to_schools!(sd::SchoolDistributor, super_areas)
    isnothing(sd.schools) && return

    for school in sd.schools.members
        school.group.external == true && continue
        n_teachers_needed = max(1, div(n_pupils(school), 30))
        n_current = n_teachers(school)
        # Teachers would be drawn from area workers — stub
    end
end
