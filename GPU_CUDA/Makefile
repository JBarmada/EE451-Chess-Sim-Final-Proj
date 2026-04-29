# Compiler
NVCC     = nvcc

# Flags
# NOTE: -arch must match your GPU's compute capability. The default sm_70
# targets V100. Common values:
#   sm_70  → V100              (Volta)
#   sm_75  → RTX 2080 Ti       (Turing)
#   sm_80  → A100              (Ampere — data center)
#   sm_86  → RTX 3090 / 3090 Ti / 30-series  (Ampere)  ← used for our published results
#   sm_89  → RTX 4090 / 40-series            (Ada Lovelace)
#   sm_90  → H100              (Hopper)
# Look up your GPU at https://developer.nvidia.com/cuda-gpus
# Running a binary built for the wrong arch fails with
# "no kernel image is available for execution on the device".
NVCCFLAGS = -std=c++17 -O2 -arch=sm_70
LDFLAGS   = -lcurand

# Directories
SRC_DIR  = .
OBJ_DIR  = build

# Main target
TARGET   = chess

# Source files
MAIN_SRC = $(SRC_DIR)/main.cu

# Test sources and their targets
TEST_SRCS = $(wildcard $(SRC_DIR)/test_*.cu)
TEST_BINS = $(patsubst $(SRC_DIR)/%.cu, $(OBJ_DIR)/%, $(TEST_SRCS))

# Default: build the main simulator
.PHONY: all clean tests

all: $(OBJ_DIR) $(OBJ_DIR)/$(TARGET)

$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

# Build main simulator
$(OBJ_DIR)/$(TARGET): $(MAIN_SRC) board.cuh game.cuh movegen.cuh board_print.cuh recording.cuh
	$(NVCC) $(NVCCFLAGS) $(LDFLAGS) -o $@ $<

# Build all test binaries
tests: $(OBJ_DIR) $(TEST_BINS)

$(OBJ_DIR)/%: $(SRC_DIR)/%.cu board.cuh game.cuh movegen.cuh board_print.cuh recording.cuh
	$(NVCC) $(NVCCFLAGS) -o $@ $<

# Run all tests
run_tests: tests
	@for t in $(TEST_BINS); do \
		echo "--- Running $$t ---"; \
		$$t; \
	done

# Clean build artifacts
clean:
	rm -rf $(OBJ_DIR)
