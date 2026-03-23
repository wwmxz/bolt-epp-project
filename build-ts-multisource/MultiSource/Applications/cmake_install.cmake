# Install script for directory: /home/common/compiler/bolt-epp-test/llvm-test-suite/MultiSource/Applications

# Set the install prefix
if(NOT DEFINED CMAKE_INSTALL_PREFIX)
  set(CMAKE_INSTALL_PREFIX "/usr/local")
endif()
string(REGEX REPLACE "/$" "" CMAKE_INSTALL_PREFIX "${CMAKE_INSTALL_PREFIX}")

# Set the install configuration name.
if(NOT DEFINED CMAKE_INSTALL_CONFIG_NAME)
  if(BUILD_TYPE)
    string(REGEX REPLACE "^[^A-Za-z0-9_]+" ""
           CMAKE_INSTALL_CONFIG_NAME "${BUILD_TYPE}")
  else()
    set(CMAKE_INSTALL_CONFIG_NAME "Release")
  endif()
  message(STATUS "Install configuration: \"${CMAKE_INSTALL_CONFIG_NAME}\"")
endif()

# Set the component getting installed.
if(NOT CMAKE_INSTALL_COMPONENT)
  if(COMPONENT)
    message(STATUS "Install component: \"${COMPONENT}\"")
    set(CMAKE_INSTALL_COMPONENT "${COMPONENT}")
  else()
    set(CMAKE_INSTALL_COMPONENT)
  endif()
endif()

# Install shared libraries without execute permission?
if(NOT DEFINED CMAKE_INSTALL_SO_NO_EXE)
  set(CMAKE_INSTALL_SO_NO_EXE "1")
endif()

# Is this installation the result of a crosscompile?
if(NOT DEFINED CMAKE_CROSSCOMPILING)
  set(CMAKE_CROSSCOMPILING "FALSE")
endif()

# Set default install directory permissions.
if(NOT DEFINED CMAKE_OBJDUMP)
  set(CMAKE_OBJDUMP "/usr/bin/objdump")
endif()

if(NOT CMAKE_INSTALL_LOCAL_ONLY)
  # Include the install script for each subdirectory.
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/JM/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/SIBsim4/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/aha/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/d/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/oggenc/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/sgefa/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/spiff/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/viterbi/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/ALAC/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/hbd/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/lambda-0.1.3/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/minisat/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/hexxagon/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/lua/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/obsequi/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/kimwitu++/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/SPASS/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/ClamAV/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/lemon/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/siod/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/sqlite3/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/Burg/cmake_install.cmake")
  include("/home/common/compiler/bolt-epp-test/build-ts-multisource/MultiSource/Applications/treecc/cmake_install.cmake")

endif()

