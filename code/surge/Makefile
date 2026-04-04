CXX := g++
CXXFLAGS := -std=c++17 -O2 -Wall -Wextra
SRC_DIR := src
SOURCES := $(wildcard $(SRC_DIR)/*.cpp)
TARGET := surge.exe

.PHONY: all clean run perft

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CXX) $(CXXFLAGS) $(SOURCES) -o $(TARGET)

run: $(TARGET)
	./$(TARGET)

perft: $(TARGET)
	./$(TARGET) --perft 6

clean:
	rm -f $(TARGET)
