import sys
import os
import random

# Add ml-kem to Python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../../ml-kem')))

from mlkem.math.polynomial_ring import PolynomialRing, RingRepresentation
from mlkem.auxiliary.ntt import ntt, ntt_inv
from mlkem.math.field import Zm

Q = 3329

def write_hex(filename, data):
    """Writes a list of integers to a file in 3-digit (12-bit) hex format."""
    with open(filename, 'w') as f:
        for val in data:
            f.write(f"{val:03X}\n")
    print(f"Created: {filename}")

# ==========================================
# 1. GENERATE HARDWARE-ALIGNED TWIDDLES
# ==========================================
ZETA = 17
ZETA_INV = 1175

def brv(x):
    return int(f"{x:07b}"[::-1], 2)

twiddles_fwd = [0] * 128
twiddles_inv = [0] * 128

for s in range(7):
    num_chunks = 1 << s
    for chunk_idx in range(num_chunks):
        tw_addr = (chunk_idx << (7 - s)) | (1 << (6 - s))
        k_fwd = (1 << s) + chunk_idx
        twiddles_fwd[tw_addr] = pow(ZETA, brv(k_fwd), Q)
        k_inv = ((1 << (s + 1)) - 1) - chunk_idx
        zeta_val = pow(ZETA, brv(k_inv), Q)
        twiddles_inv[tw_addr] = (Q - zeta_val) % Q

write_hex("twiddle_mem_dual_new.hex", twiddles_fwd + twiddles_inv)

# ==========================================
# 2. GENERATE TEST CASES USING STANDARD ntt.py
# ==========================================
print("Generating Kyber Reference Models with standard ML-KEM NTT...")

def get_coeffs(poly):
    # Extracts integer values from Zm coefficients
    return [int(c.val) if hasattr(c, 'val') else int(c) for c in poly.coefficients]

# Test Case 1: Forward NTT
tc1_in_int = [random.randint(0, Q-1) for _ in range(256)]
tc1_in = [Zm(x, Q) for x in tc1_in_int]
poly1 = PolynomialRing(tc1_in, RingRepresentation.STANDARD)
poly1_ntt = ntt(poly1)
write_hex("tc1_input_new.hex", tc1_in_int)
write_hex("tc1_expected_new.hex", get_coeffs(poly1_ntt))

# Test Case 2: Inverse NTT
tc2_in_int = [random.randint(0, Q-1) for _ in range(256)]
tc2_in = [Zm(x, Q) for x in tc2_in_int]
poly2 = PolynomialRing(tc2_in, RingRepresentation.NTT)
poly2_intt = ntt_inv(poly2)
write_hex("tc2_input_new.hex", tc2_in_int)
write_hex("tc2_expected_new.hex", get_coeffs(poly2_intt))

# Test Case 3: Edge Case (Zeros)
tc3_in_int = [0 for _ in range(256)]
tc3_in = [Zm(x, Q) for x in tc3_in_int]
poly3 = PolynomialRing(tc3_in, RingRepresentation.STANDARD)
poly3_ntt = ntt(poly3)
write_hex("tc3_zeros_input_new.hex", tc3_in_int)
write_hex("tc3_zeros_expected_new.hex", get_coeffs(poly3_ntt))

print("All new files updated successfully! Run the new Verilog simulation now.")
