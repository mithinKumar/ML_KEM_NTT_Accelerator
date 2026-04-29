import random

Q = 3329
ZETA = 17
ZETA_INV = 1175

def write_hex(filename, data):
    """Writes a list of integers to a file in 3-digit (12-bit) hex format."""
    with open(filename, 'w') as f:
        for val in data:
            f.write(f"{val:03X}\n")
    print(f"Created: {filename}")

def brv(x):
    """7-bit standard bit reversal"""
    return int(f"{x:07b}"[::-1], 2)

# ==========================================
# 1. GENERATE HARDWARE-ALIGNED TWIDDLES
# ==========================================
twiddles_fwd = [0] * 128
twiddles_inv = [0] * 128

for s in range(7):
    num_chunks = 1 << s
    for chunk_idx in range(num_chunks):
        # Hardware's exact Twiddle ROM Address (Tree Traversal)
        tw_addr = (chunk_idx << (7 - s)) | (1 << (6 - s))

        # Forward NTT Mathematical K
        k_fwd = (1 << s) + chunk_idx
        twiddles_fwd[tw_addr] = pow(ZETA, brv(k_fwd), Q)

        # Inverse NTT Mathematical K (GS counts backwards)
        k_inv = ((1 << (s + 1)) - 1) - chunk_idx
        twiddles_inv[tw_addr] = pow(ZETA_INV, brv(k_inv), Q)

write_hex("twiddle_mem_dual.hex", twiddles_fwd + twiddles_inv)

# ==========================================
# 2. KYBER STANDARD ALGORITHMS
# ==========================================
def kyber_ntt(poly):
    A = list(poly)
    k = 1
    length = 128
    while length >= 2:
        for start in range(0, 256, 2 * length):
            zeta = pow(ZETA, brv(k), Q)
            k += 1
            for j in range(start, start + length):
                t = (zeta * A[j + length]) % Q
                A[j + length] = (A[j] - t) % Q
                A[j] = (A[j] + t) % Q
        length >>= 1
    return A

def kyber_intt(poly):
    A = list(poly)
    k = 127
    length = 2
    while length <= 128:
        for start in range(0, 256, 2 * length):
            zeta_inv = pow(ZETA_INV, brv(k), Q)
            k -= 1
            for j in range(start, start + length):
                t = A[j]
                A[j] = (t + A[j + length]) % Q
                A[j + length] = (t - A[j + length]) % Q
                A[j + length] = (A[j + length] * zeta_inv) % Q
        length <<= 1
    return A

# ==========================================
# 3. GENERATE TEST CASES
# ==========================================
print("Generating Kyber Reference Models with Hardware-Mapped ROM...")

tc1_in = [random.randint(0, Q-1) for _ in range(256)]
write_hex("tc1_input.hex", tc1_in)
write_hex("tc1_expected.hex", kyber_ntt(tc1_in))

tc2_in = [random.randint(0, Q-1) for _ in range(256)]
write_hex("tc2_input.hex", tc2_in)
write_hex("tc2_expected.hex", kyber_intt(tc2_in))

tc3_in = [0 for _ in range(256)]
write_hex("tc3_zeros_input.hex", tc3_in)
write_hex("tc3_zeros_expected.hex", kyber_ntt(tc3_in))

print("All files updated successfully! Run the Verilog simulation now.")