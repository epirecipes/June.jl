# ---------------------------------------------------------------------------
# Grocery — thin wrapper around SocialVenue
# ---------------------------------------------------------------------------

const Grocery   = SocialVenue
const Groceries = SocialVenues

function create_groceries(; area=nothing)
    return SocialVenues("grocery")
end
