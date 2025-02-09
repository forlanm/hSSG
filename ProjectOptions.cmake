include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(hSSG_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(hSSG_setup_options)
  option(hSSG_ENABLE_HARDENING "Enable hardening" ON)
  option(hSSG_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    hSSG_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    hSSG_ENABLE_HARDENING
    OFF)

  hSSG_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR hSSG_PACKAGING_MAINTAINER_MODE)
    option(hSSG_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(hSSG_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(hSSG_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(hSSG_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(hSSG_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(hSSG_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(hSSG_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(hSSG_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(hSSG_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(hSSG_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(hSSG_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(hSSG_ENABLE_PCH "Enable precompiled headers" OFF)
    option(hSSG_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(hSSG_ENABLE_IPO "Enable IPO/LTO" ON)
    option(hSSG_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(hSSG_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(hSSG_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(hSSG_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(hSSG_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(hSSG_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(hSSG_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(hSSG_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(hSSG_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(hSSG_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(hSSG_ENABLE_PCH "Enable precompiled headers" OFF)
    option(hSSG_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      hSSG_ENABLE_IPO
      hSSG_WARNINGS_AS_ERRORS
      hSSG_ENABLE_USER_LINKER
      hSSG_ENABLE_SANITIZER_ADDRESS
      hSSG_ENABLE_SANITIZER_LEAK
      hSSG_ENABLE_SANITIZER_UNDEFINED
      hSSG_ENABLE_SANITIZER_THREAD
      hSSG_ENABLE_SANITIZER_MEMORY
      hSSG_ENABLE_UNITY_BUILD
      hSSG_ENABLE_CLANG_TIDY
      hSSG_ENABLE_CPPCHECK
      hSSG_ENABLE_COVERAGE
      hSSG_ENABLE_PCH
      hSSG_ENABLE_CACHE)
  endif()

  hSSG_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (hSSG_ENABLE_SANITIZER_ADDRESS OR hSSG_ENABLE_SANITIZER_THREAD OR hSSG_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(hSSG_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(hSSG_global_options)
  if(hSSG_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    hSSG_enable_ipo()
  endif()

  hSSG_supports_sanitizers()

  if(hSSG_ENABLE_HARDENING AND hSSG_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR hSSG_ENABLE_SANITIZER_UNDEFINED
       OR hSSG_ENABLE_SANITIZER_ADDRESS
       OR hSSG_ENABLE_SANITIZER_THREAD
       OR hSSG_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${hSSG_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${hSSG_ENABLE_SANITIZER_UNDEFINED}")
    hSSG_enable_hardening(hSSG_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(hSSG_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(hSSG_warnings INTERFACE)
  add_library(hSSG_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  hSSG_set_project_warnings(
    hSSG_warnings
    ${hSSG_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(hSSG_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    hSSG_configure_linker(hSSG_options)
  endif()

  include(cmake/Sanitizers.cmake)
  hSSG_enable_sanitizers(
    hSSG_options
    ${hSSG_ENABLE_SANITIZER_ADDRESS}
    ${hSSG_ENABLE_SANITIZER_LEAK}
    ${hSSG_ENABLE_SANITIZER_UNDEFINED}
    ${hSSG_ENABLE_SANITIZER_THREAD}
    ${hSSG_ENABLE_SANITIZER_MEMORY})

  set_target_properties(hSSG_options PROPERTIES UNITY_BUILD ${hSSG_ENABLE_UNITY_BUILD})

  if(hSSG_ENABLE_PCH)
    target_precompile_headers(
      hSSG_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(hSSG_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    hSSG_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(hSSG_ENABLE_CLANG_TIDY)
    hSSG_enable_clang_tidy(hSSG_options ${hSSG_WARNINGS_AS_ERRORS})
  endif()

  if(hSSG_ENABLE_CPPCHECK)
    hSSG_enable_cppcheck(${hSSG_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(hSSG_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    hSSG_enable_coverage(hSSG_options)
  endif()

  if(hSSG_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(hSSG_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(hSSG_ENABLE_HARDENING AND NOT hSSG_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR hSSG_ENABLE_SANITIZER_UNDEFINED
       OR hSSG_ENABLE_SANITIZER_ADDRESS
       OR hSSG_ENABLE_SANITIZER_THREAD
       OR hSSG_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    hSSG_enable_hardening(hSSG_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
