import pynq
import numpy as np
from pynq import allocate
from mlkem.math.constants import n, q
from mlkem.math.field import Zm
from mlkem.math.polynomial_ring import PolynomialRing, RingRepresentation

# --- PYNQ Hardware Initialization ---
print("Loading ML-KEM NTT Hardware Overlay...")
# Note: Ensure your bitstream is uploaded to the same directory and rename this if needed.
OVERLAY = pynq.Overlay("/home/xilinx/jupyter_notebooks/EE712/Project/ml-kem/project/pynq.bit") 

# Map the hardware IPs using their exact names from the Vivado Block Design
NTT_DMA = OVERLAY.axi_dma_0
NTT_IP = OVERLAY.mlkem_mmio_0
print("Hardware loaded successfully!")

# --- AXI-Lite MMIO Register Offsets ---
REG_MODE_OFFSET = 0x10   # 0 for NTT, 1 for INTT
REG_START_OFFSET = 0x14  # Start pulse
REG_READY_OFFSET = 0x18  # Done / Ready polling signal

# --- Global DMA Buffers ---
# Allocating memory through the Linux Kernel CMA is very slow. 
# We allocate these globally ONCE to achieve maximum throughput.
SHARED_IN_BUFFER = allocate(shape=(n,), dtype=np.uint16)
SHARED_OUT_BUFFER = allocate(shape=(n,), dtype=np.uint16)

def ntt(f: PolynomialRing) -> PolynomialRing:
    if f.representation != RingRepresentation.STANDARD:
        raise ValueError(
            "NTT can only be applied to polynomials in standard representation."
        )

    # 1. Load data into the shared contiguous memory
    for i, coeff in enumerate(f.coefficients):
        SHARED_IN_BUFFER[i] = coeff.val
        
    # 2. Transfer data via AXI Stream DMA and wait for completion
    NTT_DMA.sendchannel.transfer(SHARED_IN_BUFFER)
    NTT_DMA.sendchannel.wait()

    # 3. Set the mode to 0 (Forward NTT)
    NTT_IP.write(REG_MODE_OFFSET, 0)
    
    # 4. Toggle the start bit (simulate a start pulse)
    NTT_IP.write(REG_START_OFFSET, 1)
    NTT_IP.write(REG_START_OFFSET, 0) # Clear if hardware doesn't auto-clear
    
    # 5. (Redundant MMIO polling removed: DMA recvchannel intrinsically waits for ntt_done to fire)
            
    # 6. Read output data via AXI Stream DMA receive channel
    NTT_DMA.recvchannel.transfer(SHARED_OUT_BUFFER)
    NTT_DMA.recvchannel.wait()
    
    out_coeffs = [Zm(val, q) for val in SHARED_OUT_BUFFER]
        
    # 7. Reformat data and return as NTT object
    f_ = PolynomialRing(out_coeffs, RingRepresentation.NTT)
    
    return f_


def ntt_inv(f_: PolynomialRing) -> PolynomialRing:
    if f_.representation != RingRepresentation.NTT:
        raise ValueError(
            "Inverse NTT can only be applied to polynomials in NTT representation."
        )

    # 1. Load data into the shared contiguous memory
    for i, coeff in enumerate(f_.coefficients):
        SHARED_IN_BUFFER[i] = coeff.val
        
    # 2. Transfer data via AXI Stream DMA and wait
    NTT_DMA.sendchannel.transfer(SHARED_IN_BUFFER)
    NTT_DMA.sendchannel.wait()

    # 3. Set the mode to 1 (Inverse NTT / INTT)
    NTT_IP.write(REG_MODE_OFFSET, 1)
    
    # 4. Toggle the start bit
    NTT_IP.write(REG_START_OFFSET, 1)
    NTT_IP.write(REG_START_OFFSET, 0) 
    
    # 5. (Redundant MMIO polling removed: DMA recvchannel intrinsically waits for ntt_done to fire)
            
    # 6. Read output data via AXI Stream DMA receive channel
    NTT_DMA.recvchannel.transfer(SHARED_OUT_BUFFER)
    NTT_DMA.recvchannel.wait()
    
    out_coeffs = [Zm(val, q) for val in SHARED_OUT_BUFFER]
        
    # 7. Reformat data and return as STANDARD object
    f = PolynomialRing(out_coeffs, RingRepresentation.STANDARD)
    
    return f
