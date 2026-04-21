/*
g++ -std=c++17 -O3 -DNDEBUG -fopenmp main.cpp -o sim
./sim

To compile with different game counts, use:
  g++ -std=c++17 -O3 -DNDEBUG -fopenmp -DNUM_GAMES=100000 main.cpp -o sim100k
  g++ -std=c++17 -O3 -DNDEBUG -fopenmp -DNUM_GAMES=1000000 main.cpp -o sim1m
  etc.

Or use the provided Makefile: make sim1m sim10m sim100m
*/
#include <iostream>
#include <vector>
#include <random>
#include <numeric>
#include <chrono>
#include <map>
#include <iomanip>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <omp.h>
#include "chess.hpp"

#ifndef NUM_GAMES
#define NUM_GAMES 10000000
#endif

using namespace chess;

std::string formatSimSize(long long games) {
    if (games >= 1000000000LL && games % 1000000000LL == 0) {
        return std::to_string(games / 1000000000LL) + "b";
    }
    if (games >= 1000000LL && games % 1000000LL == 0) {
        return std::to_string(games / 1000000LL) + "m";
    }
    if (games >= 1000LL && games % 1000LL == 0) {
        return std::to_string(games / 1000LL) + "k";
    }
    return std::to_string(games);
}

// Single game statistics
struct GameAnalytics {
    int totalPly = 0;
    bool anyCapture = false;
    bool queenCaptured = false;
    PieceType firstCapturedPiece = PieceType::NONE;
    PieceType checkmatingPiece = PieceType::NONE;
    std::string terminationReason;
    std::string winner;
};

// Global aggregations for N games (one instance per thread)
struct AggregateStats {
    int totalGames = 0;
    int whiteWins = 0;
    int blackWins = 0;
    int draws = 0;

    std::map<std::string, int> terminationCounts;
    std::vector<int> gameLengths;

    int gamesWithAnyCapture = 0;
    int gamesWithQueenCapture = 0;
    std::map<PieceType, int> firstCapturedCounts;
    std::map<PieceType, int> checkmatingPieceCounts;
};

PieceType getCapturedPiece(const Board& board, const Move& move) {
    if (move.typeOf() == Move::ENPASSANT) {
        return PieceType::PAWN;
    }
    return board.at(move.to()).type();
}

GameAnalytics simulateRandomGame(std::mt19937& rng) {
    Board board;
    GameAnalytics stats;
    PieceType lastMovedPiece = PieceType::NONE;

    while (true) {
        Movelist moves;
        movegen::legalmoves(moves, board);

        if (moves.empty()) {
            if (board.inCheck()) {
                stats.terminationReason = "CHECKMATE";
                stats.checkmatingPiece = lastMovedPiece;
                stats.winner = (board.sideToMove() == Color::WHITE) ? "Black" : "White";
            } else {
                stats.terminationReason = "STALEMATE";
                stats.winner = "Draw";
            }
            break;
        }

        if (board.isRepetition()) {
            stats.terminationReason = "THREEFOLD_REPETITION";
            stats.winner = "Draw";
            break;
        }

        if (board.isHalfMoveDraw()) {
            auto drawType = board.getHalfMoveDrawType();
            if (drawType.first == GameResultReason::FIFTY_MOVE_RULE) {
                stats.terminationReason = "FIFTY_MOVES";
            } else {
                stats.terminationReason = "INSUFFICIENT_MATERIAL";
            }
            stats.winner = "Draw";
            break;
        }

        std::uniform_int_distribution<int> dist(0, moves.size() - 1);
        Move randomMove = moves[dist(rng)];

        if (board.isCapture(randomMove)) {
            PieceType captured = getCapturedPiece(board, randomMove);
            if (!stats.anyCapture) {
                stats.firstCapturedPiece = captured;
            }
            stats.anyCapture = true;
            if (captured == PieceType::QUEEN) {
                stats.queenCaptured = true;
            }
        }

        lastMovedPiece = board.at(randomMove.from()).type();
        board.makeMove(randomMove);
        stats.totalPly++;
    }

    return stats;
}

void aggregateGame(AggregateStats& agg, const GameAnalytics& game) {
    agg.totalGames++;
    agg.gameLengths.push_back(game.totalPly);
    agg.terminationCounts[game.terminationReason]++;

    if (game.winner == "White") agg.whiteWins++;
    else if (game.winner == "Black") agg.blackWins++;
    else agg.draws++;

    if (game.anyCapture) agg.gamesWithAnyCapture++;
    if (game.queenCaptured) agg.gamesWithQueenCapture++;
    if (game.firstCapturedPiece != PieceType::NONE) agg.firstCapturedCounts[game.firstCapturedPiece]++;
    if (game.checkmatingPiece != PieceType::NONE) agg.checkmatingPieceCounts[game.checkmatingPiece]++;
}

// Merge src into dst
void mergeStats(AggregateStats& dst, const AggregateStats& src) {
    dst.totalGames           += src.totalGames;
    dst.whiteWins            += src.whiteWins;
    dst.blackWins            += src.blackWins;
    dst.draws                += src.draws;
    dst.gamesWithAnyCapture  += src.gamesWithAnyCapture;
    dst.gamesWithQueenCapture+= src.gamesWithQueenCapture;

    dst.gameLengths.insert(dst.gameLengths.end(),
                           src.gameLengths.begin(), src.gameLengths.end());

    for (const auto& [k, v] : src.terminationCounts)
        dst.terminationCounts[k] += v;
    for (const auto& [k, v] : src.firstCapturedCounts)
        dst.firstCapturedCounts[k] += v;
    for (const auto& [k, v] : src.checkmatingPieceCounts)
        dst.checkmatingPieceCounts[k] += v;
}

int main() {
    // Seed each thread's RNG from a single master device
    std::random_device rd;
    const int numThreads = omp_get_max_threads();

    // Pre-generate one seed per thread so seeding is deterministic and race-free
    std::vector<uint32_t> seeds(numThreads);
    for (auto& s : seeds) s = rd();

    AggregateStats globalStats;
    // Reserve to avoid reallocations during the merge
    globalStats.gameLengths.reserve(NUM_GAMES);

    std::cout << "Simulating " << NUM_GAMES << " games on "
              << numThreads << " threads...\n";

    auto start_time = std::chrono::high_resolution_clock::now();

    // Each thread owns its RNG and its local stats — no locking needed.
    #pragma omp parallel num_threads(numThreads)
    {
        const int tid = omp_get_thread_num();
        std::mt19937 rng(seeds[tid]);

        AggregateStats localStats;
        // Give each thread a fair share; the schedule(static) below handles
        // any remainder automatically.
        localStats.gameLengths.reserve(NUM_GAMES / numThreads + 1);

        #pragma omp for schedule(static)
        for (int i = 0; i < NUM_GAMES; ++i) {
            GameAnalytics result = simulateRandomGame(rng);
            aggregateGame(localStats, result);
        }

        // Sequential merge — one thread at a time, but this is O(threads) not O(games)
        #pragma omp critical
        mergeStats(globalStats, localStats);
    }

    auto end_time = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> execution_time = end_time - start_time;
    double throughput = NUM_GAMES / execution_time.count();

        std::ostringstream report;

    // --- Output (unchanged from original) ---
        report << "\n--- PERFORMANCE ---\n";
        report << "Execution Time: " << execution_time.count() << " seconds\n";
        report << "Throughput: " << std::fixed << std::setprecision(2)
            << throughput << " games/sec\n";

        report << "\n--- CORE OUTCOMES ---\n";
        report << "White Wins: " << (double)globalStats.whiteWins / NUM_GAMES * 100 << "%\n";
        report << "Black Wins: " << (double)globalStats.blackWins / NUM_GAMES * 100 << "%\n";
        report << "Draws: "      << (double)globalStats.draws      / NUM_GAMES * 100 << "%\n";

    double avgPly = std::accumulate(globalStats.gameLengths.begin(),
                                    globalStats.gameLengths.end(), 0.0) / NUM_GAMES;
        report << "\n--- GAME SHAPE ---\n";
        report << "Average Length: " << avgPly << " plies\n";
    for (const auto& [reason, count] : globalStats.terminationCounts)
         report << reason << ": " << (double)count / NUM_GAMES * 100 << "%\n";

        report << "\n--- EVENT STATISTICS ---\n";
        report << "Games with ANY capture: "
            << (double)globalStats.gamesWithAnyCapture  / NUM_GAMES * 100 << "%\n";
        report << "Games with a Queen capture: "
            << (double)globalStats.gamesWithQueenCapture / NUM_GAMES * 100 << "%\n";

    const char* pieceNames[] = {"None","Pawn","Knight","Bishop","Rook","Queen","King"};

    report << "\nFirst Captured Piece Distribution:\n";
    for (const auto& [piece, count] : globalStats.firstCapturedCounts)
        if (piece != PieceType::NONE)
            report << pieceNames[static_cast<int>(piece)] << ": "
                   << (double)count / NUM_GAMES * 100 << "%\n";

    report << "\nCheckmating Piece Distribution:\n";
    for (const auto& [piece, count] : globalStats.checkmatingPieceCounts)
        if (piece != PieceType::NONE)
            report << pieceNames[static_cast<int>(piece)] << ": "
                   << (double)count / NUM_GAMES * 100 << "%\n";

    const std::string simSize = formatSimSize(NUM_GAMES);
    const char* runDir = std::getenv("CHESS_RUN_DIR");
    const std::filesystem::path resultsDir = std::filesystem::path(runDir ? runDir : "results") /
                                             (simSize + "_openmp") /
                                             std::to_string(numThreads);
    std::filesystem::create_directories(resultsDir);
    const std::filesystem::path outputFile = resultsDir / "summary.txt";

    std::ofstream out(outputFile);
    if (out) {
        out << report.str();
    } else {
        std::cerr << "Failed to write results file: " << outputFile << "\n";
    }

    std::cout << report.str();
    std::cout << "\nSaved results to " << outputFile.string() << "\n";

    return 0;
}