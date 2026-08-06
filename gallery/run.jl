using TTGC
using HDF5
using UnPack

# Setup simulation
casedir    = abspath(@__DIR__)
equation   = "convection"
solverfile = "up_b_cuda.jl"
include(joinpath(dirname(pathof(TTGC)), joinpath(equation, solverfile)))

function runsim(casedir::String)

  # Load Arrays
  partition_folder = casedir
  initfile         = "init.h5"
  hdf5_file        = "mesh3d.mesh.h5"
  u              = h5read(joinpath(partition_folder, initfile), "u")
  i_cell_to_node = reshape(
    h5read(joinpath(partition_folder, hdf5_file), "Connectivity/tet->node"), 4, :
  )
  cell_vol       = h5read(joinpath(partition_folder, hdf5_file), "cell_vol")
  node_vol       = h5read(joinpath(partition_folder, hdf5_file), "VertexData/volume")
  skx            = h5read(joinpath(partition_folder, hdf5_file), "skx")
  sky            = h5read(joinpath(partition_folder, hdf5_file), "sky")
  skz            = h5read(joinpath(partition_folder, hdf5_file), "skz")
  i_ncell        = div(length(i_cell_to_node), 4)
  i_nnode        = length(node_vol)
  cx             = h5read(joinpath(partition_folder, initfile), "cx")
  cy             = h5read(joinpath(partition_folder, initfile), "cy")
  cz             = h5read(joinpath(partition_folder, initfile), "cz")
  c              = hcat(cx,cy,cz)'
  beta           = ones(Int, i_ncell) ./ 6
  gamma          = ones(Int, i_ncell) ./ 100
  i_njac         = 32
  res            = zero(u)
  res2           = zero(u)
  up             = zero(u)
  mup            = zero(u)
  uref           = zero(u)
  loss           = zeros(eltype(u), 1)
  i_node_perio_2 = h5read(joinpath(partition_folder, hdf5_file), "i_node_perio_2")
  i_node_perio_4 = h5read(joinpath(partition_folder, hdf5_file), "i_node_perio_4")
  i_node_perio_8 = h5read(joinpath(partition_folder, hdf5_file), "i_node_perio_8")
  i_nset_perio_2 = length(i_node_perio_2[:,1])
  i_nset_perio_4 = length(i_node_perio_4[:,1])
  i_nset_perio_8 = length(i_node_perio_8[:,1])

  # Define simulation time step
  config              = TTGC._read_config_yml(casedir)
  @unpack lx, nx, cfl = config
  dx                  = lx / (nx - 1)
  cxmax               = maximum(cx)
  dt                  = cfl * dx / cxmax

  # Define number of time steps
  # required to perform one box turn
  nturn = 1
  nstep = Int(nturn * div(lx, cxmax * dt))

  # Check if CUDA device is present
  hasgpu = false
  if CUDA.has_cuda_gpu()
    hasgpu = true
  end

  # Offload Arrays to CUDA device if it is present
  if hasgpu

    i_cell_to_node = i_cell_to_node |> CuArray
    i_node_perio_2 = i_node_perio_2 |> CuArray
    i_node_perio_4 = i_node_perio_4 |> CuArray
    i_node_perio_8 = i_node_perio_8 |> CuArray
    node_vol       = node_vol       |> CuArray
    cell_vol       = cell_vol       |> CuArray
    c              = c              |> CuArray
    u              = u              |> CuArray
    uref           = uref           |> CuArray
    up             = up             |> CuArray
    mup            = mup            |> CuArray
    res            = res            |> CuArray
    res2           = res2           |> CuArray
    beta           = beta           |> CuArray
    gamma          = gamma          |> CuArray
    skx            = skx            |> CuArray
    sky            = sky            |> CuArray
    skz            = skz            |> CuArray
    loss           = loss           |> CuArray

  end

  # Enforce periodic BCs to 'node_vol'
  node_vol[i_node_perio_2] .= sum(node_vol[i_node_perio_2], dims=2)
  node_vol[i_node_perio_4] .= sum(node_vol[i_node_perio_4], dims=2)
  node_vol[i_node_perio_8] .= sum(node_vol[i_node_perio_8], dims=2)

  # Define path where simulation results
  # will be stored
  solutpath = joinpath(partition_folder, "solut")
  rm(solutpath, force=true, recursive=true)
  mkpath(solutpath)

  # Copy-paste initial condition
  istep     = 0
  solutname = lpad(istep, 3, string(0))
  h5file    = joinpath(solutpath, solutname * ".h5")
  cp(joinpath(partition_folder, initfile), h5file)
  xmfwrite(h5file, time=istep*dt)
  
  # Loop over time
  for istep = 1:nstep

    # Zero-out auxiliary arrays
    up   .= 0.
    mup  .= 0.
    res  .= 0.
    res2 .= 0.

    if hasgpu
      func_cuda(u, uref, i_cell_to_node, cell_vol, node_vol, skx, sky, skz, i_ncell, i_nnode, c, dt, beta, gamma, i_njac, res, res2, up, mup, i_node_perio_2, i_node_perio_4, i_node_perio_8, i_nset_perio_2, i_nset_perio_4, i_nset_perio_8, loss)
    else
      func(u, uref, i_cell_to_node, cell_vol, node_vol, skx, sky, skz, i_ncell, i_nnode, c, dt, beta, gamma, i_njac, res, res2, up, mup, i_node_perio_2, i_node_perio_4, i_node_perio_8, i_nset_perio_2, i_nset_perio_4, i_nset_perio_8, loss)
    end

    # Update state variable
    u .+= up
    @info "" maximum(up)

    # Write HDF5 and corresponding XMF
    solutname = lpad(istep, 3, string(0))
    h5file    = joinpath(solutpath, solutname * ".h5")
    h5write(h5file, "u", Array(u))
    xmfwrite(h5file, time=istep*dt)

  end

  # Write XMF collection
  xmfwritecollection(solutpath)

end

runsim(casedir)
