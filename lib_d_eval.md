#+TITLE:  lib_d_eval (2018-07 and later)
#+AUTHOR: Guillaume Lathoud
#+OPTIONS: ^:{}
# -*- coding: utf-8 -*-
# To refresh and open HTML:   M-x org-html-export-to-html

* build LDC with shared libraries (esp. Phobos)
Use LDC's ldmd2, a wrapper script for ldc2 which converts argument
formats from dmd style over to ldc style.

Requirement: LDC compiled with shared libs, especially Phobos

Example:

https://forum.dlang.org/thread/lbrfycmutwrrghtzazin@forum.dlang.org?page=3

This is a fresh build on Ubuntu 14.04 with cmake called via:

    cmake -DCMAKE_INSTALL_PREFIX=/opt/ldc -DBUILD_SHARED_LIBS=ON ..

.

so here we go

https://wiki.dlang.org/Building_LDC_from_source

#+BEGIN_SRC sh

  # tools

  sudo apt install cmake

  #https://github.com/ninja-build/ninja/wiki/Pre-built-Ninja-packages
  sudo apt install ninja-build

  # llvm (slightly tweaked by the LDC guys)

  cd ~/d/glathoud/software
  mkdir ldc-llvm5-tweak
  cd ldc-llvm5-tweak

  curl -L -O https://github.com/ldc-developers/llvm/releases/download/ldc-v5.0.1/llvm-5.0.1.src.tar.xz
  tar xf llvm-5.0.1.src.tar.xz
  cd llvm-5.0.1.src/
  mkdir build && cd build/

  cmake -GNinja .. -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD="X86;AArch64;ARM;PowerPC;NVPTX" -DLLVM_BUILD_TOOLS=OFF -DLLVM_BUILD_UTILS=OFF # remove -GNinja to use Make instead
  
  cd ../../../

  # now LDC itself
  # 
  # looked there: https://github.com/ldc-developers/ldc/releases
  # for the latest stable release

  mkdir ldc-1.10.0  &&  cd ldc-1.10.0
  curl -L -O https://github.com/ldc-developers/ldc/releases/download/v1.10.0/ldc-1.10.0-src.tar.gz
  tar xf ldc-1.10.0-src.tar.gz

  cd ldc-1.10.0-src/
  mkdir ~/other2/software 2>>/dev/null
  mkdir build  &&  cd build
  cmake -G Ninja -DLLVM_CONFIG=../../../ldc-llvm5-tweak/llvm-5.0.1.src/build/bin/llvm-config -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX=~/other2/software/ldc ..

  # Build and install LDC. Use -j<n> to limit parallelism if running out of memory.
  ninja
  sudo ninja install
#+END_SRC

