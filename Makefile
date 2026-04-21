CXX = g++
CXXFLAGS = -std=c++17 -O3 -DNDEBUG
OPENMP_FLAGS = -fopenmp

SERIAL_SRC   = CPU_Serial/serial.cpp
OPENMP_SRC   = CPU_OpenMP/openMP.cpp
SERIAL_INC   = -ICPU_Serial
OPENMP_INC   = -ICPU_OpenMP

SERIAL_TARGETS = sim_serial_1k sim_serial_10k sim_serial_100k sim_serial_1m sim_serial_10m sim_serial_100m sim_serial_1b
OPENMP_TARGETS = sim_openmp_1k sim_openmp_10k sim_openmp_100k sim_openmp_1m sim_openmp_10m sim_openmp_100m sim_openmp_1b

MODE ?= both

ifneq (,$(filter $(MODE),serial Serial SERIAL))
DEFAULT_TARGETS = $(SERIAL_TARGETS)
else ifneq (,$(filter $(MODE),openmp openMP OpenMP OMP omp))
DEFAULT_TARGETS = $(OPENMP_TARGETS)
else ifneq (,$(filter $(MODE),both all ALL))
DEFAULT_TARGETS = $(SERIAL_TARGETS) $(OPENMP_TARGETS)
else
$(error Unsupported MODE='$(MODE)'. Use MODE=serial, MODE=openmp, or MODE=both)
endif

.PHONY: all serial openmp clean

all: $(DEFAULT_TARGETS)
serial: $(SERIAL_TARGETS)
openmp: $(OPENMP_TARGETS)

# Serial builds
sim_serial_1k: $(SERIAL_SRC)
	$(CXX) $(CXXFLAGS) $(SERIAL_INC) -DNUM_GAMES=1000 $< -o $@

sim_serial_10k: $(SERIAL_SRC)
	$(CXX) $(CXXFLAGS) $(SERIAL_INC) -DNUM_GAMES=10000 $< -o $@

sim_serial_100k: $(SERIAL_SRC)
	$(CXX) $(CXXFLAGS) $(SERIAL_INC) -DNUM_GAMES=100000 $< -o $@

sim_serial_1m: $(SERIAL_SRC)
	$(CXX) $(CXXFLAGS) $(SERIAL_INC) -DNUM_GAMES=1000000 $< -o $@

sim_serial_10m: $(SERIAL_SRC)
	$(CXX) $(CXXFLAGS) $(SERIAL_INC) -DNUM_GAMES=10000000 $< -o $@

sim_serial_100m: $(SERIAL_SRC)
	$(CXX) $(CXXFLAGS) $(SERIAL_INC) -DNUM_GAMES=100000000 $< -o $@

sim_serial_1b: $(SERIAL_SRC)
	$(CXX) $(CXXFLAGS) $(SERIAL_INC) -DNUM_GAMES=1000000000 $< -o $@

# OpenMP builds
sim_openmp_1k: $(OPENMP_SRC)
	$(CXX) $(CXXFLAGS) $(OPENMP_INC) $(OPENMP_FLAGS) -DNUM_GAMES=1000 $< -o $@

sim_openmp_10k: $(OPENMP_SRC)
	$(CXX) $(CXXFLAGS) $(OPENMP_INC) $(OPENMP_FLAGS) -DNUM_GAMES=10000 $< -o $@

sim_openmp_100k: $(OPENMP_SRC)
	$(CXX) $(CXXFLAGS) $(OPENMP_INC) $(OPENMP_FLAGS) -DNUM_GAMES=100000 $< -o $@

sim_openmp_1m: $(OPENMP_SRC)
	$(CXX) $(CXXFLAGS) $(OPENMP_INC) $(OPENMP_FLAGS) -DNUM_GAMES=1000000 $< -o $@

sim_openmp_10m: $(OPENMP_SRC)
	$(CXX) $(CXXFLAGS) $(OPENMP_INC) $(OPENMP_FLAGS) -DNUM_GAMES=10000000 $< -o $@

sim_openmp_100m: $(OPENMP_SRC)
	$(CXX) $(CXXFLAGS) $(OPENMP_INC) $(OPENMP_FLAGS) -DNUM_GAMES=100000000 $< -o $@

sim_openmp_1b: $(OPENMP_SRC)
	$(CXX) $(CXXFLAGS) $(OPENMP_INC) $(OPENMP_FLAGS) -DNUM_GAMES=1000000000 $< -o $@

clean:
	rm -f $(SERIAL_TARGETS) $(OPENMP_TARGETS)
