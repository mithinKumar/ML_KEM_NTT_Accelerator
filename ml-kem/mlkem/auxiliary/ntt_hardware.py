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

# --- Diagnostic Counters (reset between tests) ---
import time as _time
HW_CALL_LOG = []  # list of dicts: {'fn': 'ntt'/'intt', 't_fill', 't_send', 't_recv', 't_obj', 'total'}

# --- MODE Register Cache ---
# Avoid redundant AXI-Lite writes: only write MODE when it actually changes.
_LAST_MODE = [-1]  # -1 = uninitialized

# --- Fast Zm constructor ---
# Zm.__init__ does `self.val = val % m` which is wasteful for hardware outputs
# that are already guaranteed to be in [0, q). We bypass __init__ entirely.
_Zm = Zm  # keep a reference for __new__
def _fast_zm(val: int) -> Zm:
    obj = object.__new__(_Zm)
    obj.val = val
    obj.m = q
    return obj

def ntt(f: PolynomialRing) -> PolynomialRing:
    if f.representation != RingRepresentation.STANDARD:
        raise ValueError(
            "NTT can only be applied to polynomials in standard representation."
        )

    t0 = _time.perf_counter()

    # 1. Vectorized buffer fill: list comprehension extracts .val in one sweep,
    #    then numpy slice assignment writes to mmap in one C-level call.
    SHARED_IN_BUFFER[:] = [c.val for c in f.coefficients]
    t1 = _time.perf_counter()

    # 2. DMA send
    NTT_DMA.sendchannel.transfer(SHARED_IN_BUFFER)
    NTT_DMA.sendchannel.wait()
    t2 = _time.perf_counter()

    # 3. Set mode (cached) and pulse start
    if _LAST_MODE[0] != 0:
        NTT_IP.write(REG_MODE_OFFSET, 0)
        _LAST_MODE[0] = 0
    NTT_IP.write(REG_START_OFFSET, 1)
    NTT_IP.write(REG_START_OFFSET, 0)

    # 4. DMA receive (blocks until hardware signals done via m_axis_tvalid)
    NTT_DMA.recvchannel.transfer(SHARED_OUT_BUFFER)
    NTT_DMA.recvchannel.wait()
    t3 = _time.perf_counter()

    # 5. Reconstruct Python objects
    # _fast_zm bypasses Zm.__init__ and the val%m modulo op (values already in [0,q))
    out_coeffs = [_fast_zm(val) for val in SHARED_OUT_BUFFER.tolist()]
    f_ = PolynomialRing(out_coeffs, RingRepresentation.NTT)
    t4 = _time.perf_counter()

    HW_CALL_LOG.append({'fn': 'ntt',
        't_fill': (t1-t0)*1000, 't_send': (t2-t1)*1000,
        't_recv': (t3-t2)*1000, 't_obj':  (t4-t3)*1000,
        'total':  (t4-t0)*1000})
    return f_


def ntt_inv(f_: PolynomialRing) -> PolynomialRing:
    if f_.representation != RingRepresentation.NTT:
        raise ValueError(
            "Inverse NTT can only be applied to polynomials in NTT representation."
        )

    t0 = _time.perf_counter()

    # 1. Vectorized buffer fill
    SHARED_IN_BUFFER[:] = [c.val for c in f_.coefficients]
    t1 = _time.perf_counter()

    # 2. DMA send
    NTT_DMA.sendchannel.transfer(SHARED_IN_BUFFER)
    NTT_DMA.sendchannel.wait()
    t2 = _time.perf_counter()

    # 3. Set mode (cached) and pulse start
    if _LAST_MODE[0] != 1:
        NTT_IP.write(REG_MODE_OFFSET, 1)
        _LAST_MODE[0] = 1
    NTT_IP.write(REG_START_OFFSET, 1)
    NTT_IP.write(REG_START_OFFSET, 0)

    # 4. DMA receive
    NTT_DMA.recvchannel.transfer(SHARED_OUT_BUFFER)
    NTT_DMA.recvchannel.wait()
    t3 = _time.perf_counter()

    # 5. Reconstruct Python objects using fast bypass
    out_coeffs = [_fast_zm(val) for val in SHARED_OUT_BUFFER.tolist()]
    f = PolynomialRing(out_coeffs, RingRepresentation.STANDARD)
    t4 = _time.perf_counter()

    HW_CALL_LOG.append({'fn': 'intt',
        't_fill': (t1-t0)*1000, 't_send': (t2-t1)*1000,
        't_recv': (t3-t2)*1000, 't_obj':  (t4-t3)*1000,
        'total':  (t4-t0)*1000})
    return f

