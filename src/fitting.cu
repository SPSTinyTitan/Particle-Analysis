#include "fitting.h"

namespace fit{

    //Return: ae^(kt) + be^(qt) + c
    __global__ void fdoubleExp_(float* A, float a, float b, float c, float k, float q, int N){
        int i = blockDim.x * blockIdx.x + threadIdx.x;
        if (i < N)
            A[i] = a * expf(k * i) + b * expf(q * i) + c;
    }
    __host__ void fdoubleExp(float* A, float* param, int N){
        int blocksPerGrid = (N + threadsPerBlock - 1) / threadsPerBlock;
        fdoubleExp_<<<blocksPerGrid, threadsPerBlock>>>(A, param[0], param[1], param[2], -abs(param[3]), -abs(param[4]), N);
        gpuErrchk(cudaDeviceSynchronize());
    }

    //Return: ae^(kt) + b
    __global__ void fexp_(float* A, float a, float b, float k, int N){
        int i = blockDim.x * blockIdx.x + threadIdx.x;
        if (i < N)
            A[i] = a * expf(k * i) + b;
    }
    __host__ void fexp(float* A, float* param, int N){
        int blocksPerGrid = (N + threadsPerBlock - 1) / threadsPerBlock;
        fexp_<<<blocksPerGrid, threadsPerBlock>>>(A, param[0], param[1], -abs(param[2]), N);
        gpuErrchk(cudaDeviceSynchronize());
    }

    //Return: ax + b
    __global__ void flinear_(float* A, float a, float b, int N){
        int i = blockDim.x * blockIdx.x + threadIdx.x;
        if (i < N)
            A[i] = a * i + b;
    }
    __host__ void flinear(float* A, float* param, int N){
        int blocksPerGrid = (N + threadsPerBlock - 1) / threadsPerBlock;
        flinear_<<<blocksPerGrid, threadsPerBlock>>>(A, param[0], param[1], N);
        gpuErrchk(cudaDeviceSynchronize());
    }
    
    __global__ void lincoef_ (float* A, int N){
        int i = blockDim.x * blockIdx.x + threadIdx.x;
        if (i < N)
            A[i] = i;
            A[N+i] = 1;
    }
    __host__ void lincoef (float* A, int N){
        int blocksPerGrid = (N + threadsPerBlock - 1) / threadsPerBlock;
        lincoef_<<<blocksPerGrid, threadsPerBlock>>>(A, N);
        gpuErrchk(cudaDeviceSynchronize());
    }

    //Calculates the Jacobian of f(t) for K parameters and N data points
    //Returns N x K matrix in column major order
    __host__ void jacobian(float* J, void f(float* A, float* param, int N), float* param, int N, int K){
        const float eps = pow(2,-17);
        float* prev;    gpuErrchk(cudaMalloc(&prev, N * sizeof(float)));
        float* next;    gpuErrchk(cudaMalloc(&next, N * sizeof(float)));
        float temp;

        //Calculate Y(t) for current parameters
        f(prev, param, N);

        //Calculate Y(t) for perturbed parameters
        for (int i = 0; i < K; i++){
            temp = param[i];
            param[i] += eps;
            f(next, param, N);
            vector::sub(next, prev, (float*)&J[i * N], N);
            param[i] = temp;
        }
        
        vector::mult(J, float(1./eps), J, N * K);
        
        if(prev) cudaFree(prev);
        if(next) cudaFree(next);
    }

    //Same as Jacboian() but uses adaptive values of epsilon scaled with the value of param.
    //This can achieve better precisions across a wider range of values.
    //TODO: Consider logarithms then addition instead of multiplications. Reduces arithmetic error.
    __host__ void jacobian_v2(float* J, void f(float* A, float* param, int N), float* param, int N, int K){
        const float eps = pow(2,-10);
        float* prev;    gpuErrchk(cudaMalloc(&prev, N * sizeof(float)));
        float* next;    gpuErrchk(cudaMalloc(&next, N * sizeof(float)));
        float temp, dB, scale;

        //Calculate Y(t) for current parameters
        f(prev, param, N);

        //Calculate Y(t) for perturbed parameters
        for (int i = 0; i < K; i++){
            temp = param[i];
            dB = param[i] * eps;
            
            //Make sure perturbation isn't too small
            if (dB < 1e-31 && dB > -1e-31)
                dB = 1e-30;
            param[i] += dB;

            //scale = dB^-1. Recalculation for precision. 
            scale = (float) (1./((double)temp * eps));

            //Calculating Jacobian
            f(next, param, N);
            vector::sub(next, prev, (float*)&J[i * N], N);
            vector::mult((float*)&J[i * N], scale, (float*)&J[i * N], N);

            param[i] = temp;
        }
        
        if(prev) cudaFree(prev);
        if(next) cudaFree(next);
    }

    __host__ void svd(float* A, float* U, float* S, float* VT, int M, int N){ 
    
        cusolverDnHandle_t cusolverH;
        cusolverStatus_t stat = cusolverDnCreate(&cusolverH);
        assert(CUSOLVER_STATUS_SUCCESS == stat);
        
        int lwork;
        stat = cusolverDnSgesvd_bufferSize(
            cusolverH,
            M,
            N,
            &lwork);
        assert(CUSOLVER_STATUS_SUCCESS == stat);
    
        float* work;    gpuErrchk(cudaMalloc(&work, lwork * sizeof(float)));
        int* devInfo;   gpuErrchk(cudaMalloc(&devInfo, sizeof(int))); 

        stat = cusolverDnSgesvd(
            cusolverH,
            'A',
            'A',
            M, N,
            A, M,
            S,
            U, M,
            VT, N,
            work, lwork,
            NULL,
            devInfo);
        gpuErrchk(cudaDeviceSynchronize());
        assert(CUSOLVER_STATUS_SUCCESS == stat);

        if (work) cudaFree(work);
        if (devInfo) cudaFree(devInfo);
        if (cusolverH) cusolverDnDestroy(cusolverH);
    }
    
}