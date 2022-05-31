#!/bin/bash

cd pytorch
set -ex

# clean up an existing cmake build directory
rm -rf build

# uncomment to debug cmake build
# export CMAKE_VERBOSE_MAKEFILE=1

export CFLAGS="$(echo $CFLAGS | sed 's/-fvisibility-inlines-hidden//g')"
export CXXFLAGS="$(echo $CXXFLAGS | sed 's/-fvisibility-inlines-hidden//g')"
export LDFLAGS="$(echo $LDFLAGS | sed 's/-Wl,--as-needed//g')"
export LDFLAGS="$(echo $LDFLAGS | sed 's/-Wl,-dead_strip_dylibs//g')"
export LDFLAGS_LD="$(echo $LDFLAGS_LD | sed 's/-dead_strip_dylibs//g')"
export CXXFLAGS="$CXXFLAGS -Wno-deprecated-declarations"
export CFLAGS="$CFLAGS -Wno-deprecated-declarations"

if [[ "$target_platform" == "osx-64" ]]; then
  export CXXFLAGS="$CXXFLAGS -DTARGET_OS_OSX=1"
  export CFLAGS="$CFLAGS -DTARGET_OS_OSX=1"
fi

# Dynamic libraries need to be lazily loaded so that torch
# can be imported on system without a GPU
LDFLAGS="${LDFLAGS//-Wl,-z,now/-Wl,-z,lazy}"

export CMAKE_GENERATOR=Ninja
export CMAKE_LIBRARY_PATH=$PREFIX/lib:$PREFIX/include:$CMAKE_LIBRARY_PATH
export CMAKE_PREFIX_PATH=$PREFIX
for ARG in $CMAKE_ARGS; do
  if [[ "$ARG" == "-DCMAKE_"* ]]; then
    cmake_arg=$(echo $ARG | cut -d= -f1)
    cmake_arg=$(echo $cmake_arg| cut -dD -f2-)
    cmake_val=$(echo $ARG | cut -d= -f2-)
    printf -v $cmake_arg "$cmake_val"
    export ${cmake_arg}
  fi
done
# unset CMAKE_INSTALL_PREFIX
# export TH_BINARY_BUILD=1
export PYTORCH_BUILD_VERSION=$PKG_VERSION
export PYTORCH_BUILD_NUMBER=$PKG_BUILDNUM

# export USE_NINJA=OFF
export INSTALL_TEST=0
export BUILD_TEST=0

export USE_SYSTEM_CPUINFO=1
export USE_SYSTEM_SLEEF=1
# No GPU GLOO
export USE_SYSTEM_GLOO=0
export USE_SYSTEM_FP16=1
export USE_SYSTEM_PYBIND11=1
export USE_SYSTEM_PTHREADPOOL=1
export USE_SYSTEM_PSIMD=1
export USE_SYSTEM_FXDIV=1
export USE_SYSTEM_ONNX=0
export USE_SYSTEM_XNNPACK=1
# use our protobuf
export BUILD_CUSTOM_PROTOBUF=OFF
rm -rf $PREFIX/bin/protoc

# I don't know where this folder comes from, but it's interfering with the build in osx-64
rm -rf $PREFIX/git

if [[ "$CONDA_BUILD_CROSS_COMPILATION" == 1 ]]; then
    export COMPILER_WORKS_EXITCODE=0
    export COMPILER_WORKS_EXITCODE__TRYRUN_OUTPUT=""
fi

# MacOS build is simple, and will not be for CUDA
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Produce macOS builds with torch.distributed support.
    # This is enabled by default on Linux, but disabled by default on macOS,
    # because it requires an non-bundled compile-time dependency (libuv
    # through gloo). This dependency is made available through meta.yaml, so
    # we can override the default and set USE_DISTRIBUTED=1.
    export USE_DISTRIBUTED=1

    if [[ "$target_platform" == "osx-arm64" ]]; then
        export BLAS=OpenBLAS
        export USE_MKLDNN=0
        # There is a problem with pkg-config
        # See https://github.com/conda-forge/pkg-config-feedstock/issues/38
        export USE_DISTRIBUTED=0
    fi
    $PYTHON -m pip install . --no-deps -vv
    exit 0
fi

export MAX_JOBS=${CPU_COUNT}

if [[ ${cuda_compiler_version} != "None" ]]; then
    export USE_CUDA=1
    export TORCH_CUDA_ARCH_LIST="3.5;5.0+PTX"
    if [[ ${cuda_compiler_version} == 9.0* ]]; then
        export TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST;6.0;7.0"
    elif [[ ${cuda_compiler_version} == 9.2* ]]; then
        export TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST;6.0;6.1;7.0"
    elif [[ ${cuda_compiler_version} == 10.* ]]; then
        export TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST;6.0;6.1;7.0;7.5"
    elif [[ ${cuda_compiler_version} == 11.0* ]]; then
        export TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST;6.0;6.1;7.0;7.5;8.0"
    elif [[ ${cuda_compiler_version} == 11.1 ]]; then
        export TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST;6.0;6.1;7.0;7.5;8.0;8.6"
    elif [[ ${cuda_compiler_version} == 11.2 ]]; then
        export TORCH_CUDA_ARCH_LIST="$TORCH_CUDA_ARCH_LIST;6.0;6.1;7.0;7.5;8.0;8.6"
    else
        echo "unsupported cuda version. edit build_pytorch.sh"
        exit 1
    fi
    export TORCH_NVCC_FLAGS="-Xfatbin -compress-all"
    export NCCL_ROOT_DIR=$PREFIX
    export NCCL_INCLUDE_DIR=$PREFIX/include
    export USE_SYSTEM_NCCL=1
    export USE_STATIC_NCCL=0
    export USE_STATIC_CUDNN=0
    export CUDA_TOOLKIT_ROOT_DIR=$CUDA_HOME
    export MAGMA_HOME="${PREFIX}"
else
    if [[ "$target_platform" == *-64 ]]; then
      export BLAS="MKL"
    fi
    export USE_CUDA=0
    export USE_MKLDNN=1
    export CMAKE_TOOLCHAIN_FILE="${RECIPE_DIR}/cross-linux.cmake"
fi

export CMAKE_BUILD_TYPE=Release

mkdir build
cd build
cmake ${CMAKE_ARGS} \
    -DCMAKE_GENERATOR=${CMAKE_GENERATOR} \
    -DCMAKE_LIBRARY_PATH="${CMAKE_LIBRARY_PATH}" \
    -DCMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH}" \
    -DINSTALL_TEST=${INSTALL_TEST} \
    -DBUILD_TEST=${BUILD_TEST} \
    -DUSE_SYSTEM_CPUINFO=${USE_SYSTEM_CPUINFO} \
    -DUSE_SYSTEM_SLEEF=${USE_SYSTEM_SLEEF} \
    -DUSE_SYSTEM_GLOO=${USE_SYSTEM_GLOO} \
    -DUSE_SYSTEM_FP16=${USE_SYSTEM_FP16} \
    -DUSE_SYSTEM_PYBIND11=${USE_SYSTEM_PYBIND11} \
    -DUSE_SYSTEM_PTHREADPOOL=${USE_SYSTEM_PTHREADPOOL} \
    -DUSE_SYSTEM_PSIMD=${USE_SYSTEM_PSIMD} \
    -DUSE_SYSTEM_FXDIV=${USE_SYSTEM_FXDIV} \
    -DUSE_SYSTEM_ONNX=${USE_SYSTEM_ONNX} \
    -DUSE_SYSTEM_XNNPACK=${USE_SYSTEM_XNNPACK} \
    -DBUILD_CUSTOM_PROTOBUF=${BUILD_CUSTOM_PROTOBUF} \
    -DBLAS=${BLAS} \
    -DUSE_CUDA=${USE_CUDA} \
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE} \
    -DBUILD_PYTHON=OFF \
    -DBUILD_BINARY=ON \
    ..

ninja install -j${CPU_COUNT}
# $PYTHON -m pip install . --no-deps -vvv --no-clean

