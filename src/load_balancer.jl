export AbstractLoadBalancer, GreedyLoadBalancer, RoundRobinLoadBalancer

abstract type AbstractLoadBalancer{T} end

mutable struct GreedyLoadBalancer{T <: Real} <: AbstractLoadBalancer{T}
  problems::Dict{Int, Problem{T}}
  method::Function
  iteration::Int

  function GreedyLoadBalancer(
    problems::Dict{Int, Problem{T}},
    method::Function,
    iteration::Int
  ) where {T <: Real}
    obj = new{T}(problems, method, iteration)
    obj.method = nb_partitions -> (method(obj, nb_partitions))
    return obj
  end
end

function GreedyLoadBalancer(problems::Dict{Int, Problem{T}}) where {T <: Real}
  return GreedyLoadBalancer(problems, greedy_problem_partition, 0)
end

mutable struct RoundRobinLoadBalancer{T <: Real} <: AbstractLoadBalancer{T}
  problems::Dict{Int, Problem{T}}
  method::Function
  iteration::Int

  function RoundRobinLoadBalancer(
    problems::Dict{Int, Problem{T}},
    method::Function,
    iteration::Int
  ) where {T <: Real}
    obj = new{T}(problems, method, iteration)
    obj.method = nb_partitions -> (method(obj, nb_partitions))
    return obj
  end
end

function RoundRobinLoadBalancer(problems::Dict{Int, Problem{T}}) where {T <: Real}
  return RoundRobinLoadBalancer(problems, round_robin_partition, 0)
end

generate_problem_dict(g) = Dict(id => Problem(id, nlp, eps(Float64))  for (id,nlp) ∈ enumerate(g))

function execute(
  lb::L;
  iteration_threshold = 1,
) where {L <: AbstractLoadBalancer}
  isempty(values(lb.problems)) && return
  bb_iteration = lb.iteration
  # to make sure we load balance after the first iteration
  (bb_iteration != 0) && ((bb_iteration - 1) % iteration_threshold != 0) && return

  nb_partitions = length(workers())
  partitions = lb.method(nb_partitions)

  problem_def_future = Future[]
  for (i, worker_id) in enumerate(workers())
    remotecall_fetch(clear_worker_problems, worker_id)
    push!(problem_def_future, remotecall(push_worker_problems, worker_id, partitions[i]))
  end
  @sync for problem_future in problem_def_future
    @async fetch(problem_future)
  end
  lb.iteration += 1
end

function greedy_problem_partition(
  lb::GreedyLoadBalancer{T},
  nb_partitions::Int,
) where {T <: Real}
  partitions = [Vector{Problem}() for _ ∈ 1:nb_partitions]
  problems = sort(collect(values(lb.problems)); by = p -> p.weight, rev = true)
  σ = sum(problem.weight for problem ∈ problems) / nb_partitions
  penalties = [-σ for _ ∈ 1:nb_partitions]
  for pb ∈ problems
    p_idx = argmin(penalties)
    push!(partitions[p_idx], pb)
    penalties[p_idx] += pb.weight
  end
  return partitions
end

function round_robin_partition(lb::RoundRobinLoadBalancer{T}, nb_partitions::Int) where {T <: Real}
  problems = collect(Problem, values(lb.problems))
  problems = shuffle(problems)
  partitions = [problems[i:nb_partitions:length(problems)] for i ∈ 1:nb_partitions]
  return partitions
end
