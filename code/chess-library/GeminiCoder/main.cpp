/*
g++ -std=c++17 -O3 -DNDEBUG main.cpp -o sim
./sim.exe

To compile with different game counts, use:
  g++ -std=c++17 -O3 -DNDEBUG -DNUM_GAMES=100000 main.cpp -o sim100k
  g++ -std=c++17 -O3 -DNDEBUG -DNUM_GAMES=1000000 main.cpp -o sim1m
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
#include "chess.hpp"

#ifndef NUM_GAMES
#define NUM_GAMES 10000000
#endif

using namespace chess;

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

// Global aggregations for N games (Thread-safe if instantiated per thread)
struct AggregateStats {
    int totalGames = 0;
    int whiteWins = 0;
    int blackWins = 0;
    int draws = 0;
    
    std::map<std::string, int> terminationCounts;
    std::vector<int> gameLengths; // Store lengths to calculate distribution/variance
    
    int gamesWithAnyCapture = 0;
    int gamesWithQueenCapture = 0;
    std::map<PieceType, int> firstCapturedCounts;
    std::map<PieceType, int> checkmatingPieceCounts;
};

// Helper function to extract PieceType safely (handles en passant)
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
        // 1. Generate legal moves exactly ONCE per ply
        Movelist moves;
        movegen::legalmoves(moves, board);

        // 2. Check for Checkmate or Stalemate (No moves available)
        if (moves.empty()) {
            if (board.inCheck()) {
                stats.terminationReason = "CHECKMATE";
                stats.checkmatingPiece = lastMovedPiece; // Piece that delivered mate
                
                // The side to move is mated. The other side wins.
                stats.winner = (board.sideToMove() == Color::WHITE) ? "Black" : "White";
            } else {
                stats.terminationReason = "STALEMATE";
                stats.winner = "Draw";
            }
            break;
        }

        // 3. Fast checks for Draws by rule (avoids redundant move generation)
        if (board.isRepetition()) {
            stats.terminationReason = "THREEFOLD_REPETITION";
            stats.winner = "Draw";
            break;
        }
        
        if (board.isHalfMoveDraw()) {
            // isHalfMoveDraw captures both 50-move rule and Insufficient Material
            auto drawType = board.getHalfMoveDrawType();
            if (drawType.first == GameResultReason::FIFTY_MOVE_RULE) {
                stats.terminationReason = "FIFTY_MOVES";
            } else {
                stats.terminationReason = "INSUFFICIENT_MATERIAL";
            }
            stats.winner = "Draw";
            break;
        }

        // 4. Pick a random move
        std::uniform_int_distribution<int> dist(0, moves.size() - 1);
        Move randomMove = moves[dist(rng)];

        // Event Analytics
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
    
    // Updated Win/Loss Logic
    if (game.winner == "White") agg.whiteWins++;
    else if (game.winner == "Black") agg.blackWins++;
    else agg.draws++;

    if (game.anyCapture) agg.gamesWithAnyCapture++;
    if (game.queenCaptured) agg.gamesWithQueenCapture++;
    if (game.firstCapturedPiece != PieceType::NONE) agg.firstCapturedCounts[game.firstCapturedPiece]++;
    if (game.checkmatingPiece != PieceType::NONE) agg.checkmatingPieceCounts[game.checkmatingPiece]++;
}

int main() {
    std::random_device rd;
    std::mt19937 rng(rd());
    AggregateStats globalStats;
    
    std::cout << "Simulating " << NUM_GAMES << " games..." << std::endl;

    // Start Timer
    auto start_time = std::chrono::high_resolution_clock::now();

    for (int i = 0; i < NUM_GAMES; ++i) {
        GameAnalytics gameResult = simulateRandomGame(rng);
        aggregateGame(globalStats, gameResult);
    }

    // End Timer
    auto end_time = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> execution_time = end_time - start_time;
    
    double throughput = NUM_GAMES / execution_time.count();

    // Output Performance Metrics
    std::cout << "\n--- PERFORMANCE ---" << std::endl;
    std::cout << "Execution Time: " << execution_time.count() << " seconds\n";
    std::cout << "Throughput: " << std::fixed << std::setprecision(2) << throughput << " games/sec\n";

    // Output Core Outcomes
    std::cout << "\n--- CORE OUTCOMES ---" << std::endl;
    std::cout << "White Wins: " << (double)globalStats.whiteWins / NUM_GAMES * 100 << "%\n";
    std::cout << "Black Wins: " << (double)globalStats.blackWins / NUM_GAMES * 100 << "%\n";
    std::cout << "Draws: " << (double)globalStats.draws / NUM_GAMES * 100 << "%\n";

    // Output Game-Shape Metrics
    double avgPly = std::accumulate(globalStats.gameLengths.begin(), globalStats.gameLengths.end(), 0.0) / NUM_GAMES;
    std::cout << "\n--- GAME SHAPE ---" << std::endl;
    std::cout << "Average Length: " << avgPly << " plies\n";
    for (const auto& [reason, count] : globalStats.terminationCounts) {
        std::cout << reason << ": " << (double)count / NUM_GAMES * 100 << "%\n";
    }

    // Output Event Statistics
    std::cout << "\n--- EVENT STATISTICS ---" << std::endl;
    std::cout << "Games with ANY capture: " << (double)globalStats.gamesWithAnyCapture / NUM_GAMES * 100 << "%\n";
    std::cout << "Games with a Queen capture: " << (double)globalStats.gamesWithQueenCapture / NUM_GAMES * 100 << "%\n";

    // Helper to map PieceType integer to a string name
    const char* pieceNames[] = {"None", "Pawn", "Knight", "Bishop", "Rook", "Queen", "King"};

    std::cout << "\nFirst Captured Piece Distribution:\n";
    for (const auto& [piece, count] : globalStats.firstCapturedCounts) {
        if (piece != PieceType::NONE) {
            std::cout << pieceNames[static_cast<int>(piece)] << ": " << (double)count / NUM_GAMES * 100 << "%\n";
        }
    }

    std::cout << "\nCheckmating Piece Distribution:\n";
    for (const auto& [piece, count] : globalStats.checkmatingPieceCounts) {
        if (piece != PieceType::NONE) {
            // Note: Calculating percentage based on NUM_GAMES (total games), not just decisive games
            std::cout << pieceNames[static_cast<int>(piece)] << ": " << (double)count / NUM_GAMES * 100 << "%\n";
        }
    }

    return 0;
}