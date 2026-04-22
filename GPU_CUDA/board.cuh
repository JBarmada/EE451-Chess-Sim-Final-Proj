/**
 * @file board.cuh
 * @brief Chess board representation using 12 bitboards (one per piece-type-color).
 *
 * This is the foundational data structure for the GPU chess simulator. Each game
 * running on the GPU gets its own BoardState, which is small enough (~128 bytes)
 * to live in registers or local memory.
 *
 * The 12-bitboard representation stores one uint64_t per piece-type-color combination.
 * Each bit in a bitboard corresponds to one square on the chess board. Bit 0 is a1,
 * bit 1 is b1, ..., bit 7 is h1, bit 8 is a2, ..., bit 63 is h8. This is called
 * "Little-Endian Rank-File" (LERF) mapping.
 *
 * NOTE: [thought process] No known GPU chess engine uses the 12-bitboard representation.
 * Zeta, the most well-known GPU chess engine, uses quad bitboards (4 uint64_t values
 * that encode piece type and color vertically). We chose 12-bitboard because each piece
 * query is a direct array read, which makes the move generation code much easier to
 * follow. The cost is higher register pressure (12 vs 4 values for pieces), but move
 * generation is compute-bound, so occupancy is unlikely to be the bottleneck.
 */

#pragma once

#include <cstdint>

// === Square Mapping ===
// NOTE: [pedagogical] Squares are indexed 0-63 in "Little-Endian Rank-File" (LERF) order.
// Bit 0 = a1 (bottom-left from white's perspective), bit 63 = h8 (top-right).
// To convert between (rank, file) and square index: square = rank * 8 + file.
// Rank 0 is white's back rank, rank 7 is black's back rank.
enum Square : int {
    A1, B1, C1, D1, E1, F1, G1, H1,
    A2, B2, C2, D2, E2, F2, G2, H2,
    A3, B3, C3, D3, E3, F3, G3, H3,
    A4, B4, C4, D4, E4, F4, G4, H4,
    A5, B5, C5, D5, E5, F5, G5, H5,
    A6, B6, C6, D6, E6, F6, G6, H6,
    A7, B7, C7, D7, E7, F7, G7, H7,
    A8, B8, C8, D8, E8, F8, G8, H8,
    NO_SQUARE = 64
};

// === Piece Types ===
// NOTE: [thought process] We use separate enums for color and piece type rather than a
// single combined enum. This makes it easy to index into the bitboard arrays: the piece
// bitboards are stored as pieces[color][piece_type].
enum Color : int {
    WHITE = 0,
    BLACK = 1
};

enum PieceType : int {
    PAWN   = 0,
    KNIGHT = 1,
    BISHOP = 2,
    ROOK   = 3,
    QUEEN  = 4,
    KING   = 5
};

/**
 * Complete state of a chess game.
 *
 * This struct is designed to be small enough to live in GPU registers or local memory.
 * At ~128 bytes per game, a single SM on an RTX 3090 Ti can hold thousands of games
 * in its register file simultaneously.
 */
struct BoardState {
    // NOTE: [pedagogical] The 12 bitboards are the core of the representation. Each
    // uint64_t has one bit per square. If bit N is set in pieces[WHITE][KNIGHT], it
    // means there is a white knight on square N. This makes piece-specific queries
    // trivial: "where are all white knights?" is just a single array read.
    uint64_t pieces[2][6];

    // NOTE: [thought process] Occupancy bitboards (all white pieces, all black pieces,
    // all pieces) can be derived by ORing the piece boards together. We store them
    // explicitly to avoid recomputing them on every query. The tradeoff is 24 extra
    // bytes per game vs. 6 OR operations each time we need occupancy. Since move
    // generation queries occupancy constantly, storing them is worth it.
    uint64_t occupied[2];    // occupied[WHITE] = OR of all white pieces, etc.
    uint64_t all_occupied;   // occupied[WHITE] | occupied[BLACK]

    // NOTE: [pedagogical] Castling rights are stored as 4 bits packed into a uint8_t.
    // Bit 0: white kingside, bit 1: white queenside, bit 2: black kingside, bit 3:
    // black queenside. When a king or rook moves, the corresponding bit is cleared.
    uint8_t castling_rights;

    // NOTE: [pedagogical] En passant is stored as the file (0-7) of the pawn that just
    // advanced two squares, or 8 to indicate no en passant is possible. We only need the
    // file because the rank is implied: if white just moved, the target square is on rank
    // 5 (index 40 + file); if black just moved, it's on rank 2 (index 16 + file).
    uint8_t en_passant_file; // 0-7 for file a-h, 8 = no en passant

    Color side_to_move;

    // NOTE: [pedagogical] The halfmove clock counts moves since the last pawn push or
    // capture. When it reaches 100 (50 moves per side), the game is a draw. The fullmove
    // counter tracks the total number of full moves (incremented after black moves) and
    // is useful for statistics like "average game length."
    uint8_t halfmove_clock;
    uint16_t fullmove_counter;
};

// === Bit Manipulation Helpers ===
// NOTE: [pedagogical] These are the fundamental operations on bitboards. Setting a bit
// means placing a piece, clearing a bit means removing a piece, and testing a bit means
// checking if a square is occupied. The expression (1ULL << square) creates a bitmask
// with only the target square's bit set.

__host__ __device__ inline void set_bit(uint64_t& bitboard, int square) {
    bitboard |= (1ULL << square);
}

__host__ __device__ inline void clear_bit(uint64_t& bitboard, int square) {
    bitboard &= ~(1ULL << square);
}

__host__ __device__ inline bool test_bit(uint64_t bitboard, int square) {
    return (bitboard >> square) & 1ULL;
}

// === File and Rank Masks ===
// NOTE: [pedagogical] File masks are vertical columns (a-file through h-file). Each file
// mask has one bit set per rank, so 8 bits set total. These are essential for preventing
// bitboard shifts from wrapping pieces around the board edges. For example, a pawn on the
// a-file cannot capture to the left — masking out FILE_A before a leftward shift prevents
// the bit from wrapping to the h-file of the rank below.
constexpr uint64_t FILE_A = 0x0101010101010101ULL;
constexpr uint64_t FILE_B = 0x0202020202020202ULL;
constexpr uint64_t FILE_G = 0x4040404040404040ULL;
constexpr uint64_t FILE_H = 0x8080808080808080ULL;

// NOTE: [pedagogical] Rank masks are horizontal rows. RANK_1 is white's back rank,
// RANK_8 is black's back rank. RANK_2 and RANK_7 are used to identify pawns eligible
// for double pushes. RANK_4 and RANK_5 are the en passant target ranks.
constexpr uint64_t RANK_1 = 0x00000000000000FFULL;
constexpr uint64_t RANK_2 = 0x000000000000FF00ULL;
constexpr uint64_t RANK_3 = 0x0000000000FF0000ULL;
constexpr uint64_t RANK_4 = 0x00000000FF000000ULL;
constexpr uint64_t RANK_5 = 0x000000FF00000000ULL;
constexpr uint64_t RANK_6 = 0x0000FF0000000000ULL;
constexpr uint64_t RANK_7 = 0x00FF000000000000ULL;
constexpr uint64_t RANK_8 = 0xFF00000000000000ULL;

// === Bit Scanning ===
// NOTE: [pedagogical] pop_lsb extracts and clears the least significant set bit from a
// bitboard, returning its index (0-63). This is the standard way to iterate over all set
// bits in a bitboard: call pop_lsb in a loop until the bitboard is zero. The expression
// (bitboard & (bitboard - 1)) clears the lowest set bit: subtracting 1 flips all bits
// up to and including the lowest set bit, then AND with the original clears just that bit.
__host__ __device__ inline int pop_lsb(uint64_t& bitboard) {
#ifdef __CUDA_ARCH__
    // NOTE: [pedagogical] __ffsll is a CUDA intrinsic that finds the position of the
    // first (least significant) set bit, returning a 1-indexed result. We subtract 1
    // to convert to our 0-indexed square mapping.
    int square = __ffsll(bitboard) - 1;
#else
    // NOTE: [pedagogical] __builtin_ctzll counts trailing zeros — equivalent to finding
    // the index of the least significant set bit. This is a GCC/Clang intrinsic that
    // maps to a single hardware instruction (BSF or TZCNT on x86).
    int square = __builtin_ctzll(bitboard);
#endif
    bitboard &= bitboard - 1;
    return square;
}

/**
 * Find the index of the least significant set bit without clearing it.
 */
__host__ __device__ inline int lsb(uint64_t bitboard) {
#ifdef __CUDA_ARCH__
    return __ffsll(bitboard) - 1;
#else
    return __builtin_ctzll(bitboard);
#endif
}

// === Castling Right Constants ===
constexpr uint8_t WHITE_KINGSIDE  = 1 << 0;
constexpr uint8_t WHITE_QUEENSIDE = 1 << 1;
constexpr uint8_t BLACK_KINGSIDE  = 1 << 2;
constexpr uint8_t BLACK_QUEENSIDE = 1 << 3;
constexpr uint8_t ALL_CASTLING    = WHITE_KINGSIDE | WHITE_QUEENSIDE
                                  | BLACK_KINGSIDE | BLACK_QUEENSIDE;

/**
 * Initialize a BoardState to the standard chess starting position.
 *
 * Sets up all 12 piece bitboards, computes occupancy, and sets the initial game
 * state (white to move, all castling rights, no en passant).
 */
__host__ __device__ inline void initialize_board(BoardState& board) {
    // NOTE: [pedagogical] Each hex literal below is a bitboard with bits set for the
    // starting squares of that piece type. For example, 0x00FF000000000000 has bits
    // 48-55 set, corresponding to a7-h7 (black's pawn rank). The hex representation
    // makes rank structure visible: each pair of hex digits is one rank (8 bits).

    // === White Pieces ===
    board.pieces[WHITE][PAWN]   = 0x000000000000FF00ULL; // rank 2: a2-h2
    board.pieces[WHITE][KNIGHT] = 0x0000000000000042ULL; // b1, g1
    board.pieces[WHITE][BISHOP] = 0x0000000000000024ULL; // c1, f1
    board.pieces[WHITE][ROOK]   = 0x0000000000000081ULL; // a1, h1
    board.pieces[WHITE][QUEEN]  = 0x0000000000000008ULL; // d1
    board.pieces[WHITE][KING]   = 0x0000000000000010ULL; // e1

    // === Black Pieces ===
    board.pieces[BLACK][PAWN]   = 0x00FF000000000000ULL; // rank 7: a7-h7
    board.pieces[BLACK][KNIGHT] = 0x4200000000000000ULL; // b8, g8
    board.pieces[BLACK][BISHOP] = 0x2400000000000000ULL; // c8, f8
    board.pieces[BLACK][ROOK]   = 0x8100000000000000ULL; // a8, h8
    board.pieces[BLACK][QUEEN]  = 0x0800000000000000ULL; // d8
    board.pieces[BLACK][KING]   = 0x1000000000000000ULL; // e8

    // === Occupancy ===
    board.occupied[WHITE] = 0x000000000000FFFFULL; // ranks 1-2
    board.occupied[BLACK] = 0xFFFF000000000000ULL; // ranks 7-8
    board.all_occupied    = board.occupied[WHITE] | board.occupied[BLACK];

    // === Game State ===
    board.side_to_move    = WHITE;
    board.castling_rights = ALL_CASTLING;
    board.en_passant_file = 8; // no en passant possible at game start
    board.halfmove_clock  = 0;
    board.fullmove_counter = 1;
}
