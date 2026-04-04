#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <random>
#include <string>
#include <unordered_map>
#include <type_traits>
#include <vector>

#include "tables.h"
#include "position.h"
#include "types.h"

namespace {

constexpr std::size_t POSITION_HISTORY_LIMIT = 255;

enum class TerminalReason {
	None,
	Checkmate,
	Stalemate,
	ThreefoldRepetition,
	FivefoldRepetition,
	FiftyMoveRule,
	SeventyFiveMoveRule,
	InsufficientMaterial,
	PlyCap
};

struct SimulationOptions {
	std::size_t games = 1;
	std::uint64_t seed = 0;
	bool has_seed = false;
	std::size_t max_plies = POSITION_HISTORY_LIMIT;
	bool json_output = false;
	bool log_moves = false;
	bool log_fens = false;
	bool summary = true;
	bool run_perft = false;
	unsigned int perft_depth = 0;
	std::string start_fen = DEFAULT_FEN;
};

struct GameReport {
	TerminalReason reason = TerminalReason::None;
	Color winner = WHITE;
	std::size_t plies = 0;
	std::size_t white_captures = 0;
	std::size_t black_captures = 0;
	std::size_t white_promotions = 0;
	std::size_t black_promotions = 0;
	std::size_t white_queen_captures = 0;
	std::size_t black_queen_captures = 0;
	std::int64_t white_material_lost = 0;
	std::int64_t black_material_lost = 0;
	std::vector<std::string> move_log;
	std::vector<std::string> fen_log;
};

struct BatchSummary {
	std::size_t games = 0;
	std::size_t white_wins = 0;
	std::size_t black_wins = 0;
	std::size_t draws = 0;
	std::size_t total_plies = 0;
	std::size_t total_captures = 0;
	std::size_t total_promotions = 0;
	std::size_t total_queen_captures = 0;
	std::int64_t total_material_lost = 0;
	std::unordered_map<TerminalReason, std::size_t> reasons;
};

int piece_value(PieceType pt) {
	switch (pt) {
	case PAWN: return 100;
	case KNIGHT: return 320;
	case BISHOP: return 330;
	case ROOK: return 500;
	case QUEEN: return 900;
	case KING: return 0;
	}
	return 0;
}

std::string terminal_reason_to_string(TerminalReason reason) {
	switch (reason) {
	case TerminalReason::Checkmate: return "checkmate";
	case TerminalReason::Stalemate: return "stalemate";
	case TerminalReason::ThreefoldRepetition: return "threefold-repetition";
	case TerminalReason::FivefoldRepetition: return "fivefold-repetition";
	case TerminalReason::FiftyMoveRule: return "50-move-rule";
	case TerminalReason::SeventyFiveMoveRule: return "75-move-rule";
	case TerminalReason::InsufficientMaterial: return "insufficient-material";
	case TerminalReason::PlyCap: return "ply-cap";
	case TerminalReason::None: return "none";
	}
	return "none";
}

std::string move_to_uci(const Move& move) {
	std::string result = SQSTR[move.from()];
	result += SQSTR[move.to()];
	switch (move.flags()) {
	case PR_KNIGHT:
	case PC_KNIGHT: result += 'n'; break;
	case PR_BISHOP:
	case PC_BISHOP: result += 'b'; break;
	case PR_ROOK:
	case PC_ROOK: result += 'r'; break;
	case PR_QUEEN:
	case PC_QUEEN: result += 'q'; break;
	default: break;
	}
	return result;
}

std::string json_escape(const std::string& value) {
	std::string escaped;
	escaped.reserve(value.size() + 8);
	for (char ch : value) {
		switch (ch) {
		case '\\': escaped += "\\\\"; break;
		case '"': escaped += "\\\""; break;
		case '\b': escaped += "\\b"; break;
		case '\f': escaped += "\\f"; break;
		case '\n': escaped += "\\n"; break;
		case '\r': escaped += "\\r"; break;
		case '\t': escaped += "\\t"; break;
		default:
			if (static_cast<unsigned char>(ch) < 0x20) {
				char buffer[7];
				std::snprintf(buffer, sizeof(buffer), "\\u%04x", static_cast<unsigned char>(ch));
				escaped += buffer;
			} else {
				escaped += ch;
			}
			break;
		}
	}
	return escaped;
}

template<Color Us>
bool has_insufficient_material(const Position& position) {
	const std::size_t white_pawns = pop_count(position.bitboard_of(WHITE, PAWN));
	const std::size_t black_pawns = pop_count(position.bitboard_of(BLACK, PAWN));
	const std::size_t white_rooks = pop_count(position.bitboard_of(WHITE, ROOK));
	const std::size_t black_rooks = pop_count(position.bitboard_of(BLACK, ROOK));
	const std::size_t white_queens = pop_count(position.bitboard_of(WHITE, QUEEN));
	const std::size_t black_queens = pop_count(position.bitboard_of(BLACK, QUEEN));

	if (white_pawns || black_pawns || white_rooks || black_rooks || white_queens || black_queens)
		return false;

	const std::size_t white_knights = pop_count(position.bitboard_of(WHITE, KNIGHT));
	const std::size_t black_knights = pop_count(position.bitboard_of(BLACK, KNIGHT));
	const std::size_t white_bishops = pop_count(position.bitboard_of(WHITE, BISHOP));
	const std::size_t black_bishops = pop_count(position.bitboard_of(BLACK, BISHOP));
	const std::size_t minor_total = white_knights + black_knights + white_bishops + black_bishops;

	if (minor_total <= 1)
		return true;

	if (white_knights == 0 && black_knights == 0 && minor_total == 2 && white_bishops == 2 && black_bishops == 0) {
		const bool bishop_on_light = (position.bitboard_of(WHITE, BISHOP) & 0x55AA55AA55AA55AAULL) != 0;
		const bool bishop_on_dark = (position.bitboard_of(WHITE, BISHOP) & 0xAA55AA55AA55AA55ULL) != 0;
		return bishop_on_light == bishop_on_dark;
	}

	if (white_knights == 0 && black_knights == 0 && minor_total == 2 && black_bishops == 2 && white_bishops == 0) {
		const bool bishop_on_light = (position.bitboard_of(BLACK, BISHOP) & 0x55AA55AA55AA55AAULL) != 0;
		const bool bishop_on_dark = (position.bitboard_of(BLACK, BISHOP) & 0xAA55AA55AA55AA55ULL) != 0;
		return bishop_on_light == bishop_on_dark;
	}

	if (white_bishops == 0 && black_bishops == 0 && white_knights + black_knights <= 2)
		return true;

	return false;
}

template<Color Us>
TerminalReason evaluate_terminal(Position& position, std::size_t halfmove_clock,
	const std::unordered_map<std::string, std::size_t>& repetition_counts) {
	MoveList<Us> legal_moves(position);
	if (legal_moves.size() == 0)
		return position.in_check<Us>() ? TerminalReason::Checkmate : TerminalReason::Stalemate;

	const std::string fen_key = position.fen();
	const auto repetition_it = repetition_counts.find(fen_key);
	const std::size_t repetitions = repetition_it == repetition_counts.end() ? 0 : repetition_it->second;

	if (repetitions >= 5)
		return TerminalReason::FivefoldRepetition;
	if (halfmove_clock >= 150)
		return TerminalReason::SeventyFiveMoveRule;
	if (repetitions >= 3)
		return TerminalReason::ThreefoldRepetition;
	if (halfmove_clock >= 100)
		return TerminalReason::FiftyMoveRule;
	if (has_insufficient_material<Us>(position))
		return TerminalReason::InsufficientMaterial;

	return TerminalReason::None;
}

template<Color Us>
GameReport play_random_game(Position& position, std::mt19937_64& rng, const SimulationOptions& options) {
	GameReport report;
	std::unordered_map<std::string, std::size_t> repetition_counts;
	std::size_t halfmove_clock = 0;

	repetition_counts[position.fen()] = 1;
	if (options.log_fens)
		report.fen_log.push_back(position.fen());

	for (;;) {
		TerminalReason terminal = evaluate_terminal<Us>(position, halfmove_clock, repetition_counts);
		if (terminal != TerminalReason::None) {
			report.reason = terminal;
			if (terminal == TerminalReason::Checkmate)
				report.winner = ~Us;
			break;
		}

		MoveList<Us> legal_moves(position);
		if (legal_moves.size() == 0)
			break;

		std::uniform_int_distribution<std::size_t> distribution(0, legal_moves.size() - 1);
		const Move selected_move = legal_moves.begin()[distribution(rng)];
		const Piece moving_piece = position.at(selected_move.from());
		const bool moving_pawn = type_of(moving_piece) == PAWN;
		const bool is_capture = selected_move.is_capture();

		Piece captured_piece = NO_PIECE;
		Square capture_square = selected_move.to();
		if (selected_move.flags() == EN_PASSANT)
			capture_square = selected_move.to() + relative_dir<Us>(SOUTH);
		if (is_capture)
			captured_piece = position.at(capture_square);

		position.play<Us>(selected_move);
		++report.plies;
		if (options.log_moves)
		report.move_log.push_back(move_to_uci(selected_move));
		if (options.log_fens)
			report.fen_log.push_back(position.fen());

		if (is_capture) {
			const std::size_t value = piece_value(type_of(captured_piece));
			if (Us == WHITE) {
				++report.white_captures;
				report.black_material_lost += static_cast<std::int64_t>(value);
				if (type_of(captured_piece) == QUEEN)
					++report.white_queen_captures;
			} else {
				++report.black_captures;
				report.white_material_lost += static_cast<std::int64_t>(value);
				if (type_of(captured_piece) == QUEEN)
					++report.black_queen_captures;
			}
		}

		switch (selected_move.flags()) {
		case PR_KNIGHT:
		case PR_BISHOP:
		case PR_ROOK:
		case PR_QUEEN:
			if (Us == WHITE)
				++report.white_promotions;
			else
				++report.black_promotions;
			break;
		case PC_KNIGHT:
		case PC_BISHOP:
		case PC_ROOK:
		case PC_QUEEN:
			if (Us == WHITE)
				++report.white_promotions;
			else
				++report.black_promotions;
			break;
		default:
			break;
		}

		halfmove_clock = (moving_pawn || is_capture) ? 0 : halfmove_clock + 1;

		const std::string fen_key = position.fen();
		std::size_t& count = repetition_counts[fen_key];
		++count;

		if (report.plies >= options.max_plies) {
			report.reason = TerminalReason::PlyCap;
			break;
		}

		if (count >= 5) {
			report.reason = TerminalReason::FivefoldRepetition;
			break;
		}

		if (halfmove_clock >= 150) {
			report.reason = TerminalReason::SeventyFiveMoveRule;
			break;
		}

		if (count >= 3) {
			report.reason = TerminalReason::ThreefoldRepetition;
			break;
		}

		if (halfmove_clock >= 100) {
			report.reason = TerminalReason::FiftyMoveRule;
			break;
		}

		if (has_insufficient_material<Us>(position)) {
			report.reason = TerminalReason::InsufficientMaterial;
			break;
		}
	}

	return report;
}

SimulationOptions parse_options(int argc, char** argv) {
	SimulationOptions options;
	for (int i = 1; i < argc; ++i) {
		std::string arg = argv[i];
		if (arg == "--games" && i + 1 < argc) {
			options.games = std::stoull(argv[++i]);
		} else if (arg == "--seed" && i + 1 < argc) {
			options.seed = std::stoull(argv[++i]);
			options.has_seed = true;
		} else if (arg == "--max-plies" && i + 1 < argc) {
			options.max_plies = std::stoull(argv[++i]);
		} else if (arg == "--fen" && i + 1 < argc) {
			options.start_fen = argv[++i];
		} else if (arg == "--log-moves") {
			options.log_moves = true;
		} else if (arg == "--log-fen") {
			options.log_fens = true;
		} else if (arg == "--json" || arg == "--ndjson" || arg == "-json" || arg == "-ndjson") {
			options.json_output = true;
			options.summary = false;
		} else if (arg == "--quiet") {
			options.summary = false;
		} else if (arg == "--perft" && i + 1 < argc) {
			options.run_perft = true;
			options.perft_depth = static_cast<unsigned int>(std::stoul(argv[++i]));
		} else if (arg == "--help") {
			std::cout << "Usage: surge [--games N] [--seed N] [--fen FEN] [--max-plies N] [--log-moves] [--log-fen] [--json|--ndjson] [--perft D]\n";
		}
	}

	if (options.max_plies > POSITION_HISTORY_LIMIT) {
		std::cerr << "warning: --max-plies exceeds internal history limit; clamped to "
			<< POSITION_HISTORY_LIMIT << "\n";
		options.max_plies = POSITION_HISTORY_LIMIT;
	}

	return options;
}

void print_json_field(std::ostream& os, const char* name, const std::string& value) {
	os << '"' << name << "\":\"" << json_escape(value) << '"';
}

template <typename Integer, typename = std::enable_if_t<std::is_integral_v<Integer> && !std::is_same_v<Integer, bool>>>
void print_json_field(std::ostream& os, const char* name, Integer value) {
	os << '"' << name << "\":" << value;
}

void print_json_field(std::ostream& os, const char* name, double value) {
	os << '"' << name << "\":" << std::fixed << std::setprecision(3) << value << std::defaultfloat;
}

void print_json_field(std::ostream& os, const char* name, bool value) {
	os << '"' << name << "\":" << (value ? "true" : "false");
}

template <typename T>
void print_json_array(std::ostream& os, const std::vector<T>& values) {
	os << '[';
	for (std::size_t i = 0; i < values.size(); ++i) {
		if (i != 0)
			os << ',';
		if constexpr (std::is_same_v<T, std::string>)
			os << '"' << json_escape(values[i]) << '"';
		else
			os << values[i];
	}
	os << ']';
}

void print_game_json(std::size_t index, const GameReport& report, const Position& position) {
	std::cout << '{';
	print_json_field(std::cout, "type", std::string("game"));
	std::cout << ',';
	print_json_field(std::cout, "game_index", index);
	std::cout << ',';
	print_json_field(std::cout, "result", terminal_reason_to_string(report.reason));
	std::cout << ',';
	print_json_field(std::cout, "winner", report.reason == TerminalReason::Checkmate ? (report.winner == WHITE ? std::string("white") : std::string("black")) : std::string("draw"));
	std::cout << ',';
	print_json_field(std::cout, "plies", report.plies);
	std::cout << ',';
	print_json_field(std::cout, "final_fen", position.fen());
	std::cout << ',';
	print_json_field(std::cout, "white_captures", report.white_captures);
	std::cout << ',';
	print_json_field(std::cout, "black_captures", report.black_captures);
	std::cout << ',';
	print_json_field(std::cout, "white_promotions", report.white_promotions);
	std::cout << ',';
	print_json_field(std::cout, "black_promotions", report.black_promotions);
	std::cout << ',';
	print_json_field(std::cout, "white_queen_captures", report.white_queen_captures);
	std::cout << ',';
	print_json_field(std::cout, "black_queen_captures", report.black_queen_captures);
	std::cout << ',';
	print_json_field(std::cout, "white_material_lost", report.white_material_lost);
	std::cout << ',';
	print_json_field(std::cout, "black_material_lost", report.black_material_lost);
	std::cout << ',';
	print_json_field(std::cout, "has_moves_log", !report.move_log.empty());
	std::cout << ',';
	print_json_field(std::cout, "has_fen_log", !report.fen_log.empty());
	if (!report.move_log.empty()) {
		std::cout << ',';
		std::cout << '"' << "moves" << "\":";
		print_json_array(std::cout, report.move_log);
	}
	if (!report.fen_log.empty()) {
		std::cout << ',';
		std::cout << '"' << "fen_log" << "\":";
		print_json_array(std::cout, report.fen_log);
	}
	std::cout << "}\n";
}

void print_batch_json(const BatchSummary& summary, std::uint64_t seed, const SimulationOptions& options) {
	std::cout << '{';
	print_json_field(std::cout, "type", std::string("batch_summary"));
	std::cout << ',';
	print_json_field(std::cout, "games", summary.games);
	std::cout << ',';
	print_json_field(std::cout, "seed", static_cast<std::size_t>(seed));
	std::cout << ',';
	print_json_field(std::cout, "white_wins", summary.white_wins);
	std::cout << ',';
	print_json_field(std::cout, "black_wins", summary.black_wins);
	std::cout << ',';
	print_json_field(std::cout, "draws", summary.draws);
	std::cout << ',';
	print_json_field(std::cout, "total_plies", summary.total_plies);
	std::cout << ',';
	print_json_field(std::cout, "avg_plies", summary.games == 0 ? 0.0 : static_cast<double>(summary.total_plies) / summary.games);
	std::cout << ',';
	print_json_field(std::cout, "total_captures", summary.total_captures);
	std::cout << ',';
	print_json_field(std::cout, "total_promotions", summary.total_promotions);
	std::cout << ',';
	print_json_field(std::cout, "total_queen_captures", summary.total_queen_captures);
	std::cout << ',';
	print_json_field(std::cout, "total_material_lost", summary.total_material_lost);
	std::cout << ',';
	print_json_field(std::cout, "max_plies", options.max_plies);
	std::cout << ',';
	print_json_field(std::cout, "json_output", options.json_output);
	std::cout << ',';
	std::cout << '"' << "reasons" << "\":{";
	bool first = true;
	for (const auto& entry : summary.reasons) {
		if (!first)
			std::cout << ',';
		first = false;
		std::cout << '"' << json_escape(terminal_reason_to_string(entry.first)) << "\":" << entry.second;
	}
	std::cout << "}}\n";
}

BatchSummary update_batch_summary(const GameReport& report, BatchSummary summary) {
	++summary.games;
	summary.total_plies += report.plies;
	summary.total_captures += report.white_captures + report.black_captures;
	summary.total_promotions += report.white_promotions + report.black_promotions;
	summary.total_queen_captures += report.white_queen_captures + report.black_queen_captures;
	summary.total_material_lost += report.white_material_lost + report.black_material_lost;
	++summary.reasons[report.reason];

	if (report.reason == TerminalReason::Checkmate) {
		if (report.winner == WHITE)
			++summary.white_wins;
		else
			++summary.black_wins;
	} else {
		++summary.draws;
	}

	return summary;
}

void print_game_report(std::size_t index, const GameReport& report, const Position& position) {
	std::cout << "game " << index
		<< " result=" << terminal_reason_to_string(report.reason)
		<< " plies=" << report.plies
		<< " final_fen=\"" << position.fen() << "\""
		<< " material_lost_white=" << report.white_material_lost
		<< " material_lost_black=" << report.black_material_lost
		<< " white_captures=" << report.white_captures
		<< " black_captures=" << report.black_captures
		<< " white_promotions=" << report.white_promotions
		<< " black_promotions=" << report.black_promotions
		<< " white_queen_captures=" << report.white_queen_captures
		<< " black_queen_captures=" << report.black_queen_captures
		<< "\n";

	if (!report.move_log.empty()) {
		std::cout << "moves:";
		for (const std::string& move : report.move_log)
			std::cout << ' ' << move;
		std::cout << "\n";
	}

	if (!report.fen_log.empty()) {
		std::cout << "fen-log:\n";
		for (std::size_t i = 0; i < report.fen_log.size(); ++i)
			std::cout << i << ": " << report.fen_log[i] << "\n";
	}
}

void print_batch_summary(const BatchSummary& summary) {
	if (summary.games == 0)
		return;

	std::cout << "batch games=" << summary.games
		<< " white_wins=" << summary.white_wins
		<< " black_wins=" << summary.black_wins
		<< " draws=" << summary.draws
		<< " avg_plies=" << static_cast<double>(summary.total_plies) / summary.games
		<< " captures=" << summary.total_captures
		<< " promotions=" << summary.total_promotions
		<< " queen_captures=" << summary.total_queen_captures
		<< " material_lost=" << summary.total_material_lost
		<< "\n";

	for (const auto& entry : summary.reasons) {
		std::cout << "reason " << terminal_reason_to_string(entry.first) << " count=" << entry.second << "\n";
	}
}

template<Color Us>
GameReport run_single_game(const SimulationOptions& options, std::mt19937_64& rng) {
	Position position;
	Position::set(options.start_fen, position);
	return play_random_game<Us>(position, rng, options);
}

} // namespace


//Computes the perft of the position for a given depth, using bulk-counting
//According to the https://www.chessprogramming.org/Perft site:
//Perft is a debugging function to walk the move generation tree of strictly legal moves to count 
//all the leaf nodes of a certain depth, which can be compared to predetermined values and used to isolate bugs
template<Color Us>
unsigned long long perft(Position& p, unsigned int depth) {
	int nmoves;
	unsigned long long nodes = 0;

	MoveList<Us> list(p);

	if (depth == 1) return (unsigned long long) list.size();

	for (Move move : list) {
		p.play<Us>(move);
		nodes += perft<~Us>(p, depth - 1);
		p.undo<Us>(move);
	}

	return nodes;
}

//A variant of perft, listing all moves and for each move, the perft of the decremented depth
//It is used solely for debugging
template<Color Us>
void perftdiv(Position& p, unsigned int depth) {
	unsigned long long nodes = 0, pf;

	MoveList<Us> list(p);

	for (Move move : list) {
		std::cout << move;

		p.play<Us>(move);
		pf = perft<~Us>(p, depth - 1);
		std::cout << ": " << pf << " moves\n";
		nodes += pf;
		p.undo<Us>(move);
	}

	std::cout << "\nTotal: " << nodes << " moves\n";
}

void test_perft() {
	Position p;
	Position::set("rnbqkbnr/pppppppp/8/8/8/8/PPPP1PPP/RNBQKBNR w KQkq -", p);
	std::cout << p;

	std::chrono::steady_clock::time_point begin = std::chrono::steady_clock::now();
	auto n = perft<WHITE>(p, 6);
	std::chrono::steady_clock::time_point end = std::chrono::steady_clock::now();
	auto diff = end - begin;

	std::cout << "Nodes: " << n << "\n";
	std::cout << "NPS: "
		<< int(n * 1000000.0 / std::chrono::duration_cast<std::chrono::microseconds>(diff).count())
		<< "\n";
	std::cout << "Time difference = "
		<< std::chrono::duration_cast<std::chrono::microseconds>(diff).count() << " [microseconds]\n";
}

int main(int argc, char** argv) {
	initialise_all_databases();
	zobrist::initialise_zobrist_keys();

	SimulationOptions options = parse_options(argc, argv);
	if (options.run_perft) {
		Position position;
		Position::set(options.start_fen, position);
		const auto begin = std::chrono::steady_clock::now();
		unsigned long long nodes = 0;
		if (position.turn() == WHITE)
			nodes = perft<WHITE>(position, options.perft_depth);
		else
			nodes = perft<BLACK>(position, options.perft_depth);
		const auto end = std::chrono::steady_clock::now();
		const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(end - begin).count();
		std::cout << "nodes=" << nodes << " time_us=" << elapsed << "\n";
		return 0;
	}

	std::random_device random_device;
	const std::uint64_t seed = options.has_seed ? options.seed : (static_cast<std::uint64_t>(random_device()) << 32) ^ random_device();
	std::mt19937_64 rng(seed);
	BatchSummary summary;

	for (std::size_t game = 0; game < options.games; ++game) {
		Position position;
		Position::set(options.start_fen, position);
		GameReport report = position.turn() == WHITE ? play_random_game<WHITE>(position, rng, options)
			: play_random_game<BLACK>(position, rng, options);
		if (options.json_output)
			print_game_json(game + 1, report, position);
		else if (options.summary)
			print_game_report(game + 1, report, position);
		summary = update_batch_summary(report, summary);
	}

	if (options.json_output)
		print_batch_json(summary, seed, options);
	else if (options.games > 1 && options.summary)
		print_batch_summary(summary);

	return 0;
}
