#define CUDA
#define SCALAR
// #define GIT_HASH "abc"
// #define MACRO_FLAGS "HYDRO"

#include "dust_model.h"

#include <cstdio>
#include<stdio.h>
#include <fstream>

#include <vector>

#include "../../../../cholla/src/global/global.h"
#include "../../../../cholla/src/global/global_cuda.h"
#include "../../../../cholla/src/utils/gpu.hpp"
#include "../../../../cholla/src/utils/hydro_utilities.h"
#include "../../../../cholla/src/utils/cuda_utilities.h"
#include "../../../../cholla/src/grid/grid3D.h"

const int k_n_fields = 6;
const int k_n_cells = 1;
const int k_nx = 1;
const int k_ny = 1;
const int k_nz = 1;
const int k_n_ghost = 0;
const int k_ngrid = (k_n_cells + TPB - 1) / TPB;

int main() {
  Real gamma = 1.6666666666666667;

  Real rho = 1.67260e-26;
  Real vx = 3.0;
  Real vy = 2.0;
  Real vz = 1.0;
  Real P = 3.10657e-2;
  Real rho_d = 1.67260e-26/3;

  Real dt = 1e4;

  Real *host_conserved;
  Real *dev_conserved;

  int n_dt = 1e6;
  Real t_arr[n_dt] = {0};
  Real host_out[n_dt] = {0};

  std::vector<double> vec_1 = linspace(1, 10, 3);
  print_vector(vec_1);

  // initialize time array
  Real dt_i = dt;
  for(int i=0; i<n_dt; i++) {
    t_arr[i] = dt_i;
    dt_i += dt;
  }

  for(int i=0; i<n_dt; i++) {
    // Memory allocation for host arrays
    CudaSafeCall(cudaHostAlloc(&host_conserved, k_n_fields*k_n_cells*sizeof(Real), cudaHostAllocDefault));
    //host_conserved = (Real*)malloc(k_n_fields*k_n_cells*sizeof(Real));
    // Memory allocation for device arrays
    CudaSafeCall(cudaMalloc(&dev_conserved, k_n_fields*k_n_cells*sizeof(Real)));

    // Initialize host array
    Conserved_Init(host_conserved, rho, vx, vy, vz, P, rho_d, gamma, k_n_cells, k_nx, k_ny, k_nz, k_n_ghost, k_n_fields);

    // Copy host to device
    CudaSafeCall(cudaMemcpy(dev_conserved, host_conserved, k_n_fields*k_n_cells*sizeof(Real), cudaMemcpyHostToDevice));

    // std::cout << "host_i: " << host_conserved[5*k_n_cells] << "\n";

    Dust_Update(dev_conserved, k_nx, k_ny, k_nz, k_n_ghost, k_n_fields, dt, gamma);

    // Copy device to host
    CudaSafeCall(cudaMemcpy(host_conserved, dev_conserved, k_n_fields*k_n_cells*sizeof(Real), cudaMemcpyDeviceToHost));

    // std::cout << "host_f: " << host_conserved[5*k_n_cells] << "\n";
    host_out[i] = host_conserved[5*k_n_cells];

    // free host and device memory
    CudaSafeCall(cudaFreeHost(host_conserved));
    CudaSafeCall(cudaFree(dev_conserved)); 
  }

  std::ofstream myfile ("output.txt");
  if (myfile.is_open())
  {
    for(int i=0; i<n_dt; i++) {
      // std::cout << t_arr[i] << "\n";
      myfile << t_arr[i] << "," ;
      myfile << host_out[i] << "\n" ;
    }
    myfile.close();
  }
  else std::cout << "Unable to open file";
  return 0;

  for(int i=0; i<n_dt; i++) {
    // std::cout << t_arr[i] << "\n";
    continue;
  }

  for(int i=0; i<n_dt; i++) {
    // std::cout << host_out[i] << "\n";
    continue;
  }

}

 void Dust_Update(Real *dev_conserved, int nx, int ny, int nz, int n_ghost, int n_fields, Real dt, Real gamma) {
    dim3 dim1dGrid(k_ngrid, 1, 1);
    dim3 dim1dBlock(TPB, 1, 1);
    hipLaunchKernelGGL(Dust_Kernel, dim1dGrid, dim1dBlock, 0, 0, dev_conserved, nx, ny, nz, n_ghost, n_fields, dt, gamma);
    CudaCheckError();  
}

__global__ void Dust_Kernel(Real *dev_conserved, int nx, int ny, int nz, int n_ghost, int n_fields, Real dt, Real gamma) {
    //__shared__ Real min_dt[TPB];
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

    // define physics variables
    Real d_gas, d_dust; // fluid mass densities
    Real n = 1; // gas number density
    Real T, E, P; // temperature, energy, pressure
    Real vx, vy, vz; // velocities
    #ifdef DE
    Real ge;
    #endif // DE

    dt *= 3.154e7; // in seconds

    // define integration variables
    Real dd_dt; // instantaneous rate of change in dust density
    Real dd; // change in dust density at current time-step
    Real dd_max = 0.01; // allowable percentage of dust density increase
    Real dt_sub; //refined timestep
    if (xid >= is && xid < ie && yid >= js && yid < je && zid >= ks && zid < ke) {
        // get quantities from dev_conserved
        d_gas = dev_conserved[id];
        //d_dust = dev_conserved[5*n_cells + id];
        d_dust = dev_conserved[5*n_cells + id];
        E = dev_conserved[4*n_cells + id];
        //printf("kernel: %7.4e\n", d_dust);
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

        //printf("P: %e\n", P);

        #ifdef DE
        T_init = hydro_utilities::Calc_Temp_DE(d_gas, ge, gamma, n);
        #endif // DE

        T = T_init;

        // calculate change in dust density
        Dust dust_obj(T, n, dt, d_gas, d_dust);
        dust_obj.set_tau_sp();

        dd_dt = dust_obj.calc_dd_dt();
        dd = dd_dt * dt;

        // printf("tau_sp: %e\n", dust_obj.tau_sp_);

        // printf("T: %e\n", T);
        // printf("n: %e\n", n);
        // printf("dt: %e\n", dt);

        // ensure that dust density is not changing too rapidly
        while (d_dust/dd > dd_max) {
            dt_sub = dd_max * d_dust / dd_dt;
            dust_obj.d_dust_ += dt_sub * dd_dt;
            dust_obj.dt_ -= dt_sub;
            dt = dust_obj.dt_;
            dd_dt = dust_obj.calc_dd_dt();
            dd = dt * dd_dt;
        }

        dust_obj.d_dust_ += dd;

        // printf("dd_dt: %e\n", dd_dt);
        // printf("dd: %e\n", dd);
        // printf("after calculation: %7.4e\n", dust_obj.d_dust_);

        // update dust and gas densities
        dev_conserved[5*n_cells + id] = dust_obj.d_dust_;
        
        #ifdef DE
        dev_conserved[(n_fields-1)*n_cells + id] = d*ge;
        #endif
    }
}

__device__ void Dust::set_tau_sp() {
  Real a1 = 1; // dust grain size in units of 0.1 micrometers
  Real d0 = n_ / (6e-4); // gas density in units of 10^-27 g/cm^3
  Real T_0 = 2e6; // K
  Real omega = 2.5;
  Real A = 0.17e9 * YR_IN_S_; // 0.17 Gyr in s

  tau_sp_ = A * (a1/d0) * (pow(T_0/T_, omega) + 1); // s

  // printf("tau_sp (yr): %e\n", tau_sp_/YR_IN_S_);
}

__device__ Real Dust::calc_dd_dt() {
    return -d_dust_ / (tau_sp_/3);
}

// function to initialize conserved variable array, similar to Grid3D::Constant in grid/initial_conditions.cpp 
void Conserved_Init(Real *host_conserved, Real rho, Real vx, Real vy, Real vz, Real P, Real rho_d, Real gamma, int n_cells, int nx, int ny, int nz, int n_ghost, int n_fields)
{
  int i, j, k, id;
  int istart, jstart, kstart, iend, jend, kend;

  istart = n_ghost;
  iend   = nx-n_ghost;
  if (ny > 1) {
    jstart = n_ghost;
    jend   = ny-n_ghost;
  }
  else {
    jstart = 0;
    jend   = ny;
  }
  if (nz > 1) {
    kstart = n_ghost;
    kend   = nz-n_ghost;
  }
  else {
    kstart = 0;
    kend   = nz;
  }

  // set initial values of conserved variables
  for(k=kstart-1; k<kend; k++) {
    for(j=jstart-1; j<jend; j++) {
      for(i=istart-1; i<iend; i++) {

        //get cell index
        id = i + j*nx + k*nx*ny;

        // Exclude the rightmost ghost cell on the "left" side
        if ((k >= kstart) and (j >= jstart) and (i >= istart))
        {
          // set constant initial states
          host_conserved[id] = rho;
          host_conserved[1*n_cells+id] = rho*vx;
          host_conserved[2*n_cells+id] = rho*vy;
          host_conserved[3*n_cells+id] = rho*vz;
          host_conserved[4*n_cells+id] = P/(gamma-1.0) + 0.5*rho*(vx*vx + vy*vy + vz*vz);
          #ifdef DE
          host_conserved[(n_fields-1)*n_cells+id] = P/(gamma-1.0);
          #endif  // DE
          #ifdef SCALAR
          host_conserved[5*n_cells+id] = rho_d;
          #endif // SCALAR
        }
      }
    }
  }
}

template<typename T>
std::vector<double> linspace(T start_in, T end_in, int num_in)
{

  std::vector<double> linspaced;

  double start = static_cast<double>(start_in);
  double end = static_cast<double>(end_in);
  double num = static_cast<double>(num_in);

  if (num == 0) { return linspaced; }
  if (num == 1) 
    {
      linspaced.push_back(start);
      return linspaced;
    }

  double delta = (end - start) / (num - 1);

  for(int i=0; i < num-1; ++i)
    {
      linspaced.push_back(start + delta * i);
    }
  linspaced.push_back(end); // I want to ensure that start and end
                            // are exactly the same as the input
  return linspaced;
}