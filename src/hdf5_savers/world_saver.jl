# ---------------------------------------------------------------------------
# HDF5 World I/O — save / load world state
# ---------------------------------------------------------------------------

"""
    save_world_to_hdf5(world::World, file_path::String; chunk_size=100000)

Serialize the world's population to an HDF5 file.
"""
function save_world_to_hdf5(world::World, file_path::String; chunk_size::Int=100000)
    @info "Saving world to $file_path"
    h5open(file_path, "w") do file
        # Save population
        if !isnothing(world.people)
            g = create_group(file, "population")
            n = length(world.people)
            g["ids"]   = [p.id  for p in world.people.people]
            g["ages"]  = [p.age for p in world.people.people]
            g["sexes"] = [string(p.sex) for p in world.people.people]
        end
        # Additional savers would go here for each group type
    end
end

"""
    load_world_from_hdf5(file_path::String) -> World

Deserialize a world from an HDF5 file (stub).
"""
function load_world_from_hdf5(file_path::String)::World
    @info "Loading world from $file_path"
    world = World()
    # Load from HDF5 — stub
    return world
end
