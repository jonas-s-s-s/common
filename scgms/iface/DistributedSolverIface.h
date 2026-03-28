#pragma once

#include "SolverIface.h"

namespace solver
{
    class TDistributedSolver_Setup final : TSolver_Setup
    {
    public:
        TDistributedSolver_Setup(size_t problem_size, size_t objectives_count, const double* lower_bound,
                                 const double* upper_bound, const double** hints, size_t hint_count, double* solution,
                                 const void* data,
                                 TObjective_Function objective, TFitness_Comparator comparator, size_t max_generations,
                                 size_t population_size, double tolerance, const std::string& solver_lib_name,
                                 const std::string& controller_address, size_t expected_worker_count)
            : TSolver_Setup(
                  problem_size, objectives_count, lower_bound, upper_bound, hints, hint_count, solution, data, objective
                  , comparator, max_generations, population_size, tolerance),
              solver_lib_name(solver_lib_name),
              controller_address(controller_address),
              expected_worker_count(expected_worker_count)
        {
        }

        const std::string solver_lib_name;
        const std::string controller_address;
        const size_t expected_worker_count;
    };
}
