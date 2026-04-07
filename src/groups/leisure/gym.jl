# ---------------------------------------------------------------------------
# Gym — thin wrapper around SocialVenue
# ---------------------------------------------------------------------------

const Gym  = SocialVenue
const Gyms = SocialVenues

function create_gyms(; area=nothing)
    return SocialVenues("gym")
end
