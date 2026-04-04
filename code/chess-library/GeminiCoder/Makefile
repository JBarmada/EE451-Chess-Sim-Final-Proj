CXX = g++
CXXFLAGS = -std=c++17 -O3 -DNDEBUG

# Build all targets
.PHONY: all clean

all: sim100k sim1m sim10m sim100m sim1b

# 100k games
sim100k: main.cpp
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=100000 main.cpp -o sim100k

# 1m games
sim1m: main.cpp
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=1000000 main.cpp -o sim1m

# 10m games
sim10m: main.cpp
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=10000000 main.cpp -o sim10m

# 100m games
sim100m: main.cpp
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=100000000 main.cpp -o sim100m

# 1b games
sim1b: main.cpp
	$(CXX) $(CXXFLAGS) -DNUM_GAMES=1000000000 main.cpp -o sim1b

clean:
	rm -f sim100k sim1m sim10m sim100m sim1b
