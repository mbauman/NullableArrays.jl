# ----- Base.size ------------------------------------------------------------#

# We determine the size of a NullableArray array using the size of its
# `values` field. We could equivalently use the `.isnull` field.
Base.size(X::NullableArray) = size(X.values) # -> NTuple{Int}

# ----- Base.similar ---------------------------------------------------------#

# Allocate a similar array
function Base.similar{T <: Nullable}(X::NullableArray, ::Type{T}, dims::Dims)
    NullableArray(eltype(T), dims)
end

# Allocate a similar array
Base.similar(X::NullableArray, T, dims::Dims) = NullableArray(T, dims)

# ----- Base.copy/copy! ------------------------------------------------------#

Base.copy(X::NullableArray) = Base.copy!(similar(X), X)

# Copies the initialized values of a source NullableArray into the respective
# indices of the destination NullableArray.
function Base.copy!(dest::NullableArray,
                    src::NullableArray) # -> NullableArray{T, N}
    if isbits(eltype(dest)) && isbits(eltype(src))
        copy!(dest.values, src.values)
    else
        dest_values = dest.values
        src_values = src.values
        length(dest_values) >= length(src_values) || throw(BoundsError())
        # Copy only initilialized values from src into dest
        # TODO: investigate "BoolArray.chunks"
        for i in 1:length(src_values)
            @inbounds !(src.isnull[i]) && (dest.values[i] = src.values[i])
        end
    end
    copy!(dest.isnull, src.isnull)
    return dest
end

# ----- Base.fill! -----------------------------------------------------------#

function Base.fill!(X::NullableArray, x::Nullable) # -> NullableArray{T, N}
    if isnull(x)
        fill!(X.isnull, true)
    else
        fill!(X.values, get(x))
        fill!(X.isnull, false)
    end
    return X
end

function Base.fill!(X::NullableArray, x::Any) # -> NullableArray{T, N}
    fill!(X.values, x)
    fill!(X.isnull, false)
    return X
end

# ----- Base.deepcopy --------------------------------------------------------#

function Base.deepcopy(X::NullableArray) # -> NullableArray{T}
    return NullableArray(deepcopy(X.values), deepcopy(X.isnull))
end

# ----- Base.resize! ---------------------------------------------------------#

function Base.resize!{T}(X::NullableArray{T,1}, n::Int) # -> NullableArray{T, N}
    resize!(X.values, n)
    oldn = length(X.isnull)
    resize!(X.isnull, n)
    X.isnull[oldn+1:n] = true
    return X
end

# ----- Base.ndims -----------------------------------------------------------#

Base.ndims(X::NullableArray) = ndims(X.values) # -> Int

# ----- Base.length ----------------------------------------------------------#

Base.length(X::NullableArray) = length(X.values) # -> Int

# ----- Base.endof -----------------------------------------------------------#

Base.endof(X::NullableArray) = endof(X.values) # -> Int

# ----- Base.find ------------------------------------------------------------#

function Base.find(X::NullableArray{Bool}) # -> Array{Int}
    ntrue = 0
    @inbounds for (i, isnull) in enumerate(X.isnull)
        ntrue += !isnull && X.values[i]
    end
    target = Array(Int, ntrue)
    ind = 1
    @inbounds for (i, isnull) in enumerate(X.isnull)
        if !isnull && X.values[i]
            target[ind] = i
            ind += 1
        end
    end
    return target
end

# TODO: implement further 'find' methods

# ----- dropnull -------------------------------------------------------------#

dropnull(X::NullableVector) = copy(X.values[!X.isnull]) # -> Vector{T}

# ----- anynull --------------------------------------------------------------#

anynull(X::NullableArray) = any(X.isnull) # -> Bool

# NOTE: the following currently short-circuits.
function anynull(A::AbstractArray) # -> Bool
    for a in A
        if isa(a, Nullable)
            a.isnull && (return true)
        end
    end
    return false
end

function anynull(xs::NTuple) # -> Bool
    return anynull(collect(xs))
end

@generated function anynull{T, N, U<:NullableArray}(S::SubArray{T, N, U})
    return quote
        isnull = slice(S.parent.isnull, S.indexes...)
        @nloops $N i S begin
            (@nref $N isnull i) && (return true)
        end
        return false
    end
end

# ----- allnull --------------------------------------------------------------#

allnull(X::NullableArray) = all(X.isnull) # -> Bool

# ----- Base.isnan -----------------------------------------------------------#

function Base.isnan(X::NullableArray) # -> NullableArray{Bool}
    return NullableArray(isnan(X.values), copy(X.isnull))
end

# ----- Base.isfinite --------------------------------------------------------#

function Base.isfinite(X::NullableArray) # -> NullableArray{Bool}
    n = length(X)
    target = Array(Bool, size(X))
    for i in 1:n
        if !X.isnull[i]
            target[i] = isfinite(X.values[i])
        end
    end
    return NullableArray(target, copy(X.isnull))
end

# ----- Conversion methods ---------------------------------------------------#

function Base.convert{S, T, N}(::Type{Array{S, N}},
                               X::NullableArray{T, N}) # -> Array{S, N}
    if anynull(X)
        # err = "Cannot convert NullableArray with null values."
        #TODO: Investigate constructors for NullException
        throw(NullException())
    else
        return convert(Array{S, N}, X.values)
    end
end

function Base.convert{S, T, N}(::Type{Array{S}},
                               X::NullableArray{T, N}) # -> Array{S, N}
    return convert(Array{S, N}, X)
end

function Base.convert{T}(::Type{Vector}, X::NullableVector{T}) # -> Vector{T}
    return convert(Array{T, 1}, X)
end

function Base.convert{T}(::Type{Matrix}, X::NullableMatrix{T}) # -> Matrix{T}
    return convert(Array{T, 2}, X)
end

function Base.convert{T, N}(::Type{Array},
                            X::NullableArray{T, N}) # -> Array{T, N}
    return convert(Array{T, N}, X)
end

# Conversions with replacements for handling null values

function Base.convert{S, T, N}(::Type{Array{S, N}},
                               X::NullableArray{T, N},
                               replacement::Any) # -> Array{S, N}
    replacementS = convert(S, replacement)
    target = Array(S, size(X))
    for i in 1:length(X)
        if X.isnull[i]
            target[i] = replacementS
        else
            target[i] = X.values[i]
        end
    end
    return target
end

function Base.convert{T}(::Type{Vector},
                         X::NullableVector{T},
                         replacement::Any) # -> Vector{T}
    return convert(Array{T, 1}, X, replacement)
end

function Base.convert{T}(::Type{Matrix},
                         X::NullableMatrix{T},
                         replacement::Any) # -> Matrix{T}
    return convert(Array{T, 2}, X, replacement)
end

function Base.convert{T, N}(::Type{Array},
                            X::NullableArray{T, N},
                            replacement::Any) # -> Array{T, N}
    return convert(Array{T, N}, X, replacement)
end

function Base.convert{S, T, N}(::Type{NullableArray{S, N}},
                               A::AbstractArray{T, N}) # -> NullableArray{S, N}
    return NullableArray(convert(Array{S, N}, A))
end

function Base.convert{S, T, N}(::Type{NullableArray{S}},
                             A::AbstractArray{T, N}) # -> NullableArray{S, N}
    return NullableArray(convert(Array{S, N}, A))
end

function Base.convert(::Type{NullableArray},
                            A::AbstractArray) # -> NullableArray
    return NullableArray(A)
end

function Base.convert{S, T, N}(::Type{NullableArray{S, N}},
                               A::NullableArray{T, N}) # -> NullableArray{S, N}
    return NullableArray(convert(Array{S}, A.values), A.isnull)
end


function Base.float(X::NullableArray) # -> NullableArray{T, N}
    isbits(eltype(X)) || error()
    return NullableArray(float(X.values), copy(X.isnull))
end

# ----- Base.hash ------------------------------------------------------------#

# Use ready-made method for AbstractArrays or implement method specific to
# NullableArrays, possibly for performance purposes?

# ----- Base.unique ----------------------------------------------------------#

# Use ready-made method for AbstractArrays or implement method specific to
# NullableArrays, possibly for performance purposes?
