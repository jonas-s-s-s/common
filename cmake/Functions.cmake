# SmartCGMS - continuous glucose monitoring and controlling framework
# https://diabetes.zcu.cz/
#
# Copyright (c) since 2018 University of West Bohemia.
#
# Contact:
# diabetes@mail.kiv.zcu.cz
# Medical Informatics, Department of Computer Science and Engineering
# Faculty of Applied Sciences, University of West Bohemia
# Univerzitni 8, 301 00 Pilsen
# Czech Republic
# 
# 
# Purpose of this software:
# This software is intended to demonstrate work of the diabetes.zcu.cz research
# group to other scientists, to complement our published papers. It is strictly
# prohibited to use this software for diagnosis or treatment of any medical condition,
# without obtaining all required approvals from respective regulatory bodies.
#
# Especially, a diabetic patient is warned that unauthorized use of this software
# may result into severe injure, including death.
#
#
# Licensing terms:
# Unless required by applicable law or agreed to in writing, software
# distributed under these license terms is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#
# a) This file is available under the Apache License, Version 2.0.
# b) When publishing any derivative work or results obtained using this software, you agree to cite the following paper:
#    Tomas Koutny and Martin Ubl, "SmartCGMS as a Testbed for a Blood-Glucose Level Prediction and/or 
#    Control Challenge with (an FDA-Accepted) Diabetic Patient Simulation", Procedia Computer Science,  
#    Volume 177, pp. 354-362, 2020

# here we store globally required include paths and libs
SET(REQUIRED_INCLUDE_PATHS "" CACHE INTERNAL "")
SET(REQUIRED_LIBRARIES "" CACHE INTERNAL "")

# add include path
MACRO(PUSH_REQUIRED_INCLUDE_PATH INCL_PATH)
	SET(REQUIRED_INCLUDE_PATHS ${REQUIRED_INCLUDE_PATHS} ${INCL_PATH} CACHE INTERNAL "")
ENDMACRO()

# add required library
MACRO(PUSH_REQUIRED_LIBRARY LIB_PATH)
	SET(REQUIRED_LIBRARIES ${REQUIRED_LIBRARIES} ${LIB_PATH} CACHE INTERNAL "")
ENDMACRO()

# discovers dependencies relevant to the whole SmartCGMS system
FUNCTION(DISCOVER_DEPENDENCIES)
	# find scgms-common library; if built within project, append it; otherwise we need to know the location from configuration parameters
	IF(TARGET scgms-common)
		MESSAGE(STATUS "The scgms-common library is build within solution and will be linked automatically")
	ELSE()
		SET(SCGMS_COMMON_LIB "" CACHE PATH "SmartCGMS 'common' (scgms-common) library directory path")
		LINK_DIRECTORIES(${SCGMS_COMMON_LIB})
	ENDIF()

	# find threads library (pthreads on GNU/Linux and macOS) and link it
	FIND_PACKAGE(Threads REQUIRED)
	PUSH_REQUIRED_LIBRARY("${CMAKE_THREAD_LIBS_INIT}")

	# Eigen3 - this library is widely used in whole SmartCGMS, thus required
	SET(EIGEN3_INCLUDE "" CACHE PATH "Eigen3 header files location")
	PUSH_REQUIRED_INCLUDE_PATH("${EIGEN3_INCLUDE}")

	# default: do not link stdc++ filesystem support; several environments provide filesystem techspec implementation in a separate library (gcc, clang)
	SET(LINK_STDCPPFS FALSE)

	IF (${CMAKE_CXX_COMPILER_ID} STREQUAL "GNU" OR ${CMAKE_CXX_COMPILER_ID} MATCHES "Clang")

		# gcc's std::filesystem is incomplete and buggy
		IF ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU" AND CMAKE_CXX_COMPILER_VERSION VERSION_LESS_EQUAL 11.0)
			ADD_DEFINITIONS(-DSTDCPP_FS_DISABLED)
			SET(LINK_STDCPPFS FALSE)
		# Android NDK does not support C++ std::filesystem as of version r21c
		ELSEIF (ANDROID)
			SET(LINK_STDCPPFS FALSE)
		# AppleClang includes stdc++fs as a part of standard library
		ELSEIF ("${CMAKE_CXX_COMPILER_ID}" MATCHES "Apple" AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 11.0)
			SET(LINK_STDCPPFS FALSE)
		# default: link stdc++fs
		ELSE()
			SET(LINK_STDCPPFS TRUE)
		ENDIF()

		# on GCC and Clang, we need to add libdl and and libm
		PUSH_REQUIRED_LIBRARY("${CMAKE_DL_LIBS}")
		PUSH_REQUIRED_LIBRARY("m")
	ENDIF()

	IF(LINK_STDCPPFS)
		PUSH_REQUIRED_LIBRARY("stdc++fs")
	ENDIF()

	IF("${CMAKE_SYSTEM_PROCESSOR}" MATCHES ".*armv7.*" OR "${CMAKE_SYSTEM_PROCESSOR}" MATCHES ".*armv6.*")
		MESSAGE("Warning: linking against libatomic, the host processor does not support atomic instructions")
		PUSH_REQUIRED_LIBRARY("atomic")
	ENDIF()
ENDFUNCTION()

SET(Qt_REQUIRED FALSE)
SET(Qt_INCLUDE_PATHS )

# discovers Qt with given components
FUNCTION(DISCOVER_QT_LIBRARY)

	SET(Qt6_COMPONENT_REQUEST ${ARGV})
	SET(Qt5_COMPONENT_REQUEST ${ARGV})

	FOREACH(arg IN LISTS ARGV)
        IF("Svg" STREQUAL ${arg})
			SET(Qt6_COMPONENT_REQUEST "${Qt6_COMPONENT_REQUEST};SvgWidgets")
            BREAK()
        ENDIF()
    ENDFOREACH()

	FIND_PACKAGE(Qt6 QUIET COMPONENTS ${Qt6_COMPONENT_REQUEST})
	IF(Qt6_FOUND)
		SET(Qt_INCLUDE_PATHS ${Qt6Core_INCLUDE_DIRS} ${Qt6Sql_INCLUDE_DIRS})
		SET(Qt_MAJOR_VERSION 6 CACHE INTERNAL "Qt major version")
	ELSE()
		FIND_PACKAGE(Qt5 5.15 QUIET COMPONENTS ${Qt5_COMPONENT_REQUEST})
		IF(Qt5_FOUND)
			SET(Qt_INCLUDE_PATHS ${Qt5Core_INCLUDE_DIRS} ${Qt5Sql_INCLUDE_DIRS})
			SET(Qt_MAJOR_VERSION 5 CACHE INTERNAL "Qt major version")
		ELSE()	
			MESSAGE(WARNING "No Qt5 or Qt6 installation found!")
			SET(Qt_REQUIRED FALSE)
			ADD_DEFINITIONS(-DDO_NOT_USE_QT -DNOGUI)
		ENDIF()
	ENDIF()
ENDFUNCTION()

# applies global settings to SmartCGMS libraries
FUNCTION(APPLY_SCGMS_LIBRARY_BUILD_SETTINGS TARGET_NAME)
	SET_PROPERTY(TARGET ${TARGET_NAME} PROPERTY CXX_STANDARD 20)
	SET_PROPERTY(TARGET ${TARGET_NAME} PROPERTY CXX_STANDARD_REQUIRED On)
	SET_PROPERTY(TARGET ${TARGET_NAME} PROPERTY CXX_EXTENSIONS Off)
	
	IF(Qt_REQUIRED)
		PUSH_REQUIRED_INCLUDE_PATH(${Qt_INCLUDE_PATHS})
	ENDIF()
	
	TARGET_LINK_LIBRARIES(${TARGET_NAME} ${REQUIRED_LIBRARIES})
	TARGET_INCLUDE_DIRECTORIES(${TARGET_NAME} PUBLIC ${REQUIRED_INCLUDE_PATHS})
	
	SET(TARGET_COMPILE_FLAGS )
	SET(TARGET_COMPILE_FLAGS_RELEASE )
	SET(TARGET_COMPILE_FLAGS_DEBUG )
	
	# Win32/MSVC build flags
	IF(WIN32)
		# On Windows, use /bigobj flag to avoid linker limitation errors on common obj format
		SET(TARGET_COMPILE_FLAGS /bigobj)
	ENDIF(WIN32)
	
	# GCC/clang build flags
	IF(${CMAKE_CXX_COMPILER_ID} STREQUAL "GNU" OR ${CMAKE_CXX_COMPILER_ID} MATCHES "Clang")
		# append gcc+clang specific flags - report all warnings except the ones we acknowledged
		# -Wno-ignored-attributes, -Wno-unused-parameter - we decided not to follow these rules
		# -Wno-deprecated-declarations - mostly because of 3rd party libraries and their interfaces
		# -Wno-unknown-pragmas - this is due to "disable warning" pragma we use to suppress ugly warnings on MSVS
		ADD_COMPILE_OPTIONS(-Wall -Wextra -Wno-ignored-attributes -Wno-unused-parameter -fPIC)
		ADD_COMPILE_OPTIONS(-Wno-ignored-attributes -Wno-deprecated-declarations -Wno-deprecated-copy -Wno-unknown-pragmas)

		# gcc reports a specific use case of copy semantics as deprecated, unlike Clang
		IF ("${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU")
			ADD_COMPILE_OPTIONS(-Wimplicit-fallthrough=0)
			ADD_COMPILE_OPTIONS(-Wno-deprecated-copy -Wno-class-memaccess)
		ENDIF()

		# debug build = no optimization, add debug symbols
		LIST(APPEND TARGET_COMPILE_FLAGS_DEBUG -g)
		IF (BUILDOPT_DEVEL)
			# append debug symbols even if explicitly requested)
			LIST(APPEND TARGET_COMPILE_FLAGS_RELEASE -g)
		ENDIF()

		# release build = maximum optimization, use all available mechanisms for given platform/architecture
		IF (ANDROID)
			# do not optimize with march=native when cross-compiling for Android
			LIST(APPEND TARGET_COMPILE_FLAGS_RELEASE -O3)
		ELSE()
			LIST(APPEND TARGET_COMPILE_FLAGS_RELEASE -O3 -march=native)
		ENDIF()
	ENDIF()
	
	IF(WIN32)
		SEPARATE_ARGUMENTS(TARGET_COMPILE_FLAGS_STR WINDOWS_COMMAND "${TARGET_COMPILE_FLAGS}")
		SEPARATE_ARGUMENTS(TARGET_COMPILE_FLAGS_DEBUG_STR WINDOWS_COMMAND "${TARGET_COMPILE_FLAGS_DEBUG}")
		SEPARATE_ARGUMENTS(TARGET_COMPILE_FLAGS_RELEASE_STR WINDOWS_COMMAND "${TARGET_COMPILE_FLAGS_RELEASE}")
	ELSE()
		SEPARATE_ARGUMENTS(TARGET_COMPILE_FLAGS_STR UNIX_COMMAND "${TARGET_COMPILE_FLAGS}")
		SEPARATE_ARGUMENTS(TARGET_COMPILE_FLAGS_DEBUG_STR UNIX_COMMAND "${TARGET_COMPILE_FLAGS_DEBUG}")
		SEPARATE_ARGUMENTS(TARGET_COMPILE_FLAGS_RELEASE_STR UNIX_COMMAND "${TARGET_COMPILE_FLAGS_RELEASE}")
	ENDIF()
	
	TARGET_COMPILE_OPTIONS(${TARGET_NAME} PUBLIC ${TARGET_COMPILE_FLAGS_STR})
	TARGET_COMPILE_OPTIONS(${TARGET_NAME} PUBLIC $<$<CONFIG:DEBUG>:${TARGET_COMPILE_FLAGS_DEBUG_STR}>)
	TARGET_COMPILE_OPTIONS(${TARGET_NAME} PUBLIC $<$<CONFIG:RELEASE>:${TARGET_COMPILE_FLAGS_RELEASE_STR}>)
ENDFUNCTION()

# macro for searching through directory for subdirectories
MACRO(SUBDIRLIST result curdir)
	FILE(GLOB children RELATIVE ${curdir} ${curdir}/*)
	SET(dirlist "")
	FOREACH(child ${children})
		IF(IS_DIRECTORY ${curdir}/${child})
			LIST(APPEND dirlist ${child})
		ENDIF()
	ENDFOREACH()
	SET(${result} ${dirlist})
ENDMACRO()

# remembered libraries and executables
SET(TARGETS_EXECUTABLES )
SET(TARGETS_LIBRARIES )

# add new executable, the buildsystem remembers the executable so it can e.g., clone it later for multiple configurations
MACRO(SCGMS_ADD_EXECUTABLE TARGET_NAME)
	ADD_EXECUTABLE(${ARGV})
	LIST(APPEND TARGETS_EXECUTABLES ${TARGET_NAME} CACHE INTERNAL "" FORCE)
ENDMACRO()
# add new library (filter or other)
MACRO(SCGMS_ADD_LIBRARY TARGET_NAME)
	ADD_LIBRARY(${ARGV})
	LIST(APPEND TARGETS_LIBRARIES ${TARGET_NAME} CACHE INTERNAL "" FORCE)
ENDMACRO()

# link common libraries
MACRO(SCGMS_LINK_COMMON_LIBRARIES TARGET_NAME)
	TARGET_LINK_LIBRARIES(${TARGET_NAME} scgms-common)
	
	# link TBB as parallelism backend on MacOS, or when using clang as a compiler except on Windows
	SET(USE_TBB OFF)
	IF (${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
		SET(USE_TBB ON)
	ELSE()
		IF (CMAKE_CXX_COMPILER_ID STREQUAL "Clang" OR CMAKE_CXX_COMPILER_ID STREQUAL "Intel")
			SET(USE_TBB ON)
		ENDIF()
	ENDIF()

	IF (USE_TBB)
		TARGET_LINK_LIBRARIES(${TARGET_NAME} tbb)
	ENDIF()
ENDMACRO()

SET(OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/compiled/" CACHE PATH "Where to store compiled binaries")

# function to configure output parameters of common target according to project settings
FUNCTION(CONFIGURE_BASE_LIB_OUTPUT PROJNAME)
	# single-configuration environments (GCC, ..)
	SET_TARGET_PROPERTIES(${PROJNAME}
		PROPERTIES
		ARCHIVE_OUTPUT_DIRECTORY "${OUTPUT_DIRECTORY}/"
		LIBRARY_OUTPUT_DIRECTORY "${OUTPUT_DIRECTORY}/"
		RUNTIME_OUTPUT_DIRECTORY "${OUTPUT_DIRECTORY}/"
	)
	# multi-configuration environments (MSVS, ..)
	FOREACH(OUTPUTCONFIG ${CMAKE_CONFIGURATION_TYPES})
		SET(ORIG_OUT_CONFIG ${OUTPUTCONFIG})
		STRING(TOUPPER ${OUTPUTCONFIG} OUTPUTCONFIG)
		SET_TARGET_PROPERTIES(${PROJNAME}
			PROPERTIES
			ARCHIVE_OUTPUT_DIRECTORY_${OUTPUTCONFIG} "${OUTPUT_DIRECTORY}/${ORIG_OUT_CONFIG}/"
			LIBRARY_OUTPUT_DIRECTORY_${OUTPUTCONFIG} "${OUTPUT_DIRECTORY}/${ORIG_OUT_CONFIG}/"
			RUNTIME_OUTPUT_DIRECTORY_${OUTPUTCONFIG} "${OUTPUT_DIRECTORY}/${ORIG_OUT_CONFIG}/"
		)
	ENDFOREACH(OUTPUTCONFIG CMAKE_CONFIGURATION_TYPES)
ENDFUNCTION()

# function to configure output parameters of common target according to project settings
FUNCTION(CONFIGURE_FILTER_OUTPUT PROJNAME)
	# single-configuration environments (GCC, ..)
	SET_TARGET_PROPERTIES(${PROJNAME}
		PROPERTIES
		ARCHIVE_OUTPUT_DIRECTORY "${OUTPUT_DIRECTORY}/filters"
		LIBRARY_OUTPUT_DIRECTORY "${OUTPUT_DIRECTORY}/filters"
		RUNTIME_OUTPUT_DIRECTORY "${OUTPUT_DIRECTORY}/filters"
	)
	# multi-configuration environments (MSVS, ..)
	FOREACH(OUTPUTCONFIG ${CMAKE_CONFIGURATION_TYPES})
		SET(ORIG_OUT_CONFIG ${OUTPUTCONFIG})
		STRING(TOUPPER ${OUTPUTCONFIG} OUTPUTCONFIG)
		SET_TARGET_PROPERTIES(${PROJNAME}
			PROPERTIES
			ARCHIVE_OUTPUT_DIRECTORY_${OUTPUTCONFIG} "${OUTPUT_DIRECTORY}/${ORIG_OUT_CONFIG}/filters"
			LIBRARY_OUTPUT_DIRECTORY_${OUTPUTCONFIG} "${OUTPUT_DIRECTORY}/${ORIG_OUT_CONFIG}/filters"
			RUNTIME_OUTPUT_DIRECTORY_${OUTPUTCONFIG} "${OUTPUT_DIRECTORY}/${ORIG_OUT_CONFIG}/filters"
		)
	ENDFOREACH(OUTPUTCONFIG CMAKE_CONFIGURATION_TYPES)
	
	IF(TARGET desktop)
		ADD_DEPENDENCIES(desktop ${PROJNAME})
	ENDIF()
	IF(TARGET console)
		ADD_DEPENDENCIES(console ${PROJNAME})
	ENDIF()
ENDFUNCTION()

# function to configure output parameters of common target according to project settings
FUNCTION(CONFIGURE_TARGET_OUTPUT PROJNAME OUTDIRNAME)
	# single-configuration environments (GCC, ..)
	SET_TARGET_PROPERTIES(${PROJNAME}
		PROPERTIES
		ARCHIVE_OUTPUT_DIRECTORY "${OUTPUT_DIRECTORY}/${OUTDIRNAME}"
		LIBRARY_OUTPUT_DIRECTORY "${OUTPUT_DIRECTORY}/${OUTDIRNAME}"
		RUNTIME_OUTPUT_DIRECTORY "${OUTPUT_DIRECTORY}/${OUTDIRNAME}"
	)
	# multi-configuration environments (MSVS, ..)
	FOREACH(OUTPUTCONFIG ${CMAKE_CONFIGURATION_TYPES})
		SET(ORIG_OUT_CONFIG ${OUTPUTCONFIG})
		STRING(TOUPPER ${OUTPUTCONFIG} OUTPUTCONFIG)
		SET_TARGET_PROPERTIES(${PROJNAME}
			PROPERTIES
			ARCHIVE_OUTPUT_DIRECTORY_${OUTPUTCONFIG} "${OUTPUT_DIRECTORY}/${ORIG_OUT_CONFIG}/${OUTDIRNAME}"
			LIBRARY_OUTPUT_DIRECTORY_${OUTPUTCONFIG} "${OUTPUT_DIRECTORY}/${ORIG_OUT_CONFIG}/${OUTDIRNAME}"
			RUNTIME_OUTPUT_DIRECTORY_${OUTPUTCONFIG} "${OUTPUT_DIRECTORY}/${ORIG_OUT_CONFIG}/${OUTDIRNAME}"
		)
	ENDFOREACH(OUTPUTCONFIG CMAKE_CONFIGURATION_TYPES)
ENDFUNCTION()

# function to configure output parameters of common target according to project settings
FUNCTION(CONFIGURE_ROOT_TARGET_OUTPUT PROJNAME)
	CONFIGURE_TARGET_OUTPUT(${PROJNAME} "")
ENDFUNCTION()

# Set generic library variables, since Windows, Linux and Mac have different conventions for library naming
IF(WIN32)
	SET(LIB_PREFIX_STATIC "")
	SET(LIB_SUFFIX_STATIC ".lib")
	SET(LIB_SUFFIX_DYNAMIC ".dll")
ELSEIF(APPLE)
	SET(LIB_PREFIX_STATIC "lib")
	SET(LIB_SUFFIX_STATIC ".a")
	SET(LIB_SUFFIX_DYNAMIC ".dylib")
	SET(CMAKE_MACOSX_RPATH 1)
ELSE()
	SET(LIB_PREFIX_STATIC "lib")
	SET(LIB_SUFFIX_STATIC ".a")
	SET(LIB_SUFFIX_DYNAMIC ".so")
ENDIF()

# generic library config for imported libraries - takes library name, path and flag if the library is static or shared
FUNCTION(GEN_LIBCONF LIBNAME LIBPATH ISSTATIC)
	IF(${ISSTATIC})
		SET(INCMODE STATIC)
		SET(LIB_SUFFIX ${LIB_SUFFIX_STATIC})
	ELSE()
		SET(INCMODE SHARED)
		SET(LIB_SUFFIX ${LIB_SUFFIX_DYNAMIC})
	ENDIF()
	ADD_LIBRARY(${LIBNAME} ${INCMODE} IMPORTED GLOBAL)
	SET_TARGET_PROPERTIES(${LIBNAME} PROPERTIES IMPORTED_LOCATION "${LIBPATH}/${LIB_PREFIX_STATIC}${LIBNAME}${LIB_SUFFIX}")
	SET_TARGET_PROPERTIES(${LIBNAME} PROPERTIES IMPORTED_LOCATION_DEBUG "${LIBPATH}/${LIB_PREFIX_STATIC}${LIBNAME}${LIB_SUFFIX}")
	SET_TARGET_PROPERTIES(${LIBNAME} PROPERTIES IMPORTED_LOCATION_RELEASE "${LIBPATH}/${LIB_PREFIX_STATIC}${LIBNAME}${LIB_SUFFIX}")
	
	IF(APPLE)
		SET(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_RPATH};${LIBPATH}")
	ENDIF()
ENDFUNCTION()

# generic library config for imported libraries, for which their version (debug vs. release) is determined by attached "d"
FUNCTION(GEN_LIBCONF_D LIBNAME LIBPATH ISSTATIC)
        IF(${ISSTATIC})
                SET(INCMODE STATIC)
                SET(LIB_SUFFIX ${LIB_SUFFIX_STATIC})
        ELSE()
                SET(INCMODE SHARED)
                SET(LIB_SUFFIX ${LIB_SUFFIX_DYNAMIC})
        ENDIF()
	ADD_LIBRARY(${LIBNAME} ${INCMODE} IMPORTED GLOBAL)
	SET_TARGET_PROPERTIES(${LIBNAME} PROPERTIES IMPORTED_LOCATION "${LIBPATH}/${LIB_PREFIX_STATIC}${LIBNAME}${LIB_SUFFIX}")
	SET_TARGET_PROPERTIES(${LIBNAME} PROPERTIES IMPORTED_LOCATION_DEBUG "${LIBPATH}/${LIB_PREFIX_STATIC}${LIBNAME}d${LIB_SUFFIX}")
	SET_TARGET_PROPERTIES(${LIBNAME} PROPERTIES IMPORTED_LOCATION_RELEASE "${LIBPATH}/${LIB_PREFIX_STATIC}${LIBNAME}${LIB_SUFFIX}")
	
	IF(APPLE)
		SET(CMAKE_INSTALL_RPATH "${CMAKE_INSTALL_RPATH};${LIBPATH}")
	ENDIF()
ENDFUNCTION()
