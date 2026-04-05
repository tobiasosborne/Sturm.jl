"""
    classicalise(f::Function) -> Matrix{Float64}

Compute the classical stochastic map of a single-qubit quantum channel.

Runs `f` (which takes a QBool and applies operations) on each computational
basis state using DensityMatrixContext, reads diagonal probabilities of
the output, and assembles the 2×2 transition matrix.

Returns M where M[i,j] = P(output=i-1 | input=j-1).

Example: classicalise(X!) → [0 1; 1 0] (bit-flip).
"""
function classicalise(f::Function)
    M = zeros(Float64, 2, 2)

    for input_val in 0:1
        @context DensityMatrixContext() begin
            q = QBool(Float64(input_val))
            f(q)
            # Read output probabilities from density matrix
            ctx = current_context()
            qubit = _resolve(ctx, q.wire)
            dim = 1 << ctx.n_qubits
            mask = 1 << qubit

            p0 = 0.0
            p1 = 0.0
            for i in 0:dim-1
                diag = real(ctx.orkan[i, i])
                if (i & mask) != 0
                    p1 += diag
                else
                    p0 += diag
                end
            end

            M[1, input_val + 1] = p0  # P(output=0 | input=input_val)
            M[2, input_val + 1] = p1  # P(output=1 | input=input_val)

            discard!(q)
        end
    end

    return M
end
