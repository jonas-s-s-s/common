#pragma once

#include "SolverIface.h"

namespace solver
{
    /**
     * Serves as a wrapper for distributed solver's extra parameters
     * We simply assign this to the "data" field of the original TSolver_Setup struct
     *
     * Another alternative could be to make TSolver_Setup polymorphic and derive this class from it, however the current
     * approach seems to be less invasive and has less potential for breaking existing code.
     */
    struct TDistributedSolver_Data
    {
        const std::string solver_lib_name;
        const std::string controller_address;
        const size_t expected_worker_count;

        // Original data that'd be normally contained inside TSolver_Setup
        const void *solverData;
    };
}
