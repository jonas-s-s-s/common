/**
 * SmartCGMS - continuous glucose monitoring and controlling framework
 * https://diabetes.zcu.cz/
 *
 * Copyright (c) since 2018 University of West Bohemia.
 *
 * Contact:
 * diabetes@mail.kiv.zcu.cz
 * Medical Informatics, Department of Computer Science and Engineering
 * Faculty of Applied Sciences, University of West Bohemia
 * Univerzitni 8, 301 00 Pilsen
 * Czech Republic
 * 
 * 
 * Purpose of this software:
 * This software is intended to demonstrate work of the diabetes.zcu.cz research
 * group to other scientists, to complement our published papers. It is strictly
 * prohibited to use this software for diagnosis or treatment of any medical condition,
 * without obtaining all required approvals from respective regulatory bodies.
 *
 * Especially, a diabetic patient is warned that unauthorized use of this software
 * may result into severe injure, including death.
 *
 *
 * Licensing terms:
 * Unless required by applicable law or agreed to in writing, software
 * distributed under these license terms is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *
 * a) This file is available under the Apache License, Version 2.0.
 * b) When publishing any derivative work or results obtained using this software, you agree to cite the following paper:
 *    Tomas Koutny and Martin Ubl, "SmartCGMS as a Testbed for a Blood-Glucose Level Prediction and/or 
 *    Control Challenge with (an FDA-Accepted) Diabetic Patient Simulation", Procedia Computer Science,  
 *    Volume 177, pp. 354-362, 2020
 */

#pragma once

#include "FilterIface.h"

#undef min

namespace solver {
	/* maximum number of objectives the solver may use */
	constexpr size_t Maximum_Objectives_Count = 10;

	using TFitness = std::array<double, solver::Maximum_Objectives_Count>;

	/* a container to propagate solver progress to outer code */
	struct TSolver_Progress {
		/* current solver progress (always less or equal max_progress); minimum progress is 0 */
		size_t current_progress;
		/* maximum progress (e.g., maximum number of generations or solver steps) */
		size_t max_progress;
		/* container of best achieved metrics */
		TFitness best_metric;
		/* cancelled flag; if the outer code sets this to TRUE, the solver cancels the operation in its nearest convenience */
		BOOL cancelled;
	};

	const TFitness Nan_Fitness = { std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::quiet_NaN() };
	const TFitness Max_Fitness = { std::numeric_limits<double>::max(), std::numeric_limits<double>::max(), std::numeric_limits<double>::max(), std::numeric_limits<double>::max(), std::numeric_limits<double>::max(), std::numeric_limits<double>::max(), std::numeric_limits<double>::max(), std::numeric_limits<double>::max(), std::numeric_limits<double>::max(), std::numeric_limits<double>::max() };
	const TSolver_Progress Null_Solver_Progress = { 0, 0, Nan_Fitness, 0 };
	
	/* Fitness comparator to compare fitnesses during multi-criterial optimalization
	 * better and worse are arrays of fitnesses of two respective parameter sets, objective_count is a size of these arrays
	 * returns TRUE if better is truly better than worse, FALSE otherwise
	 */
	using TFitness_Comparator = BOOL(IfaceCalling*)(const double* better, const double* worse, const size_t objective_count);

	/* Objective function pointer
	 * data is an opaque handler for arbitrary data (e.g., for stateful evaluation)
	 * count is the number of solutions - they are laid one after one in 1D/fixed-size array
	 * solution points to the first candidate solution, increase the pointer by n*sizeof(double)*problem_size bytes to read n-th solution
	 * fitness is an array where to store up to Maximum_Objective_Count, also laid in 1D/fixed-size array, thus increase the pointer by n*solver::Maximum_Objectives_Count*sizeof(double) bytes to write n-th fitness
	 * returns TRUE (success) or FALSE (there was an error) */
	using TObjective_Function = BOOL(IfaceCalling*)(const void *data, const size_t count, const double *solution, double * const fitness);

	/* solver setup container */
	struct TSolver_Setup {
		/* size of the problem, e.g., number of parameters */
		const size_t problem_size;
		/* count of objectives to consider (always less or equal to Maximum_Objectives_Count */
		const size_t objectives_count;
		/* parameter lower bounds */
		const double* lower_bound;
		/* parameter upper bounds */
		const double* upper_bound;
		/* parameter hints - an array of previously solved or default parameters */
		const double **hints;
		/* size of hints array */
		const size_t hint_count;
		/* a pointer to a sufficiently large array of doubles, where the solver stores the solution */
		double * const solution;

		/* arbitrary data pointer (for e.g., stateful evaluation) */
		const void *data;
		/* pointer to objective function; cannot be nullptr */
		const TObjective_Function objective;
		/* fitness comparator for multi-criterial evaluation; can be nullptr, solver will then use its default comparator */
		const TFitness_Comparator comparator;

		/* maximum number of generations for generation-based solvers (where relevant); zero for default value of given solver */
		const size_t max_generations;
		/* maximum number of population members for population-based solvers (where relevant); zero for default value of given solver */
		const size_t population_size;
		/* tolerance indicating no further improvement between steps (where relevant) */
		const double tolerance;
	};

	const TSolver_Setup Default_Solver_Setup = { 0, 0, nullptr, nullptr, nullptr, 0, nullptr, nullptr, nullptr, nullptr, 0, 0, std::numeric_limits<double>::min() };
	using TGeneric_Solver = HRESULT(IfaceCalling*)(const GUID *solver_id, const TSolver_Setup *setup, TSolver_Progress *progress);
}

namespace scgms {

	/* parameters of metric to use during solve */
	struct TMetric_Parameters {
		/* metric GUID */
		const GUID metric_id;
			//any metric can ignore the parameters below as seen fit as e.g., AIC or Leal_2010 are not compatible with all the options

		/* should the metric use relative error? can be ignored by the metric, if the metric does not support it */
		const unsigned char use_relative_error;
		/* should the metric use squared differences? can be ignored by the metric, if the metric does not support it */
		const unsigned char use_squared_differences;
		/* should the result be once more divided by the value count? can be ignored by the metric, if the metric does not support it */
		const unsigned char prefer_more_levels;
		/* metric threshold; this parameter depends on the used metric, the caller is responsible for providing the metric with a correct value */
		const double threshold;
	};

	const TMetric_Parameters Null_Metric_Parameters = { Invalid_GUID, 0, 0, 0, 0.0 };

	/* metric interface */
	class IMetric: public virtual refcnt::IReferenced {
		public:
			/* accumulates next batch of levels - the calculator processes a batch of differences
			 * count is the number of elements of differences, which are encoded as vectors to exploit SIMD
			 * not calculated levels are quiet NaN and they are ignored */
			virtual HRESULT IfaceCalling Accumulate(const double *times, const double *reference, const double *calculated, const size_t count) = 0;

			/* undo all previously called Accumulate */
			virtual HRESULT IfaceCalling Reset() = 0;

			/* calculates the metric - the less number is better; stores the result into the metric output parameter
			 * levels_accumulated will be the number of non-nan levels accumulated, can be nullptr
			 * returns S_FALSE if *levels_accumulated < levels_required */
			virtual HRESULT IfaceCalling Calculate(double *metric, size_t *levels_accumulated, size_t levels_required) = 0;

			/* Retrieves metric parameter struct, so that we can clone the metric, e.g., over a network connection */
			virtual HRESULT IfaceCalling Get_Parameters(TMetric_Parameters *parameters) = 0;
	};

	/* solver status enumeration */
	enum class TSolver_Status : uint8_t {
		Disabled = 0,            // no solver status
		Idle,                    // solver is idle at the moment
		In_Progress,             // solver is performing optimalization
		Completed_Improved,      // solver completed its operation, parameters were improved according to metrics
		Completed_Not_Improved,  // solver completed its operation, parameters were not improved according to metrics
		Failed                   // solver operation failed
	};

	constexpr GUID IID_Calculate_Filter_Inspection = { 0xec44cd18, 0x8d08, 0x46d1, { 0xa6, 0xcb, 0xc2, 0x43, 0x8e, 0x4, 0x19, 0x88 } };

	/* calculated signal filter inspection interface */
	class ICalculate_Filter_Inspection : public virtual refcnt::IReferenced {
		public:
			/* retrieves solver progress, copies the progress to supplied progress container (makes a deep copy, the caller must provide a valid pointer) */
			virtual HRESULT IfaceCalling Get_Solver_Progress(solver::TSolver_Progress* const progress) = 0;
			/* retrieves the solver information to given output parameters */
			virtual HRESULT IfaceCalling Get_Solver_Information(GUID* const calculated_signal_id, scgms::TSolver_Status* const status) const = 0;
			/* cancels the solver explicitly */
			virtual HRESULT IfaceCalling Cancel_Solver() = 0;
	};

	using TCreate_Metric = HRESULT(IfaceCalling*)(const TMetric_Parameters *parameters, IMetric **metric);

	using TOptimize_Parameters = HRESULT(IfaceCalling*)(scgms::IFilter_Chain_Configuration *configuration, const size_t filter_index, const wchar_t *parameters_configuration_name,
		scgms::TOn_Filter_Created on_filter_created, const void* on_filter_created_data,
		const GUID *solver_id, const size_t population_size, const size_t max_generations, 
		const double** hints, const size_t hint_count,
		solver::TSolver_Progress *progress, refcnt::wstr_list *error_description);

	using TOptimize_Multiple_Parameters = HRESULT(IfaceCalling*)(scgms::IFilter_Chain_Configuration *configuration, const size_t *filter_indices, const wchar_t **parameters_configuration_names, size_t filter_count,
		scgms::TOn_Filter_Created on_filter_created, const void* on_filter_created_data,
		const GUID *solver_id, const size_t population_size, const size_t max_generations, 
		const double** hints, const size_t hint_count,
		solver::TSolver_Progress *progress, refcnt::wstr_list *error_description);
}
