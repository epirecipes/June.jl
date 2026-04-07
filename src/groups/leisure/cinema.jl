# ---------------------------------------------------------------------------
# Cinema — thin wrapper around SocialVenue
# ---------------------------------------------------------------------------

const Cinema  = SocialVenue
const Cinemas = SocialVenues

function create_cinemas(; area=nothing)
    return SocialVenues("cinema")
end
