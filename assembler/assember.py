# The module below is a lightweight compiler from assembly-like
# program files into ISA-compliant files that can be loaded on
# to the controller in the GPU.

import sys

###########################################################
#                                                         #
# The functions below convert commands into machine code. #
# Upgraded for 32-bit datapath & automatic instruction    #
# expansion for massive 32-bit immediate values.          #
#                                                         #
###########################################################

def nop():
    return [(0b0000 << 28)]

def end():
    return [(0b0001 << 28)]

def _mask4(val):
    return int(val) & 0xF

def xor(a_reg, b_reg):
    return [(0b0010 << 28) + (_mask4(a_reg) << 24) + (_mask4(b_reg) << 4)]

def addi(a_reg, b_reg, val):
    val = int(val)
    if val < -32768 or val > 32767:
        # Requires 32-bit expansion
        lower = val & 0xFFFF
        upper = (val >> 16) & 0xFFFF
        
        # If the lower 16 bits have their sign bit set, the first ADDI 
        # will sign-extend and effectively subtract 1 from the upper 16 bits.
        # We mathematically compensate by adding 1 to the upper half!
        if lower & 0x8000:
            upper = (upper + 1) & 0xFFFF
            
        return [
            (0b0011 << 28) + (_mask4(a_reg) << 24) + (lower << 8) + (_mask4(b_reg) << 4),
            (0b0011 << 28) + (_mask4(a_reg) << 24) + (upper << 8) + (_mask4(a_reg) << 4) + 1 # The +1 triggers the LOAD HIGH flag in bit [31]
        ]
    else:
        return [(0b0011 << 28) + (_mask4(a_reg) << 24) + ((val & 0xFFFF) << 8) + (_mask4(b_reg) << 4)]

def bge(a_reg, b_reg):
    return [(0b0100 << 28) + (_mask4(a_reg) << 24) + (_mask4(b_reg) << 4)]

def jump(jump_to_val):
    return [(0b0101 << 28) + ((int(jump_to_val) & 0xFFFF) << 8)]

def fbswap():
    return [(0b0110 << 28)]

def loadi(a_reg, val):
    val = int(val)
    if val < -32768 or val > 32767:
        # Memory LOADI directly overwrites the register halves, no compensation needed
        lower = val & 0xFFFF
        upper = (val >> 16) & 0xFFFF
        return [
            (0b0111 << 28) + (_mask4(a_reg) << 24) + (lower << 8),
            (0b0111 << 28) + (_mask4(a_reg) << 24) + (upper << 8) + 1 # The +1 triggers the LOAD HIGH flag
        ]
    else:
        return [(0b0111 << 28) + (_mask4(a_reg) << 24) + ((val & 0xFFFF) << 8)]

def add(a_reg, b_reg, c_reg):
    return [(0b1000 << 28) + (_mask4(a_reg) << 24) + (_mask4(b_reg) << 4) + _mask4(c_reg)]

def loadb(shuf1, shuf2, shuf3):
    return [(0b1001 << 28) + (_mask4(shuf1) << 24) + (_mask4(shuf2) << 4) + _mask4(shuf3)]

def load(abc, b_reg, c_reg):
    # FIXED: memory.sv uses reg_c for the delta multiplier, not an immediate.
    return [(0b1010 << 28) + (_mask4(abc) << 24) + (_mask4(b_reg) << 4) + _mask4(c_reg)]

def writeb(replace_c, fma_val):
    return [(0b1011 << 28) + (_mask4(replace_c) << 24) + (_mask4(fma_val) << 4)]

def write(replace_c, fma_val):
    return [(0b1100 << 28) + (_mask4(replace_c) << 24) + (_mask4(fma_val) << 4)]

def or_op(iter_val):
    return [(0b1101 << 28) + (int(iter_val) << 24)]

def senditers(x_count, y_count):
    return [(0b1110 << 28) + (_mask4(x_count) << 24) + (_mask4(y_count) << 4)]

def pause():
    return [(0b1111 << 28)]


str_to_command = {
    "nop": nop,
    "end": end,
    "xor": xor,
    "addi": addi,
    "bge": bge,
    "jump": jump,
    "fbswap": fbswap,
    "loadi": loadi,
    "add": add,
    "loadb": loadb,
    "load": load,
    "writeb": writeb,
    "write": write,
    "or": or_op,
    "senditers": senditers,
    "pause": pause
}

def parse_arg_raw(arg_str):
    if arg_str.startswith("r"):
        return int(arg_str[1:])
    try:
        return int(arg_str)
    except ValueError:
        return arg_str # Return as string for jump label resolution

if __name__ == "__main__":
    args = sys.argv[1:]
    
    if len(args) != 1:
        print("\tPlease pass one argument <program_file_path> to convert to ISA.")
        exit()

    orig_name = args[0].split("/")[-1].split(".")[0]
    
    with open(args[0], "r") as f:
        file_content = f.read()

    lines = file_content.replace("\r", "").split("\n")
    instructions = []
    for line in lines:
        clean = line.split("#")[0].strip().lower()
        if clean:
            instructions.append(clean)
    
    instructions.append("nop")
    
    # PASS 1: Map instruction lines to their expanded BRAM addresses
    line_to_bram_addr = {}
    bram_addr = 0
    parsed_lines = []
    
    for line_idx, instr_str in enumerate(instructions):
        line_to_bram_addr[line_idx] = bram_addr
        
        parts = [p for p in instr_str.replace(",", " ").split() if p]
        op_name = parts[0]
        op_args = [parse_arg_raw(arg) for arg in parts[1:]]
        
        parsed_lines.append((op_name, op_args, line_idx, instr_str))
        
        # Predict dynamic expansion length
        if op_name in ["addi", "loadi"]:
            val = op_args[-1]
            if isinstance(val, int) and (val < -32768 or val > 32767):
                bram_addr += 2
            else:
                bram_addr += 1
        else:
            bram_addr += 1

    # PASS 2: Resolve jump targets and emit Machine Code
    isa_commands = []
    for op_name, op_args, line_idx, raw_text in parsed_lines:
        if op_name not in str_to_command:
            raise ValueError(f"Unrecognized command '{op_name}' on line {line_idx+1}")
        
        # Resolve jump targets using their new expanded memory footprint.
        # Numeric targets are treated as source-line indices so expansion stays correct.
        # Use @<addr> to force an absolute BRAM address.
        if op_name == "jump":
            target = op_args[0]
            if isinstance(target, str):
                resolved = False
                if target.startswith("@"):
                    op_args[0] = int(target[1:])
                    resolved = True
                else:
                    for i, instr in enumerate(instructions):
                        if instr == target:
                            op_args[0] = line_to_bram_addr[i]
                            resolved = True
                            break
                if not resolved:
                    raise ValueError(f"Could not resolve jump target '{target}'")
            else:
                if target < 0 or target >= len(instructions):
                    raise ValueError(f"Jump target out of range: {target}")
                op_args[0] = line_to_bram_addr[target]

        try:
            commands = str_to_command[op_name](*op_args)
        except Exception as e:
            raise ValueError(f"Compile Error on line {line_idx+1} ('{raw_text}'): {e}")
            
        for cmd in commands:
            isa_commands.append(f"{cmd:08x}")

    with open(orig_name + ".mem", "w") as f:
        f.write("\n".join(isa_commands))
        
    print(f"Success! Compiled {len(instructions)} lines into {len(isa_commands)} machine instructions.")