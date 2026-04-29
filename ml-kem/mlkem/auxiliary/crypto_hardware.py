# Hardware Mode Convention:
# Mode 0: SHA3-256
# Mode 1: SHA3-512
# Mode 2: SHAKE-128
# Mode 3: SHAKE-256

# --- Placeholders for your PYNQ hardware endpoints ---
#OVERLAY = pynq.Overlay("mlkem_accel.bit")  
# SHA3_IP = OVERLAY.sha3_engine_ip
# REG_MODE       = 0x10  # 0: SHA3-256, 1: SHA3-512, 2: SHAKE-128, 3: SHAKE-256
# REG_MSG_SIZE   = 0x14  # Size of current payload in bytes
# REG_OFFSET     = 0x18  # 1 for 'more blocks', 0 for 'final block'
# REG_START      = 0x1C  # Pulse to start block
# REG_READY      = 0x20  # Poll for completion
# MEM_IN_BASE    = 0x100 # Base offset to write bytes
# MEM_OUT_BASE   = 0x200 # Base offset to read outputs
# REG_RESET      = 0x24  # Pulse to reset Keccak state matrix
# REG_SQUEEZE    = 0x28  # Pulse to trigger a raw squeeze permutation

def _hardware_reset():
    """Pulse the reset signal to clear the Keccak state matrix."""
    SHA3_IP.write(REG_RESET, 1)
    SHA3_IP.write(REG_RESET, 0)


def _hardware_absorb(msg: bytes, r_size: int, mode: int):
    """
    Iteratively chunk and send a message to the hardware absorption buffer.
    """
    # 1. Inform the hardware which primitive we are using
    SHA3_IP.write(REG_MODE, mode)
    
    total_len = len(msg)
    
    # If the message is completely empty, we still must process 0 bytes and apply padding
    if total_len == 0:
        chunks = [b""]
    else:
        chunks = [msg[i:i + r_size] for i in range(0, total_len, r_size)]
    
    for i, chunk in enumerate(chunks):
        chunk_len = len(chunk)
        is_last_chunk = (i == len(chunks) - 1)
        
        # 2. Write the chunk bytes into the hardware input buffer.
        # (Assuming your registers are byte-addressable. If they are exactly 32-bit, 
        # you will need a small loop to pack 4 bytes into an integer here)
        for byte_idx, byte_val in enumerate(chunk):
            SHA3_IP.write(MEM_IN_BASE + (byte_idx * 4), byte_val)
            
        # 3. Configure the block and size
        SHA3_IP.write(REG_MSG_SIZE, chunk_len) 
        
        # If it's the last chunk, offset=0 (apply pad). Else offset=1 (do not pad).
        SHA3_IP.write(REG_OFFSET, 0 if is_last_chunk else 1)
        
        # 4. Pulse the start signal
        SHA3_IP.write(REG_START, 1)
        SHA3_IP.write(REG_START, 0)
        
        # 5. Polling loop: Wait for hardware to finish permutation
        while True:
            if SHA3_IP.read(REG_READY) == 1:
                break


def prf(eta: int, s: bytes, b: bytes) -> bytes:
    if eta not in {2, 3}:
        raise ValueError(f"eta must be 2 or 3 (got {eta})")
    if len(s) != 32:
        raise ValueError(f"len(s) must be 32 (got {len(s)})")
    if len(b) != 1:
        raise ValueError(f"len(b) must be 1 (got {len(b)})")

    # The string to hash
    msg = s + b

     # 0. Reset the hardware to clear previous hashing state
    _hardware_reset()
    
    # 1. Start absorption. SHAKE-256 (Assuming mode = 3) has an r_size of 136 bytes.
    _hardware_absorb(msg, r_size=136, mode=3)
    
    # 2. Setup generation (Squeeze loop)
    desired_length = 64 * eta
    out_buffer = bytearray()
    
    while len(out_buffer) < desired_length:
        # Calculate how many bytes we can read in this squeeze cycle
        remaining = desired_length - len(out_buffer)
        bytes_to_read = min(remaining, 136) # Max we can read per cycle is r_size
        
        # Read the available output from the output memory buffer
        for i in range(bytes_to_read):
            val = SHA3_IP.read(MEM_OUT_BASE + (i * 4))
            out_buffer.append(val & 0xFF)
            
        # If we still need more bytes, we pulse hardware to compute the next block
        if len(out_buffer) < desired_length:
            # We trigger the dedicated Squeeze bypass logic in hardware
            SHA3_IP.write(REG_SQUEEZE, 1)
            SHA3_IP.write(REG_SQUEEZE, 0)
            
            while True:
                if SHA3_IP.read(REG_READY) == 1:
                    break

    return bytes(out_buffer)

def h(s: bytes) -> bytes:
    r"""An alias for the SHA3-256 hash function."""
    # 0. Clear hardware state
    _hardware_reset()
    
    # 1. Mode 0: SHA3-256, r_size = 136 bytes.
    _hardware_absorb(s, r_size=136, mode=0)
    
    # 2. Read exactly 32 bytes from the output buffer
    out_buffer = bytearray()
    for i in range(32):
        val = SHA3_IP.read(MEM_OUT_BASE + (i * 4))
        out_buffer.append(val & 0xFF)
        
    return bytes(out_buffer)


def j(s: bytes) -> bytes:
    r"""An alias for the SHAKE-256 hash function returning 32 bytes."""
    # 0. Clear hardware state
    _hardware_reset()
    
    # 1. Mode 3: SHAKE-256, r_size = 136 bytes.
    _hardware_absorb(s, r_size=136, mode=3)
    
    # 2. Read exactly 32 bytes from the output buffer
    out_buffer = bytearray()
    for i in range(32):
        val = SHA3_IP.read(MEM_OUT_BASE + (i * 4))
        out_buffer.append(val & 0xFF)
        
    return bytes(out_buffer)


def g(c: bytes) -> tuple[bytes, bytes]:
    r"""An alias for the SHA3-512 hash function. Output is split into two 32 byte values."""
    # 0. Clear hardware state
    _hardware_reset()
    
    # 1. Mode 1: SHA3-512, r_size = 72 bytes.
    _hardware_absorb(c, r_size=72, mode=1)
    
    # 2. Read exactly 64 bytes from the output buffer
    out_buffer = bytearray()
    for i in range(64):
        val = SHA3_IP.read(MEM_OUT_BASE + (i * 4))
        out_buffer.append(val & 0xFF)
        
    # 3. Split the digest into two equal 32-byte halves
    ab = bytes(out_buffer)
    return ab[:32], ab[32:]


class XOF:
    r"""An eXtendable-Output Function that interfaces directly with the hardware SHAKE-128."""

    def __init__(self) -> None:
        # MODE 2: SHAKE-128 (rate = 168 bytes)
        self.mode = 2
        self.r_size = 168
        
        # 0. Clear hardware state before initializing a new sponge
        _hardware_reset()
        
        # We maintain a small python buffer just for bytes we've squeezed 
        # from the hardware but haven't returned to the caller yet
        self.buffer = bytearray()

    def absorb(self, string: bytes) -> None:
        """Absorb data into the hardware SHAKE-128 state."""
        # This will absorb the full string, set offset=0 on the last block, 
        # apply padding, run rounds, and leave the state machine ready
        _hardware_absorb(string, r_size=self.r_size, mode=self.mode)
        
        # Pull the very first block of squeezed data from the hardware
        for i in range(self.r_size):
            val = SHA3_IP.read(MEM_OUT_BASE + (i * 4))
            self.buffer.append(val & 0xFF)

    def squeeze(self, length: int) -> bytes:
        """Extract output bytes from the hardware, triggering permutations if needed."""
        # 1. Check if we need the hardware to generate more squeeze blocks
        while len(self.buffer) < length:
            # Trigger the dedicated squeeze permutation in hardware
            SHA3_IP.write(REG_SQUEEZE, 1)
            SHA3_IP.write(REG_SQUEEZE, 0)
            
            while True:
                if SHA3_IP.read(REG_READY) == 1:
                    break
                    
            # Read the new 168 bytes from the hardware
            for i in range(self.r_size):
                val = SHA3_IP.read(MEM_OUT_BASE + (i * 4))
                self.buffer.append(val & 0xFF)

        # 2. Return the requested bytes and remove them from our buffer
        result = self.buffer[:length]
        self.buffer = self.buffer[length:]
        
        return bytes(result)
