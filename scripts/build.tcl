# ==============================================================================
# Master Build Script: 32-Core SIMD GPU on ZC706
# Target: Vivado 2018.2
# ==============================================================================

# 1. Setup absolute paths so the script can be run from anywhere
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file dirname $script_dir]
cd $root_dir

# 2. Define Project Variables
set proj_name "fpga_gpu_project"
set proj_dir "$root_dir/vivado_workspace"
set partNum "xc7z045ffg900-2"

# 3. Clean Slate: Delete the old workspace if it exists
if {[file exists $proj_dir]} {
    puts "Cleaning up old Vivado workspace..."
    file delete -force $proj_dir
}

# 4. Create the Vivado GUI Project
puts "Creating Vivado Project..."
create_project $proj_name $proj_dir -part $partNum

# 5. Import Hardware Design Languages (HDL)
puts "Importing HDL sources..."
add_files -nocomplain [glob -nocomplain $root_dir/hdl/*.v]
add_files -nocomplain [glob -nocomplain $root_dir/hdl/*.sv]

# 6. Import Constraints
puts "Importing Constraints..."
add_files -fileset constrs_1 -nocomplain [glob -nocomplain $root_dir/constraints/*.xdc]

# 7. Import Memory Data (e.g., your assembly .mem files)
puts "Importing Memory Data..."
add_files -nocomplain [glob -nocomplain $root_dir/data/*.mem]

# 8. Reconstruct the Block Diagram
# This reads the script you generated with write_bd_tcl and redraws the Zynq PS/DMA
puts "Rebuilding Block Design..."
source $root_dir/bd/zynq_system.tcl

# 9. Create Block Design Wrapper (Vivado 2018.2 Syntax)
puts "Generating BD Wrapper..."
set bd_file [get_files *.bd]
make_wrapper -files [get_files $bd_file] -top

# In Vivado 2018.2, generated files go into .srcs, not .gen
add_files -norecurse [glob -nocomplain $proj_dir/${proj_name}.srcs/sources_1/bd/*/hdl/*_wrapper.v]

# 10. Set the Top Module
# Since Vivado generates the wrapper, we explicitly set it as the top module.
# The wrapper name usually matches the block design name with "_wrapper" appended.
set wrapper_name [file rootname [file tail $bd_file]]_wrapper
set_property top $wrapper_name [current_fileset]
update_compile_order -fileset sources_1

puts "=========================================================================="
puts " SUCCESS: Project reconstruction complete!"
puts " Open Vivado 2018.2 and load the project at: $proj_dir/$proj_name.xpr"
puts " Or build immediately by typing: launch_runs impl_1 -to_step write_bitstream -jobs 8"
puts "=========================================================================="