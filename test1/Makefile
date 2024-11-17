# Makefile for VCS simulation

# Define the simulator
SIM = vcs

# Compiler and simulator flags
COMPILE_FLAGS = -sverilog -debug_all +lint=all,noVCDE
SIM_FLAGS = -l sim.log

# Define target
TARGET = simv

# Source files
SOURCES = tb.sv rt_stimulator.sv rt_monitor.sv rt_generator.sv rt_interface.sv ../dut/router.v

# Default rule to run everything
all: compile simulate

# Rule to compile
compile: $(SOURCES)
	$(SIM) $(COMPILE_FLAGS) -o $(TARGET) $(SOURCES)

# Rule to run simulation
simulate:
	./$(TARGET) $(SIM_FLAGS)

# Clean rule
clean:
	rm -rf $(TARGET) csrc simv.daidir ucli.key sim.log DVEfiles *.vpd *.key

# Dependency on header or package files
tb.sv: ../dut/router.v rt_interface.sv
rt_stimulator.sv rt_monitor.sv rt_generator.sv: rt_interface.sv

# Include dependency
include $(SOURCES:.sv=.d)

.PHONY: all compile simulate clean
