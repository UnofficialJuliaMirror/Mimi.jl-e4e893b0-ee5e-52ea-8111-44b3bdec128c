#
# Functions pertaining to instantiated models and their components
#

modeldef(mi::ModelInstance) = mi.md

compinstance(mi::ModelInstance, name::Symbol) = mi.components[name]

compdef(ci::ComponentInstance) = compdef(ci.comp_id)

# compdef(mi::ModelInstance, name::Symbol) = compdef(mi.components[name].comp_id)

name(ci::ComponentInstance) = ci.comp_name

"""
    components(mi::ModelInstance)

Return an iterator on the components in model instance `mi`.
"""
components(mi::ModelInstance) = values(mi.components)

function addcomponent(mi::ModelInstance, ci::ComponentInstance) 
    mi.components[name(ci)] = ci

    push!(mi.starts, ci.start)
    push!(mi.stops, ci.stop)
end

#
# Support for dot-overloading in run_timestep functions
#
function _index_pos(names, propname, var_or_par)
    index_pos = findfirst(names, propname)
    # println("findfirst($names, $propname) returned $index_pos")

    index_pos == 0 && error("Unknown $var_or_par name $propname.")
    return index_pos
end

function _property_expr(obj, types, index_pos)
    T = types.parameters[index_pos]
    # println("_property_expr() index_pos: $index_pos, T: $T")

    if types.parameters[index_pos] <: Ref
        ex = :(obj.values[$index_pos][])
        # println("Returning $ex")
        return ex

    # TBD: deprecated if we keep Refs for everything
    else
        return :(obj.values[$index_pos])
    end
end

# Fallback get & set property funcs that revert to dot notation
@generated function getproperty(obj, ::Val{PROPERTY}) where {PROPERTY}
    return :(obj.$PROPERTY)
end

@generated function setproperty!(obj, ::Val{PROPERTY}, value) where {PROPERTY}
    return :(obj.$PROPERTY = value)
end

# Special case support for Dicts so we can use dot notation on dimension.
# The run() func passes a reference to md.index_values as the "d" parameter.
# Here we return a range representing the indices into that list of values.
@generated function getproperty(obj::Dict, ::Val{PROPERTY}) where {PROPERTY}
    return :(obj[PROPERTY])
end

# Setting/getting parameter and variable values
@generated function getproperty(obj::ComponentInstanceParameters{NAMES, TYPES}, 
                                ::Val{PROPERTY}) where {NAMES, TYPES, PROPERTY}
    index_pos = _index_pos(NAMES, PROPERTY, "parameter")
    return _property_expr(obj, TYPES, index_pos)
end

@generated function getproperty(obj::ComponentInstanceVariables{NAMES, TYPES}, 
                                ::Val{PROPERTY}) where {NAMES, TYPES, PROPERTY}
    index_pos = _index_pos(NAMES, PROPERTY, "variable")
    return _property_expr(obj, TYPES, index_pos)
end


@generated function setproperty!(obj::ComponentInstanceParameters{NAMES, TYPES}, 
                                 ::Val{PROPERTY}, value) where {NAMES, TYPES, PROPERTY}
    index_pos = _index_pos(NAMES, PROPERTY, "parameter")

    return :(obj.values[$index_pos][] = value)

    #
    # TBD: now that everything is a Ref, this isn't necessary, but still need to catch this error!
    #
    # if TYPES.parameters[index_pos] <: Ref
    #     return :(obj.values[$index_pos][] = value)
    # else
    #     return :(obj.values[$index_pos] = value)
    #     # T = TYPES.parameters[index_pos]
    #     # error("You cannot override indexed parameter $PROPERTY::$T.")
    # end
end

@generated function setproperty!(obj::ComponentInstanceVariables{NAMES, TYPES}, 
                                 ::Val{PROPERTY}, value) where {NAMES, TYPES, PROPERTY}
    index_pos = _index_pos(NAMES, PROPERTY, "variable")

    return :(obj.values[$index_pos][] = value)

    #
    # TBD: now that everything is a Ref, this isn't necessary, but still need to catch this error!
    #
    # if TYPES.variables[index_pos] <: Ref
    #     return :(obj.values[$index_pos][] = value)
    # else
    #     T = TYPES.variables[index_pos]
    #     error("You cannot override indexed variable $PROPERTY::$T.")
    # end
end

# Convenience functions that can be called with a name symbol rather than Val(name)
function get_parameter_value(ci::ComponentInstance, name::Symbol)
    try 
        return getproperty(ci.parameters, Val(name))
    catch err
        if isa(err, KeyError)
            error("Component $(ci.comp_id) has no parameter named $name")
        else
            rethrow(err)
        end
    end
end

function get_variable_value(ci::ComponentInstance, name::Symbol)
    try
        # println("Getting $name from $(ci.variables)")
        return getproperty(ci.variables, Val(name))
    catch err
        if isa(err, KeyError)
            error("Component $(ci.comp_id) has no variable named $name")
        else
            rethrow(err)
        end
    end
end

set_parameter_value(ci::ComponentInstance, name::Symbol, value) = setproperty!(ci.parameters, Val(name), value)

set_variable_value(ci::ComponentInstance, name::Symbol, value)  = setproperty!(ci.variables, Val(name), value)

# Allow values to be obtained from either parameter type using one method name.
value(param::ScalarModelParameter) = param.value

value(param::ArrayModelParameter)  = param.values

dimensions(obj::ArrayModelParameter) = obj.dimensions

dimensions(obj::ScalarModelParameter) = []

"""
variables(mi::ModelInstance, componentname::Symbol)

List all the variables of `componentname` in the ModelInstance 'mi'.
NOTE: this variables function does NOT take in Nullable instances
"""
function variables(mi::ModelInstance, comp_name::Symbol)
    ci = compinstance(mi, comp_name)
    return variables(ci)
end

variables(ci::ComponentInstance) = variables(ci.comp_id)

function getindex(mi::ModelInstance, comp_name::Symbol, datum_name::Symbol)
    if !(comp_name in keys(mi.components))
        error("Component does not exist in current model")
    end
    
    comp_inst = compinstance(mi, comp_name)
    vars = comp_inst.variables
    pars = comp_inst.parameters

    if datum_name in vars.names
        which = vars
    elseif datum_name in pars.names
        which = pars
    else
        error("$datum_name is not a parameter or a variable in component $comp_name.")
    end

    value = getproperty(which, Val(datum_name))
    # return isa(value, PklVector) || isa(value, TimestepMatrix) ? value.data : value
    return isa(value, AbstractTimestepMatrix) ? value.data : value
end

# """
#     indexcount(mi::ModelInstance, idx_name::Symbol)

# Returns the size of index `idx_name`` in model instance `mi`.
# """
# indexcount(mi::ModelInstance, idx_name::Symbol) = indexcounts(mi.md, idx_name)

"""
    dim_count(mi::ModelInstance, dim_name::Symbol)

Returns the size of index `dim_name`` in model instance `mi`.
"""
dim_count(mi::ModelInstance, dim_name::Symbol) = dim_count(mi.md, dim_name)

dim_key_dict(mi::ModelInstance) = dim_key_dict(mi.md)

dim_value_dict(mi::ModelInstance) = dim_value_dict(mi.md)

# """
#     indexvalues(mi::ModelInstance, idx_name::Symbol)

# Return the values of index `idx_name` in model instance `mi`.
# """
# indexvalues(mi::ModelInstance, idx_name::Symbol) = indexvalues(mi.md, idx_name)

function make_clock(mi::ModelInstance, ntimesteps, time_keys::Vector{Int})
    start = time_keys[1]
    stop  = time_keys[min(length(time_keys), ntimesteps)]
    step  = step_size(time_keys)
    return Clock(start, step, stop)
end

function reset_variables(ci::ComponentInstance)
    # println("reset_variables($(ci.comp_id))")
    vars = ci.variables

    for (name, ref) in zip(vars.names, vars.types.parameters)
        # Everything is held in a Ref{}, so get the parameters to that...
        T = ref.parameters[1]
        value = getproperty(vars, Val(name))

        if (T <: AbstractTimestepMatrix || T <: AbstractMatrix) && eltype(value) <: AbstractFloat
            fill!(value, NaN)

        elseif T <: AbstractFloat
            setproperty!(vars, Val(name), NaN)
        end
    end
end

function init(mi::ModelInstance)
    for ci in components(mi)
        init(mi, ci)
    end
end

function init(mi::ModelInstance, ci::ComponentInstance)
    reset_variables(ci)

    comp_def = compdef(mi.md, ci.comp_name)

    if init_expr(comp_def) != nothing
        module_name = compmodule(ci.comp_id)
        comp_name = ci.comp_name
        pars = ci.parameters
        vars = ci.variables
        dims = dim_value_dict(mi.md)

        Base.invokelatest(init, (Val(module_name), Val(comp_name), pars, vars, dims)...)
    end
end

function run_timestep(mi::ModelInstance, ci::ComponentInstance, clock::Clock)
    module_name = compmodule(ci.comp_id)
    comp_name = compname(ci.comp_id)
    
    pars = ci.parameters
    vars = ci.variables
    dims = dim_value_dict(mi.md)
    t = timeindex(clock)

    # required since we eval the run_func on the fly
    Base.invokelatest(run_timestep, (Val(module_name), Val(comp_name), pars, vars, dims, t)...)
    advance(clock)
end

function run(mi::ModelInstance, ntimesteps::Int=typemax(Int), 
             dim_keys::Union{Void, Dict{Symbol, Vector{T} where T}}=nothing)
    if length(mi.components) == 0
        error("Cannot run the model: no components have been created.")
    end

    dim_keys = dim_keys == nothing ? dim_key_dict(mi) : dim_keys

    starts = mi.starts
    stops = mi.stops
    step  = step_size(dim_keys[:time])

    comp_clocks = [Clock(start, step, stop) for (start, stop) in zip(starts, stops)]
    
    clock = make_clock(mi, ntimesteps, dim_keys[:time])

    init(mi)    # call module's (or fallback) init function

    comp_instances = components(mi)

    while ! finished(clock)
        for (ci, start, stop, comp_clock) in zip(comp_instances, starts, stops, comp_clocks)
            if start <= gettime(clock) <= stop
                run_timestep(mi, ci, comp_clock)
            end
        end
        advance(clock)
    end
end
