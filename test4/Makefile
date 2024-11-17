# Makefile for VCS simulation

# Define the simulator
SIM = vcs
SEED = 1
TESTNAME ?=rt_single_ch_test

# Compiler and simulator flags
COMPILE_FLAGS = -full64 -sverilog -debug_access+all -timescale=1ns/1ps -l comp.log -kdb -cm line+tgl+branch+fsm
SIM_FLAGS = -l sim.log -dump -add /* +ntb_random_seed=$(SEED) +TESTNAME=$(TESTNAME) -cm line+tgl+branch -cm_name $(TESTNAME)_$(SEED)


TB = tb
# Define target
TARGET = simv #-gui

# Source files
SOURCES = router_io.sv rt_test_pkg.sv tb.sv ../dut/router.v 

# Default rule to run everything
all: compile simulate

# Rule to compile
compile: $(SOURCES)
	$(SIM) $(COMPILE_FLAGS) -top $(TB) -o $(TARGET) $(SOURCES)

# Rule to run simulation
simulate:
	./$(TARGET) $(SIM_FLAGS)

editcov:
	urg -full64 -dir *.vdb -dbname merged -parallel -report urgReport
	dve -cov -full64 -dir simv.vdb &

viewcov:
	#urg -full64 -format both -dir simv.vdb
	firefox urgReport/dashboard.html

clean:
	rm -rf AN.DB DVEfiles csrc simv* *.cst *.simv *.simv.daidir *.simv.vdb ucli.key
	rm -rf *.log* *.vpd *.h urgReport


.PHONY: all compile simulate clean
.SECONDARY:

