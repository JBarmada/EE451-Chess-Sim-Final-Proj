/*
# Batch random chess simulator
#
# Build and run:
#   g++ -std=c++17 -O3 main.cpp -o simulator
#   ./simulator [games] [seed] [csv_path]
#
# Supported inputs:
#   - games: number of random games to simulate
#   - seed: optional RNG seed for reproducible runs
#   - csv_path: optional file path to write one row per game
#   - --games=N, --seed=S, --csv=path are also accepted
#   - -h or --help prints usage and exits
#
# Outputs:
#   - Console summary with throughput, runtime, outcomes, and game-shape stats
#   - Optional CSV with one record per game including runtime, plies, captures,
#     checks, branching factor, termination reason, winner, and final FEN
#
# Notes:
#   - The simulation is structured so the per-game work is isolated and can be
#     parallelized later by distributing game indices across worker threads.
#   - Seed 0 is valid; if no seed is provided, a random seed is generated.
*/

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <sstream>
#include <string>
#include <string_view>
#include <stdexcept>

#include <chess.hpp>

using namespace chess;

namespace {

using Clock = std::chrono::steady_clock;

constexpr std::size_t kPieceTypeCount = 6;

struct RunningStats {
    std::uint64_t count = 0;
    double mean = 0.0;
    double m2 = 0.0;

    void add(double value) {
        ++count;
        const double delta = value - mean;
        mean += delta / static_cast<double>(count);
        const double delta2 = value - mean;
        m2 += delta * delta2;
    }

    [[nodiscard]] double variance() const noexcept {
        return count > 1 ? m2 / static_cast<double>(count - 1) : 0.0;
    }

    [[nodiscard]] double stddev() const noexcept {
        return std::sqrt(variance());
    }
};

struct GameAnalytics {
    std::uint64_t seed = 0;
    std::uint64_t runtimeMicros = 0;

    int totalPly = 0;
    int totalCaptures = 0;
    int totalChecks = 0;
    int branchingSamples = 0;
    int maxBranchingFactor = 0;
    double branchingSum = 0.0;
    double avgBranchingFactor = 0.0;

    bool anyCapture = false;
    bool queenCaptured = false;

    PieceType firstCapturedPiece = PieceType::NONE;
    PieceType checkmateDeliveringPiece = PieceType::NONE;

    GameResultReason terminationReason = GameResultReason::NONE;
    GameResult terminalResult = GameResult::NONE;
    std::string winner;
    std::string finalFen;
};

struct BatchSummary {
    std::uint64_t games = 0;
    std::uint64_t whiteWins = 0;
    std::uint64_t blackWins = 0;
    std::uint64_t draws = 0;

    std::uint64_t checkmates = 0;
    std::uint64_t stalemates = 0;
    std::uint64_t insufficientMaterial = 0;
    std::uint64_t fiftyMoveRule = 0;
    std::uint64_t threefoldRepetition = 0;

    std::uint64_t anyCaptureGames = 0;
    std::uint64_t queenCaptureGames = 0;

    std::uint64_t totalPly = 0;
    std::uint64_t totalCaptures = 0;
    std::uint64_t totalChecks = 0;
    std::uint64_t totalBranchingSamples = 0;
    double totalBranchingSum = 0.0;

    RunningStats pliesPerGame;
    RunningStats runtimePerGame;
    RunningStats branchingPerGame;

    std::array<std::uint64_t, kPieceTypeCount> firstCaptureCounts = {};
    std::array<std::uint64_t, kPieceTypeCount> checkmatePieceCounts = {};

    void accumulate(const GameAnalytics& game) {
        ++games;
        totalPly += static_cast<std::uint64_t>(game.totalPly);
        totalCaptures += static_cast<std::uint64_t>(game.totalCaptures);
        totalChecks += static_cast<std::uint64_t>(game.totalChecks);
        totalBranchingSamples += static_cast<std::uint64_t>(game.branchingSamples);
        totalBranchingSum += game.branchingSum;

        pliesPerGame.add(static_cast<double>(game.totalPly));
        runtimePerGame.add(static_cast<double>(game.runtimeMicros));
        branchingPerGame.add(game.avgBranchingFactor);

        if (game.winner == "White") {
            ++whiteWins;
        } else if (game.winner == "Black") {
            ++blackWins;
        } else {
            ++draws;
        }

        switch (game.terminationReason) {
            case GameResultReason::CHECKMATE:
                ++checkmates;
                break;
            case GameResultReason::STALEMATE:
                ++stalemates;
                break;
            case GameResultReason::INSUFFICIENT_MATERIAL:
                ++insufficientMaterial;
                break;
            case GameResultReason::FIFTY_MOVE_RULE:
                ++fiftyMoveRule;
                break;
            case GameResultReason::THREEFOLD_REPETITION:
                ++threefoldRepetition;
                break;
            case GameResultReason::NONE:
                break;
        }

        if (game.anyCapture) {
            ++anyCaptureGames;
        }

        if (game.queenCaptured) {
            ++queenCaptureGames;
        }

        const auto firstCaptureIndex = pieceTypeIndex(game.firstCapturedPiece);
        if (firstCaptureIndex >= 0) {
            ++firstCaptureCounts[static_cast<std::size_t>(firstCaptureIndex)];
        }

        const auto matePieceIndex = pieceTypeIndex(game.checkmateDeliveringPiece);
        if (matePieceIndex >= 0) {
            ++checkmatePieceCounts[static_cast<std::size_t>(matePieceIndex)];
        }
    }
};

struct ProgramOptions {
    std::uint64_t games = 1;
    std::uint64_t seed = 0;
    bool seedProvided = false;
    std::string csvPath;
};

int pieceTypeIndex(PieceType pieceType);

std::string toString(GameResultReason reason) {
    switch (reason) {
        case GameResultReason::CHECKMATE:
            return "CHECKMATE";
        case GameResultReason::STALEMATE:
            return "STALEMATE";
        case GameResultReason::INSUFFICIENT_MATERIAL:
            return "INSUFFICIENT_MATERIAL";
        case GameResultReason::FIFTY_MOVE_RULE:
            return "FIFTY_MOVE_RULE";
        case GameResultReason::THREEFOLD_REPETITION:
            return "THREEFOLD_REPETITION";
        case GameResultReason::NONE:
            return "NONE";
    }

    return "UNKNOWN";
}

std::string toString(GameResult result) {
    switch (result) {
        case GameResult::WIN:
            return "WIN";
        case GameResult::LOSE:
            return "LOSE";
        case GameResult::DRAW:
            return "DRAW";
        case GameResult::NONE:
            return "NONE";
    }

    return "UNKNOWN";
}

std::string toString(PieceType pieceType) {
    switch (static_cast<int>(pieceType.internal())) {
        case static_cast<int>(PieceType::PAWN):
            return "PAWN";
        case static_cast<int>(PieceType::KNIGHT):
            return "KNIGHT";
        case static_cast<int>(PieceType::BISHOP):
            return "BISHOP";
        case static_cast<int>(PieceType::ROOK):
            return "ROOK";
        case static_cast<int>(PieceType::QUEEN):
            return "QUEEN";
        case static_cast<int>(PieceType::KING):
            return "KING";
        default:
            return "NONE";
    }
}

int pieceTypeIndex(PieceType pieceType) {
    const int value = static_cast<int>(pieceType.internal());
    if (value < 0 || value >= static_cast<int>(kPieceTypeCount)) {
        return -1;
    }

    return value;
}

std::string csvEscape(std::string_view value) {
    const bool needsQuotes = value.find_first_of(",\"\n\r") != std::string_view::npos;
    if (!needsQuotes) {
        return std::string(value);
    }

    std::string escaped;
    escaped.reserve(value.size() + 2);
    escaped.push_back('"');
    for (const char c : value) {
        if (c == '"') {
            escaped.push_back('"');
        }
        escaped.push_back(c);
    }
    escaped.push_back('"');
    return escaped;
}

std::uint64_t splitmix64(std::uint64_t value) {
    value += 0x9E3779B97F4A7C15ULL;
    value = (value ^ (value >> 30U)) * 0xBF58476D1CE4E5B9ULL;
    value = (value ^ (value >> 27U)) * 0x94D049BB133111EBULL;
    return value ^ (value >> 31U);
}

std::mt19937 makeRng(std::uint64_t baseSeed, std::uint64_t gameIndex) {
    const std::uint64_t mixed = splitmix64(baseSeed ^ splitmix64(gameIndex + 1ULL));
    const std::uint32_t low = static_cast<std::uint32_t>(mixed & 0xFFFFFFFFULL);
    const std::uint32_t high = static_cast<std::uint32_t>((mixed >> 32U) & 0xFFFFFFFFULL);
    std::seed_seq seq{low, high};
    return std::mt19937(seq);
}

std::string winnerForTerminal(const Board& board, GameResult result) {
    if (result == GameResult::DRAW || result == GameResult::NONE) {
        return "Draw";
    }

    if (result == GameResult::LOSE) {
        return board.sideToMove() == Color::WHITE ? "Black" : "White";
    }

    return board.sideToMove() == Color::WHITE ? "White" : "Black";
}

void recordTerminal(GameAnalytics& stats, const Board& board, GameResultReason reason, GameResult result) {
    stats.terminationReason = reason;
    stats.terminalResult = result;
    stats.winner = winnerForTerminal(board, result);
}

ProgramOptions parseOptions(int argc, char* argv[]) {
    ProgramOptions options;
    bool gamesSet = false;
    bool seedSet = false;

    for (int index = 1; index < argc; ++index) {
        const std::string argument = argv[index];

        if (argument == "-h" || argument == "--help") {
            std::cout << "Usage: " << argv[0] << " [games] [seed] [csv_path]\n"
                      << "   or: " << argv[0] << " --games=N --seed=S --csv=path\n";
            std::exit(0);
        }

        if (argument.rfind("--games=", 0) == 0) {
            options.games = std::stoull(argument.substr(8));
            gamesSet = true;
            continue;
        }

        if (argument.rfind("--seed=", 0) == 0) {
            options.seed = std::stoull(argument.substr(7));
            options.seedProvided = true;
            seedSet = true;
            continue;
        }

        if (argument.rfind("--csv=", 0) == 0) {
            options.csvPath = argument.substr(6);
            continue;
        }

        if (!gamesSet) {
            options.games = std::stoull(argument);
            gamesSet = true;
            continue;
        }

        if (!seedSet) {
            options.seed = std::stoull(argument);
            options.seedProvided = true;
            seedSet = true;
            continue;
        }

        if (options.csvPath.empty()) {
            options.csvPath = argument;
            continue;
        }

        throw std::runtime_error("Unexpected argument: " + argument);
    }

    if (!options.seedProvided) {
        std::random_device rd;
        options.seed = (static_cast<std::uint64_t>(rd()) << 32U) ^ static_cast<std::uint64_t>(rd());
    }

    return options;
}

GameAnalytics simulateRandomGame(std::mt19937& rng, std::uint64_t seed) {
    Board board;
    GameAnalytics stats;
    stats.seed = seed;
    const auto start = Clock::now();

    while (true) {
        auto [reason, result] = board.isGameOver();
        if (reason != GameResultReason::NONE) {
            recordTerminal(stats, board, reason, result);
            break;
        }

        Movelist moves;
        movegen::legalmoves(moves, board);
        if (moves.empty()) {
            auto [emptyReason, emptyResult] = board.isGameOver();
            recordTerminal(stats, board, emptyReason, emptyResult);
            break;
        }

        stats.branchingSum += static_cast<double>(moves.size());
        ++stats.branchingSamples;
        stats.maxBranchingFactor = std::max(stats.maxBranchingFactor, static_cast<int>(moves.size()));

        if (board.inCheck()) {
            ++stats.totalChecks;
        }

        std::uniform_int_distribution<int> distribution(0, static_cast<int>(moves.size()) - 1);
        const Move selectedMove = moves[distribution(rng)];
        const PieceType movingPiece = board.at<PieceType>(selectedMove.from());
        const PieceType capturedPiece = board.getCapturing<PieceType>(selectedMove);

        if (board.isCapture(selectedMove)) {
            ++stats.totalCaptures;
            stats.anyCapture = true;
            if (stats.firstCapturedPiece == PieceType::NONE) {
                stats.firstCapturedPiece = capturedPiece;
            }
            if (capturedPiece == PieceType::QUEEN) {
                stats.queenCaptured = true;
            }
        }

        board.makeMove(selectedMove);
        ++stats.totalPly;

        auto [nextReason, nextResult] = board.isGameOver();
        if (nextReason != GameResultReason::NONE) {
            recordTerminal(stats, board, nextReason, nextResult);
            if (nextReason == GameResultReason::CHECKMATE) {
                stats.checkmateDeliveringPiece = movingPiece;
            }
            break;
        }
    }

    if (stats.branchingSamples > 0) {
        stats.avgBranchingFactor = stats.branchingSum / static_cast<double>(stats.branchingSamples);
    }

    stats.finalFen = board.getFen();
    stats.runtimeMicros = static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::microseconds>(Clock::now() - start).count());
    return stats;
}

void writeCsvHeader(std::ofstream& csv) {
    csv << "game_index,seed,runtime_us,plies,total_captures,total_checks,avg_branching_factor,max_branching_factor,"
           "termination_reason,result,winner,any_capture,queen_capture,first_captured_piece,checkmate_piece,final_fen\n";
}

void writeCsvRow(std::ofstream& csv, std::uint64_t gameIndex, const GameAnalytics& game) {
    csv << gameIndex << ','
        << game.seed << ','
        << game.runtimeMicros << ','
        << game.totalPly << ','
        << game.totalCaptures << ','
        << game.totalChecks << ','
        << std::fixed << std::setprecision(6) << game.avgBranchingFactor << ','
        << game.maxBranchingFactor << ','
        << csvEscape(toString(game.terminationReason)) << ','
        << csvEscape(toString(game.terminalResult)) << ','
        << csvEscape(game.winner) << ','
        << (game.anyCapture ? 1 : 0) << ','
        << (game.queenCaptured ? 1 : 0) << ','
        << csvEscape(toString(game.firstCapturedPiece)) << ','
        << csvEscape(toString(game.checkmateDeliveringPiece)) << ','
        << csvEscape(game.finalFen) << '\n';
}

void printSummary(const BatchSummary& summary, std::chrono::microseconds elapsed) {
    const double seconds = static_cast<double>(elapsed.count()) / 1'000'000.0;
    const double gamesPerSecond = seconds > 0.0 ? static_cast<double>(summary.games) / seconds : 0.0;
    const double pliesPerSecond = seconds > 0.0 ? static_cast<double>(summary.totalPly) / seconds : 0.0;

    std::cout << std::fixed << std::setprecision(3);
    std::cout << "Games: " << summary.games << '\n';
    std::cout << "Elapsed seconds: " << seconds << '\n';
    std::cout << "Throughput: " << gamesPerSecond << " games/s" << '\n';
    std::cout << "Throughput: " << pliesPerSecond << " plies/s" << '\n';
    std::cout << "Average runtime per game: " << (summary.runtimePerGame.mean / 1000.0) << " ms" << '\n';
    std::cout << "White wins: " << summary.whiteWins << '\n';
    std::cout << "Black wins: " << summary.blackWins << '\n';
    std::cout << "Draws: " << summary.draws << '\n';
    std::cout << "Average plies per game: " << summary.pliesPerGame.mean << " (stddev " << summary.pliesPerGame.stddev() << ')' << '\n';
    std::cout << "Average branching factor: " << (summary.totalBranchingSamples > 0 ? summary.totalBranchingSum / static_cast<double>(summary.totalBranchingSamples) : 0.0) << '\n';
    std::cout << "Any capture rate: " << (summary.games > 0 ? 100.0 * static_cast<double>(summary.anyCaptureGames) / static_cast<double>(summary.games) : 0.0) << "%" << '\n';
    std::cout << "Queen capture rate: " << (summary.games > 0 ? 100.0 * static_cast<double>(summary.queenCaptureGames) / static_cast<double>(summary.games) : 0.0) << "%" << '\n';
    std::cout << "Checkmates: " << summary.checkmates << '\n';
    std::cout << "Stalemates: " << summary.stalemates << '\n';
    std::cout << "Insufficient material: " << summary.insufficientMaterial << '\n';
    std::cout << "Fifty-move rule: " << summary.fiftyMoveRule << '\n';
    std::cout << "Threefold repetition: " << summary.threefoldRepetition << '\n';

    std::cout << "First captured piece distribution:" << '\n';
    for (std::size_t index = 0; index < kPieceTypeCount; ++index) {
        std::cout << "  " << toString(PieceType(static_cast<PieceType::underlying>(index))) << ": "
                  << summary.firstCaptureCounts[index] << '\n';
    }

    std::cout << "Checkmating piece distribution:" << '\n';
    for (std::size_t index = 0; index < kPieceTypeCount; ++index) {
        std::cout << "  " << toString(PieceType(static_cast<PieceType::underlying>(index))) << ": "
                  << summary.checkmatePieceCounts[index] << '\n';
    }
}

}  // namespace

int main(int argc, char* argv[]) {
    try {
        const ProgramOptions options = parseOptions(argc, argv);

        std::ofstream csv;
        if (!options.csvPath.empty()) {
            csv.open(options.csvPath, std::ios::out | std::ios::trunc);
            if (!csv.is_open()) {
                throw std::runtime_error("Failed to open CSV output file: " + options.csvPath);
            }
            writeCsvHeader(csv);
        }

        BatchSummary summary;
        const auto batchStart = Clock::now();

        for (std::uint64_t gameIndex = 0; gameIndex < options.games; ++gameIndex) {
            const std::uint64_t gameSeed = splitmix64(options.seed + gameIndex);
            std::mt19937 rng = makeRng(options.seed, gameIndex);
            GameAnalytics result = simulateRandomGame(rng, gameSeed);
            summary.accumulate(result);

            if (csv.is_open()) {
                writeCsvRow(csv, gameIndex, result);
            }
        }

        const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(Clock::now() - batchStart);
        printSummary(summary, elapsed);

        if (csv.is_open()) {
            csv.flush();
        }

        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Error: " << error.what() << '\n';
        return 1;
    }
}