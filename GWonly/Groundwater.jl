# The groundwater component
#
# Manages the groundwater level over time, watch out for conductivity units and needs connectivity matrix !

using Mimi
using Distributions


@defcomp Aquifer begin
  aquifers = Index()

  # Aquifer description
  depthaquif = Parameter(index=[aquifers])
  areaaquif = Parameter(index=[aquifers])
  storagecoef = Parameter(index=[aquifers])
  piezohead0 = Parameter(index=[aquifers]) # used for initialisation
  meandepth = Variable(index=[aquifers, time]) # used to compute cost
  # Recharge
  recharge = Parameter(index=[aquifers, time])
  # Withdrawals - to be optimised
  withdrawal = Parameter(index=[aquifers, time])
  # Lateral flows
  lateralflows = Variable(index=[aquifers, time])
  aquiferconnexion = Parameter(index=[aquifers, aquifers]) # aquiferconnexion[aa,aa']=1 -> aquifers are connected, 0 otherwise.
  lateralconductivity = Parameter(index=[aquifers, aquifers])
  # Piezometric head
  piezohead = Variable(index=[aquifers, time])
end

"""
Compute the piezometric head for each reservoirs and the lateral flows between adjacent aquifers
"""
function timestep(c::Aquifer, tt::Int)
  v = c.Variables
  p = c.Parameters
  d = c.Dimensions

  # piezometric head initialisation and simulation (piezohead is actually a drawdown)
  for aa in d.aquifers
    if tt==1
      v.piezohead[aa,tt] = p.piezohead0[aa]
    else
      v.piezohead[aa,tt] = v.piezohead[aa,tt-1] + 1/(p.storagecoef[aa]*p.areaaquif[aa])*(- p.recharge[aa,tt-1] + p.withdrawal[aa,tt-1] + v.lateralflows[aa,tt-1])
    end
  end

  # computation of lateral flows:
  v.lateralflows[:,tt]=zeros(d.aquifers[end],1)

  for aa in 1:d.aquifers[end]
    for aa_ in (aa+1):(d.aquifers[end]-1)
      if p.aquiferconnexion[aa,aa_]==1.
        latflow = p.lateralconductivity[aa,aa_]*(v.piezohead[aa_,tt]-v.piezohead[aa,tt])*12; # in m3/month or m3/year if factor 12
        v.lateralflows[aa,tt] += latflow;
        v.lateralflows[aa_,tt] += -latflow;
      end
    end
  end

  # variable to pass to watercost component. assumption: piezohead does not vary much and it's initial value is representative. piezohead datum is sea level
  for aa in d.aquifers
    v.meandepth[aa,tt] = p.piezohead0[aa]
  end
end

function makeconstraintpiezomin(aa, tt)
    function constraint(model)
        -m[:Aquifer, :piezohead][aa, tt]# piezohead > 0 (non-artesian well)
    end
end
function makeconstraintpiezomax(aa, tt)
    function constraint(model)
       +m[:Aquifer, :piezohead][aa, tt] - m.components[:Aquifer].Parameters.depthaquif[aa] # piezohead > layerthick
    end
end

"""
Add an Aquifer component to the model.
"""
function initaquiferfive(m::Model)
  aquifer = addcomponent(m, Aquifer)

  #five county test:
  aquifer[:depthaquif] = [-100.; -90.; -100.; -80.; -80.];
  aquifer[:storagecoef] = [5e-4; 5e-4; 5e-4; 5e-4; 5e-4];
  aquifer[:piezohead0] = [-55.; -45.; -53.; -33.; -35.];
  aquifer[:areaaquif] = [8e8; 6e8; 5e8; 5e8; 3e8];

  aquifer[:withdrawal] = repeat(rand(Normal(190000,3700), m.indices_counts[:aquifers]), outer=[1, m.indices_counts[:time]]);
  aquifer[:recharge] = repeat(rand(Normal(240000,1000), m.indices_counts[:aquifers]), outer=[1, m.indices_counts[:time]]);

  aquifer[:lateralconductivity] = 100*[0    1e-6 1e-4 1e-6 0   ;
                                   1e-6 0    0    1e-6 0   ;
                                   1e-4 0    0    1e-6 0
                                   1e-6 1e-6 1e-6 0    1e-3;
                                   0    0    0    1e-3 0   ];

  aquifer[:aquiferconnexion] = [ 1. 1. 1. 1. 0.; 1. 0 0 1. 0; 1. 0 0 1. 0; 1. 1. 1. 0 1.; 0 0 0 1. 0];
  aquifer
end

function initaquifercontusmac(m::Model)
  aquifer = addcomponent(m, Aquifer)
  v=[1:3109]

  temp = readdlm("Dropbox/POSTDOC/AW-julia/operational-problem/data/v_FIPS.txt")

  temp = readdlm("Dropbox/POSTDOC/AW-julia/operational-problem/data/aquifer_depth.txt")
  aquifer[:depthaquif] = temp[v,1];
  aquifer[:piezohead0] = 0.85*temp[v,1]; # needs to be changed
  temp = readdlm("Dropbox/POSTDOC/AW-julia/operational-problem/data/vector_storativity.txt")
  aquifer[:storagecoef] = temp[v,1];
  temp = readdlm("Dropbox/POSTDOC/AW-julia/operational-problem/data/county_area.txt")
  aquifer[:areaaquif] = temp[v,1];

  #Mtemp = readdlm("Dropbox/POSTDOC/AW-julia/operational-problem/data/oneyearrecharge.txt")
  M = zeros(m.indices_counts[:regions],m.indices_counts[:time]);
  aquifer[:withdrawal] = M;
  aquifer[:recharge] = M;

  temp = readdlm("Dropbox/POSTDOC/AW-julia/operational-problem/data/matrix_leakage_factor.txt")
  aquifer[:lateralconductivity] = temp[v,v];
  temp = readdlm("Dropbox/POSTDOC/AW-julia/operational-problem/data/connectivity_matrix.txt")
  aquifer[:aquiferconnexion] = temp[v,v];
  aquifer
end

