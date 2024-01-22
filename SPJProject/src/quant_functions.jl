include("quant_types.jl")

function calculate_shared_scale(row::AbstractArray{Float32})::Float64
    emaxelem = 127 
    shared_exp = floor(log2(maximum(abs.(row))))

    scale_emax = 2^(8 - 1) - 1
    shared_exp = shared_exp > scale_emax ? NaN : shared_exp
    shared_exp = shared_exp < -scale_emax ? float(-scale_emax) : shared_exp

    emax = emaxelem^floor(log2(maximum(abs.(row))))

    # shared_exp = shared_exp - emax
    
    return 2^shared_exp
end

function quantize_to_element_format(values::Vector{Float32}, scale::Float64)::Vector{Int8}
    result = Int8[]

    for value in values
        scaled_value = Float32(value / scale)
        if isnan(scale) || abs(scaled_value * 2^6) > typemax(Float32)
            push!(result, Int8(0))  # Handle special cases
        else
            push!(result, clamp(round(scaled_value * 2^6), typemin(Int8), typemax(Int8)))
        end
    end
    
    return result
end

function convert_to_quant_matrix(matrix::Matrix{Float32})
    quantized = zeros(Int, size(matrix, 1), size(matrix, 2))
    scales = zeros(Float32, size(matrix, 1))

    for row in 1:size(matrix, 1)

        shared_scale = calculate_shared_scale(matrix[row, :])
        scales[row] = shared_scale

        Pᵢ = quantize_to_element_format(matrix[row, :], shared_scale)

        quantized[row, :] = Pᵢ
    end

    return quantized, scales
end

function pack(a::Int, b::Int)
    return UInt16((a << 8) + b)
end

origin_col_idx(j, i, NBLOCKS, BLOCKSIZE=32) = (mod1(i, NBLOCKS) - 1) * BLOCKSIZE + j
origin_row_idx(i, NBLOCKS) = fld1(i, NBLOCKS)

function pack(m::Matrix{Int}, scales::Vector{Float32}, BLOCKSIZE=4)
    mat_size = size(m)

    dimension = Pair(mat_size[1], Int(ceil(mat_size[2] / BLOCKSIZE)))

    qm = Matrix{Chunk{Vector{Int8}}}(undef, mat_size[1], Int(ceil(mat_size[2] / BLOCKSIZE)))

    for i in axes(qm, 1)
        for j in 1:4:mat_size[2]

            signs = BitArray([1, 1, 1, 1])
            vals = Int8[m[i, j], (j + 1 <= size(m, 2)) ? m[i, j + 1] : 0, (j + 2 <= size(m, 2)) ? m[i, j + 2] : 0, (j + 3 <= size(m, 2)) ? m[i, j + 3] : 0]

            (m[i, j] < 0) && (vals[1] *= -1; signs[1] = 0)
            (m[i, j + 1] < 0) && (vals[2] *= -1; signs[2] = 0)
            (m[i, j + 2] < 0) && (vals[3] *= -1; signs[3] = 0)
            (m[i, j + 3] < 0) && (vals[4] *= -1; signs[4] = 0)

            chunk = Chunk{Vector{Int8}, Float32}(tuple(vals), Float32(scales[i]), signs)  

            qm[i, Int(floor(j/4))+1] = chunk
        end
    end

    fully_quantized_matrix = QuantMatrix{Vector{Int8}, Float32}(qm, dimension, 4)

    return fully_quantized_matrix
end
