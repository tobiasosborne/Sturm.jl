"""
    AbstractCode

Abstract base type for quantum error-correcting codes.
Subtypes implement `encode!` and `decode!` which map between
logical and physical qubits.
"""
abstract type AbstractCode end

"""
    encode!(code::AbstractCode, logical::QBool) -> NTuple{N, QBool}

Encode a logical qubit into N physical qubits using the given code.
The logical qubit is consumed; N fresh physical qubits are returned.
"""
function encode! end

"""
    decode!(code::AbstractCode, physical::NTuple{N, QBool}) -> QBool

Decode N physical qubits back to 1 logical qubit.
Performs error syndrome extraction and correction.
Physical qubits are consumed; 1 logical qubit is returned.
"""
function decode! end
