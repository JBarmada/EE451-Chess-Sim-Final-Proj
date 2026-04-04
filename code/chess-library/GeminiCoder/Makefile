CXX = g++
CXXFLAGS = -std=c++17 -O3 -DNDEBUG

# Set MODE=serial or MODE=openmp when invoking make.
MODE ?= serial

ifeq ($(MODE),openmp)
SRC = openMP.cpp
CXXFLAGS += -fopenmp
else
SRC = serial.cpp
endif

# Build all targets
.PHONY: all clean

all: sim100k sim1m sim10m sim100m sim1b

# 100k games
sim100k: $(SRC)
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=100000 $(SRC) -o sim100k

# 1m games
sim1m: $(SRC)
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=1000000 $(SRC) -o sim1m

# 10m games
sim10m: $(SRC)
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=10000000 $(SRC) -o sim10m

# 100m games
sim100m: $(SRC)
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=100000000 $(SRC) -o sim100m

# 1b games
sim1b: $(SRC)
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=1000000000 $(SRC) -o sim1b

clean:
	rm -f sim100k sim1m sim10m sim100m sim1b
