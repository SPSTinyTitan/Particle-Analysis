#include "matrix_wrappers.h"

namespace matrix{
    
    //C = (alpha * A) x (beta * B)
    //A - M x N
    //B - N x K
    //C - M x K
    __host__ void mult(float* A, float* B, float* C, float alpha, float beta, bool TA, bool TB, int M, int N, int K){

        //Initializing CuBlas
        cublasHandle_t cublasH = NULL;
        cublasStatus_t cublas_status = CUBLAS_STATUS_SUCCESS;
        cublasOperation_t OA = (TA ? CUBLAS_OP_T : CUBLAS_OP_N);
        cublasOperation_t OB = (TB ? CUBLAS_OP_T : CUBLAS_OP_N);
        cublas_status = cublasCreate(&cublasH);
        assert(CUBLAS_STATUS_SUCCESS == cublas_status);

        //Zeroing results
        cudaMemset(C, 0, M * K * sizeof(float));

        //Multiplying
        cublas_status = cublasSgemm_v2(
            cublasH,
            OA, OB,
            M, K, N,
            &alpha,
            A, M,
            B, N,
            &beta,
            C, M
        );
        assert(CUBLAS_STATUS_SUCCESS == cublas_status);
    }

    //Calculates diagonal matrix multiplication
    //C = A x B
    //A - 1 x N diagonal (representing MxN)
    //B - N x K
    __host__ void multD(float* A, float* B, float* C, int M, int N){
        
        //Initializing CuBlas
        cublasHandle_t cublasH = NULL;
        cublasStatus_t cublas_status = CUBLAS_STATUS_SUCCESS;
        cublas_status = cublasCreate(&cublasH);
        assert(CUBLAS_STATUS_SUCCESS == cublas_status);

        //Zeroing results
        gpuErrchk(cudaMemset(C, 0, M * N * sizeof(float)));

        //Multiplying
        cublas_status = cublasSdgmm(
            cublasH, CUBLAS_SIDE_LEFT,
            M, N,
            B, M,
            A, 1,
            C, M
        );
        assert(CUBLAS_STATUS_SUCCESS == cublas_status);
    }

    //Nvidia Reference implementation
    __global__ void transpose_(float *A, float *B, int M, int N){
        __shared__ float block[BLOCK_DIM][BLOCK_DIM+1];
        
        // read the matrix tile into shared memory
        unsigned int xIndex = blockIdx.x * BLOCK_DIM + threadIdx.x;
        unsigned int yIndex = blockIdx.y * BLOCK_DIM + threadIdx.y;
        if((xIndex < M) && (yIndex < N))
        {
            unsigned int index_in = yIndex * M + xIndex;
            block[threadIdx.y][threadIdx.x] = A[index_in];
        }

        __syncthreads();

        // write the transposed matrix tile to global memory
        xIndex = blockIdx.y * BLOCK_DIM + threadIdx.x;
        yIndex = blockIdx.x * BLOCK_DIM + threadIdx.y;
        if((xIndex < N) && (yIndex < M))
        {
            unsigned int index_out = yIndex * N + xIndex;
            B[index_out] = block[threadIdx.x][threadIdx.y];
        }
    }
    __host__ void transpose(float* A, float* B, int M, int N){

        float* C;
        //Copy matrix if storing back
        if (A == B){
            gpuErrchk(cudaMalloc(&C, M * N * sizeof(float)));
            vector::copy(C, A, M * N);
        }
        else
            C = A;
        dim3 grid((M - 1 + BLOCK_DIM) / BLOCK_DIM, (N - 1 + BLOCK_DIM) / BLOCK_DIM, 1);
        dim3 threads(BLOCK_DIM, BLOCK_DIM, 1);
        transpose_<<<grid, threads>>>(C, B, M, N);

    }
}