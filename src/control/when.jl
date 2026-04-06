"""
    when(f::Function, ctrl::QBool)

Quantum control: execute `f()` controlled on `ctrl`.
`ctrl` remains quantum (no measurement). Nesting composes controls.

Usage:
    when(flag) do
        target.φ += π/4    # controlled-T
    end
"""
@inline function when(f::Function, ctrl::QBool)
    check_live!(ctrl)
    push_control!(ctrl.ctx, ctrl.wire)
    try
        f()
    finally
        pop_control!(ctrl.ctx)
    end
end
