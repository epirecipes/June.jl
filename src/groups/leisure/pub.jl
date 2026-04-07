# ---------------------------------------------------------------------------
# Pub — thin wrapper around SocialVenue
# ---------------------------------------------------------------------------

const Pub  = SocialVenue
const Pubs = SocialVenues

function create_pubs(; area=nothing)
    return SocialVenues("pub")
end
