#include "dust_model.h"

#include <cstdio>
#include <vector>

#include "/ihome/hrichie/her45/GitHub/cholla/src/global/global.h"
#include "/ihome/hrichie/her45/GitHub/cholla/src/global/global_cuda.h"
#include "/ihome/hrichie/her45/GitHub/cholla/src/utils/gpu.hpp"
#include "/ihome/hrichie/her45/GitHub/cholla/src/utils/hydro_utilities.h"
#include "/ihome/hrichie/her45/GitHub/cholla/src/utils/cuda_utilities.h"

int main() {
    cuda_hello<<<1, 1>>>();
    return 0;
}

 void dust_update(Real *dev_conserved, int nx, int ny, int nz, int n_ghost, int n_fields, Real dt, Real gamma, Real *dt_array) {
    dim3 dim1dGrid(ngrid, 1, 1);
    dim3 dim1dBlock(TPB, 1, 1);
    hipLaunchKernelGGL(dust_kernel, dim1dGrid, dim1dBlock, 0, 0, dev_conserved, nx, ny, nz, n_ghost, n_fields, dt, gamma, dt_array);
    CudaCheckError();  
}

__global__ void dust_kernel(Real *dev_conserved, int nx, int ny, int nz, int n_ghost, int n_fields, Real dt, Real gamma, Real *dt_array) {
    __shared__ Real min_dt[TPB];

    // get grid indices
    int n_cells = nx * ny * nz;
    int is, ie, js, je, ks, ke;
    cuda_utilities::Get_Real_Indices(n_ghost, nx, ny, nz, is, ie, js, je, ks, ke);

    // get a global thread ID
    int blockId = blockIdx.x + blockIdx.y * gridDim.x;
    int id = threadIdx.x + blockId * blockDim.x;
    int zid = id / (nx * ny);
    int yid = (id - zid * nx * ny) / nx;
    int xid = id - zid * nx * ny - yid * nx;
    // add a thread id within the block
    int tid = threadIdx.x;

    // set min dt to a high number
    min_dt[tid] = 1e10;
    __syncthreads();

    // define physics variables
    Real d_gas, d_dust; // fluid mass densities
    Real n; // gas number density
    Real T, E, P; // temperature, energy, pressure
    Real vx, vy, vz; // velocities
    #ifdef DE
    Real ge;
    #endif // DE

    // define integration variables
    Real dd_dt; // instantaneous rate of change in dust density
    Real dd; // change in dust density at current time-step
    Real dd_max = 0.01; // allowable percentage of dust density increase
    Real dt_sub; //refined timestep

    if (xid >= is && xid < ie && yid >= js && yid < je && zid >= ks && zid < ke) {
        // get quantities from dev_conserved
        d_gas = dev_conserved[id];
        d_dust = dev_conserved[5*n_cells + id];
        E = dev_conserved[4*n_cells + id];
        // make sure thread hasn't crashed
        if (E < 0.0 || E != E) return;
        
        vx = dev_conserved[1*n_cells + id] / d_gas;
        vy = dev_conserved[2*n_cells + id] / d_gas;
        vz = dev_conserved[3*n_cells + id] / d_gas;

        #ifdef DE
        ge = dev_conserved[(n_fields-1)*n_cells + id] / d_gas;
        ge = fmax(ge, (Real) TINY_NUMBER);
        #endif // DE

        // calculate physical quantities
        P = hydro_utilities::Calc_Pressure_Primitive(E, d_gas, vx, vy, vz, gamma);

        Real T_init;
        T_init = hydro_utilities::Calc_Temp(P, n);

        #ifdef DE
        T_init = hydro_utilities::Calc_Temp_DE(d_gas, ge, gamma, n);
        #endif // DE

        T = T_init;

        // calculate change in dust density
        Dust dust_obj(T, n, dt, d_gas, d_dust);
        dust_obj.set_tau_sp();

        dd_dt = dust_obj.calc_dd_dt();
        dd = dd_dt * dt;

        // ensure that dust density is not changing too rapidly
        while (d_dust/dd > dd_max) {
            dt_sub = dd_max * d_dust / dd_dt;
            dust_obj.d_dust_ += dt_sub * dd_dt;
            dust_obj.dt_ -= dt_sub;
            dt = dust_obj.dt_;
            dd_dt = dust_obj.calc_dd_dt();
            dd = dt * dd_dt;
        }

        // update dust and gas densities
        dev_conserved[5*n_cells + id] = dust_obj.d_dust_;
        dev_conserved[id] -= dd;
        
        #ifdef DE
        dev_conserved[(n_fields-1)*n_cells + id] = d*ge;
        #endif
    }
    __syncthreads();

    // do the reduction in shared memory (find the min timestep in the block)
    for (unsigned int s=1; s<blockDim.x; s*=2) {
        if (tid % (2*s) == 0) {
        min_dt[tid] = fmin(min_dt[tid], min_dt[tid + s]);
        }
        __syncthreads();
    }

    // write the result for this block to global memory
     if (tid == 0) dt_array[blockIdx.x] = min_dt[0];
}

void Dust::set_tau_sp() {
  Real a1 = 1; // dust grain size in units of 0.1 micrometers
  Real d0 = n_ / (6*pow(10, -4)); // gas density in units of 10^-27 g/cm^3
  Real T_0 = 2*pow(10, 6); // K
  Real omega = 2.5;
  Real A = 0.17*pow(10, 9) * YR_IN_S_; // 0.17 Gyr in s

  tau_sp_ = A * (a1/d0) * (pow(T_0/T_, omega) + 1); // s
}

Real Dust::calc_dd_dt() {
    return -d_dust_ / (tau_sp_/3);
}