CXX = g++
CXXFLAGS = -std=c++17 -O3 -DNDEBUG

# Set MODE=serial or MODE=openmp when invoking make.
# If MODE is not provided, build both variants.
MODE ?= both

SERIAL_SRC = serial.cpp
OPENMP_SRC = openMP.cpp
OPENMP_FLAGS = -fopenmp

SERIAL_TARGETS = sim100k_serial sim1m_serial sim10m_serial sim100m_serial sim1b_serial
OPENMP_TARGETS = sim100k_openmp sim1m_openmp sim10m_openmp sim100m_openmp sim1b_openmp
LEGACY_TARGETS = sim sim10k sim100k sim1m sim10m sim100m sim1b
SANITY_TARGETS = sanity_serial sanity_openmp

ifneq (,$(filter $(MODE),serial Serial SERIAL))
DEFAULT_TARGETS = $(SERIAL_TARGETS)
else ifneq (,$(filter $(MODE),openmp openMP OpenMP OMP omp))
DEFAULT_TARGETS = $(OPENMP_TARGETS)
else ifneq (,$(filter $(MODE),both all ALL))
DEFAULT_TARGETS = $(SERIAL_TARGETS) $(OPENMP_TARGETS)
else
$(error Unsupported MODE='$(MODE)'. Use MODE=serial, MODE=openmp, or MODE=both)
endif

# Build targets
.PHONY: all serial openmp clean sim100k sim1m sim10m sim100m sim1b

all: $(DEFAULT_TARGETS)

serial: $(SERIAL_TARGETS)
openmp: $(OPENMP_TARGETS)

# Backward-compatible aliases (default to serial naming)
sim100k: sim100k_serial
sim1m: sim1m_serial
sim10m: sim10m_serial
sim100m: sim100m_serial
sim1b: sim1b_serial

# Serial builds
sim100k_serial: $(SERIAL_SRC)
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=100000 $(SERIAL_SRC) -o sim100k_serial

sim1m_serial: $(SERIAL_SRC)
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=1000000 $(SERIAL_SRC) -o sim1m_serial

sim10m_serial: $(SERIAL_SRC)
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=10000000 $(SERIAL_SRC) -o sim10m_serial

sim100m_serial: $(SERIAL_SRC)
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=100000000 $(SERIAL_SRC) -o sim100m_serial

sim1b_serial: $(SERIAL_SRC)
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=1000000000 $(SERIAL_SRC) -o sim1b_serial

# OpenMP builds
sim100k_openmp: $(OPENMP_SRC)
	$(CXX) $(CXXFLAGS) $(OPENMP_FLAGS) -DNUM_GAMES=100000 $(OPENMP_SRC) -o sim100k_openmp

sim1m_openmp: $(OPENMP_SRC)
	$(CXX) $(CXXFLAGS) $(OPENMP_FLAGS) -DNUM_GAMES=1000000 $(OPENMP_SRC) -o sim1m_openmp

sim10m_openmp: $(OPENMP_SRC)
	$(CXX) $(CXXFLAGS) $(OPENMP_FLAGS) -DNUM_GAMES=10000000 $(OPENMP_SRC) -o sim10m_openmp

sim100m_openmp: $(OPENMP_SRC)
	$(CXX) $(CXXFLAGS) $(OPENMP_FLAGS) -DNUM_GAMES=100000000 $(OPENMP_SRC) -o sim100m_openmp

sim1b_openmp: $(OPENMP_SRC)
	$(CXX) $(CXXFLAGS) $(OPENMP_FLAGS) -DNUM_GAMES=1000000000 $(OPENMP_SRC) -o sim1b_openmp

clean:
	rm -f $(SERIAL_TARGETS) $(OPENMP_TARGETS) $(LEGACY_TARGETS) $(SANITY_TARGETS)
	rm -f $(SERIAL_TARGETS:%=%.exe) $(OPENMP_TARGETS:%=%.exe) $(LEGACY_TARGETS:%=%.exe) $(SANITY_TARGETS:%=%.exe)
