# ---------------------------------------------------------------------------
# MPI setup — optional, only active when MPI.jl is available
# ---------------------------------------------------------------------------

let
    global mpi_comm, mpi_rank, mpi_size
    try
        if !MPI.Initialized()
            MPI.Init()
        end
        mpi_comm = MPI.COMM_WORLD
        mpi_rank = MPI.Comm_rank(mpi_comm)
        mpi_size = MPI.Comm_size(mpi_comm)
    catch
        mpi_comm = nothing
        mpi_rank = 0
        mpi_size = 1
    end
end
