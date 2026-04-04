# surge

## A fast bitboard-based legal chess move generator, written in C++

### Features

* Magic Bitboard sliding attacks and pre-generated attack tables
* Make-Unmake position class
* 16-bit Move representation
* Extremely fast bulk-counted perft (over 180,000,000 NPS, single-threaded, without hashtable)
* Simple design for use in any chess engine

### Random chess simulator

This build also includes a serial random legal-game simulator. It plays random legal moves until the game ends by mate, stalemate, repetition, the 50-move or 75-move rule, insufficient material, or a ply cap.

### Build

From the `code/surge` directory, compile all sources into a single executable:

```bash
g++ -std=c++17 -O2 src/*.cpp -o surge.exe
```

### Run

Run the simulator from the same directory:

```bash
./surge.exe
```

Useful flags:

* `--games N` run `N` random games in sequence
* `--seed N` use a fixed seed for reproducible runs
* `--fen "..."` start from a custom FEN position
* `--max-plies N` stop a game after `N` plies as a safety cap
* `--log-moves` print the UCI move list for each game
* `--log-fen` print the FEN after each ply
* `--json` or `--ndjson` emit one JSON record per game plus a final batch summary record
* `--quiet` suppress per-game summaries
* `--perft D` run perft at depth `D` instead of the simulator

Examples:

```bash
./surge.exe --seed 12345 --games 1 --log-moves
./surge.exe --games 1000 --seed 42 --quiet
./surge.exe --games 100 --seed 7 --json
./surge.exe --fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -" --max-plies 500
```


