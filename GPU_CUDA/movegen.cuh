/**
 * @file movegen.cuh
 * @brief Move generation for chess.
 *
 * Move generation is the core computational task of the chess simulator. For each
 * position, we enumerate every legal move, then pick one uniformly at random. This
 * file builds up the move generator piece by piece (literally).
 *
 * NOTE: [thought process] We generate pseudo-legal moves here — moves that follow piece
 * movement rules but might leave the king in check. A separate legality filter removes
 * illegal moves afterward. This two-phase approach is standard in chess engines because
 * it simplifies each piece's move generator: they don't need to reason about pins,
 * discovered checks, or other king-safety concerns.
 */

#pragma once

#include "board.cuh"

// === Move Representation ===
// NOTE: [pedagogical] The 4-bit flag encoding below is a standard scheme used in many
// chess engines. Bit 2 (value 4) indicates a capture, bit 3 (value 8) indicates a
// promotion. The lower 2 bits distinguish subtypes. This means you can test for captures
// with (flag & 4) and promotions with (flag & 8) using simple bitmasks.
enum MoveFlag : uint8_t {
    QUIET              = 0,
    DOUBLE_PAWN_PUSH   = 1,
    KINGSIDE_CASTLE    = 2,
    QUEENSIDE_CASTLE   = 3,
    CAPTURE            = 4,
    EN_PASSANT         = 5,
    // flags 6, 7 unused
    PROMOTE_KNIGHT     = 8,
    PROMOTE_BISHOP     = 9,
    PROMOTE_ROOK       = 10,
    PROMOTE_QUEEN      = 11,
    CAPTURE_PROMOTE_KNIGHT = 12,
    CAPTURE_PROMOTE_BISHOP = 13,
    CAPTURE_PROMOTE_ROOK   = 14,
    CAPTURE_PROMOTE_QUEEN  = 15
};

/**
 * A single chess move.
 *
 * Stores the source and destination squares plus a flag indicating the move type.
 * At 3 bytes per move, a full move list of 256 moves fits in 768 bytes.
 */
struct Move {
    uint8_t from;
    uint8_t to;
    MoveFlag flag;
};

// NOTE: [thought process] The maximum number of legal moves in any chess position is 218
// (a famous constructed position). We round up to 256 for alignment. In practice, most
// positions have 30-40 legal moves, so most of this array goes unused — but on the GPU,
// a fixed-size array avoids dynamic allocation entirely.
constexpr int MAX_MOVES = 256;

/**
 * A fixed-size list of moves, suitable for use on the GPU without dynamic allocation.
 */
struct MoveList {
    Move moves[MAX_MOVES];
    int count;
};

/**
 * Add a move to the move list.
 */
__host__ __device__ inline void add_move(MoveList& list, int from, int to, MoveFlag flag) {
    list.moves[list.count] = {(uint8_t)from, (uint8_t)to, flag};
    list.count++;
}

// NOTE: [pedagogical] Pawn move generation is the most complex of any piece because
// pawns have so many special rules: direction depends on color, double push from the
// starting rank, diagonal captures, en passant, and promotion. We break this into
// five sections to keep each one simple:
//   1. Single pushes (non-promoting)
//   2. Double pushes
//   3. Captures (non-promoting)
//   4. Promotions (both pushes and captures)
//   5. En passant

/**
 * Generate all pseudo-legal pawn moves for the side to move.
 *
 * Adds moves to the provided MoveList. Does not check whether moves leave the
 * king in check — that is handled by a separate legality filter.
 */
__host__ __device__ void generate_pawn_moves(const BoardState& board, MoveList& list) {
    Color us = board.side_to_move;
    Color them = (us == WHITE) ? BLACK : WHITE;

    uint64_t our_pawns = board.pieces[us][PAWN];
    uint64_t empty     = ~board.all_occupied;
    uint64_t enemy     = board.occupied[them];

    // NOTE: [thought process] All directional constants depend on color. White pawns move
    // toward higher ranks (positive shift), black pawns toward lower ranks (negative shift).
    // Rather than writing separate code paths for each color, we set direction variables
    // once and use them throughout. The "forward" direction is +8 for white and -8 for
    // black in our LERF square mapping.
    int forward          = (us == WHITE) ? 8 : -8;
    uint64_t start_rank  = (us == WHITE) ? RANK_2 : RANK_7;
    uint64_t promo_rank  = (us == WHITE) ? RANK_8 : RANK_1;

    // NOTE: [pedagogical] For captures, pawns move diagonally: northeast (+9) and
    // northwest (+7) for white, southeast (-7) and southwest (-9) for black. But shifting
    // a bitboard left or right can wrap bits around the board edges. For example, a pawn
    // on h2 shifted left by 9 would wrap to a4 instead of going off the board. We prevent
    // this by masking out edge-file pawns before shifting.
    //
    // "Capture left" means toward the a-file (lower file index):
    //   White: shift << 7 (north-west), mask out a-file to prevent wrap
    //   Black: shift >> 9 (south-west), mask out a-file to prevent wrap
    //
    // "Capture right" means toward the h-file (higher file index):
    //   White: shift << 9 (north-east), mask out h-file to prevent wrap
    //   Black: shift >> 7 (south-east), mask out h-file to prevent wrap

    // === Single Pushes (Non-Promoting) ===
    // NOTE: [pedagogical] Shifting the entire pawn bitboard forward by one rank generates
    // all single-push destinations simultaneously. ANDing with empty squares removes pushes
    // that are blocked by any piece. We exclude promotions here (handled separately below)
    // because promotions generate 4 moves per square (one for each promotion piece).
    uint64_t single_push = (us == WHITE)
        ? (our_pawns << 8) & empty
        : (our_pawns >> 8) & empty;
    uint64_t non_promo_push = single_push & ~promo_rank;

    uint64_t targets = non_promo_push;
    while (targets) {
        int to = pop_lsb(targets);
        // NOTE: [shape] to - forward walks the destination back to the source square.
        add_move(list, to - forward, to, QUIET);
    }

    // === Double Pushes ===
    // NOTE: [pedagogical] Only pawns on their starting rank can double push. The trick is
    // that both the intermediate square AND the destination must be empty. We compute
    // single pushes from start-rank pawns first (guaranteed to land on double_rank), then
    // shift those forward again and check emptiness.
    uint64_t single_from_start = (us == WHITE)
        ? ((our_pawns & start_rank) << 8) & empty
        : ((our_pawns & start_rank) >> 8) & empty;
    uint64_t double_push = (us == WHITE)
        ? (single_from_start << 8) & empty
        : (single_from_start >> 8) & empty;

    targets = double_push;
    while (targets) {
        int to = pop_lsb(targets);
        add_move(list, to - 2 * forward, to, DOUBLE_PAWN_PUSH);
    }

    // === Captures (Non-Promoting) ===
    uint64_t capture_left = (us == WHITE)
        ? ((our_pawns & ~FILE_A) << 7) & enemy
        : ((our_pawns & ~FILE_A) >> 9) & enemy;
    uint64_t capture_right = (us == WHITE)
        ? ((our_pawns & ~FILE_H) << 9) & enemy
        : ((our_pawns & ~FILE_H) >> 7) & enemy;

    // NOTE: [thought process] We separate non-promoting captures from promoting captures
    // because non-promoting captures produce one move per destination, while promoting
    // captures produce four (one for each promotion piece).
    uint64_t non_promo_capture_left  = capture_left  & ~promo_rank;
    uint64_t non_promo_capture_right = capture_right & ~promo_rank;

    int capture_left_offset  = (us == WHITE) ? -7 : 9;
    int capture_right_offset = (us == WHITE) ? -9 : 7;

    targets = non_promo_capture_left;
    while (targets) {
        int to = pop_lsb(targets);
        add_move(list, to + capture_left_offset, to, CAPTURE);
    }

    targets = non_promo_capture_right;
    while (targets) {
        int to = pop_lsb(targets);
        add_move(list, to + capture_right_offset, to, CAPTURE);
    }

    // === Promotions ===
    // NOTE: [pedagogical] When a pawn reaches the last rank, it must promote. Each
    // promoting move generates four entries in the move list — one for queen, rook,
    // bishop, and knight. This applies to both pushes and captures that land on the
    // promotion rank.
    uint64_t promo_push          = single_push   & promo_rank;
    uint64_t promo_capture_left  = capture_left  & promo_rank;
    uint64_t promo_capture_right = capture_right & promo_rank;

    targets = promo_push;
    while (targets) {
        int to = pop_lsb(targets);
        int from = to - forward;
        add_move(list, from, to, PROMOTE_QUEEN);
        add_move(list, from, to, PROMOTE_ROOK);
        add_move(list, from, to, PROMOTE_BISHOP);
        add_move(list, from, to, PROMOTE_KNIGHT);
    }

    targets = promo_capture_left;
    while (targets) {
        int to = pop_lsb(targets);
        int from = to + capture_left_offset;
        add_move(list, from, to, CAPTURE_PROMOTE_QUEEN);
        add_move(list, from, to, CAPTURE_PROMOTE_ROOK);
        add_move(list, from, to, CAPTURE_PROMOTE_BISHOP);
        add_move(list, from, to, CAPTURE_PROMOTE_KNIGHT);
    }

    targets = promo_capture_right;
    while (targets) {
        int to = pop_lsb(targets);
        int from = to + capture_right_offset;
        add_move(list, from, to, CAPTURE_PROMOTE_QUEEN);
        add_move(list, from, to, CAPTURE_PROMOTE_ROOK);
        add_move(list, from, to, CAPTURE_PROMOTE_BISHOP);
        add_move(list, from, to, CAPTURE_PROMOTE_KNIGHT);
    }

    // === En Passant ===
    // NOTE: [pedagogical] En passant is the rarest and most unusual pawn move. It can
    // only happen immediately after the opponent double-pushes a pawn, and only by a
    // pawn that is adjacent to the pushed pawn. The capturing pawn moves diagonally to
    // the square the opponent's pawn "passed through," and the opponent's pawn is removed.
    if (board.en_passant_file < 8) {
        // NOTE: [thought process] The en passant target square (where the capturing pawn
        // lands) is on rank 5 for white and rank 2 for black. We only need to check two
        // possible capturing pawns: one to the left and one to the right of the target file.
        int ep_target = (us == WHITE)
            ? 40 + board.en_passant_file  // rank 5 (squares 40-47)
            : 16 + board.en_passant_file; // rank 2 (squares 16-23)

        // NOTE: [shape] ep_target - forward is the rank where a capturable pawn sits. The
        // capturing pawn must be on that same rank, adjacent file (file ± 1).
        int ep_captured_square = ep_target - forward;

        // Check for a capturing pawn to the left of the target file
        if (board.en_passant_file > 0) {
            int from = ep_captured_square - 1;
            if (test_bit(our_pawns, from)) {
                add_move(list, from, ep_target, EN_PASSANT);
            }
        }

        // Check for a capturing pawn to the right of the target file
        if (board.en_passant_file < 7) {
            int from = ep_captured_square + 1;
            if (test_bit(our_pawns, from)) {
                add_move(list, from, ep_target, EN_PASSANT);
            }
        }
    }
}

// === Knight Moves ===

/**
 * Compute the bitboard of all squares a knight can reach from the given square.
 *
 * A knight moves in an "L" shape: two squares in one direction and one square
 * perpendicular (or vice versa). This gives up to 8 possible destinations from any
 * square, fewer near the edges.
 *
 * NOTE: [performance improvement] This function recomputes the attack set from scratch
 * each time. For CPU engines, a precomputed 64-entry lookup table is standard. On the
 * GPU, this table could live in __constant__ memory (64 * 8 = 512 bytes, well within
 * the 64KB limit) for a small speedup. We compute on the fly here for clarity.
 */
__host__ __device__ inline uint64_t knight_attacks(int square) {
    uint64_t bb = 1ULL << square;

    // NOTE: [pedagogical] Each shift below corresponds to one of the 8 "L" shaped jumps.
    // The file masks prevent wraparound: a knight on the a-file cannot jump left, and one
    // on the h-file cannot jump right. For 2-square horizontal jumps, we need to mask out
    // both edge files (A+B or G+H) since the knight could start on either.
    //
    //   Direction       Shift    Mask (prevent wrapping)
    //   up 2, right 1   << 17   not FILE_A (destination would be on a-file if wrapped)
    //   up 2, left 1    << 15   not FILE_H
    //   up 1, right 2   << 10   not FILE_A or B
    //   up 1, left 2    <<  6   not FILE_G or H
    //   down 1, right 2 >>  6   not FILE_A or B
    //   down 1, left 2  >> 10   not FILE_G or H
    //   down 2, right 1 >> 15   not FILE_A
    //   down 2, left 1  >> 17   not FILE_H

    uint64_t attacks = 0;
    attacks |= (bb << 17) & ~FILE_A;
    attacks |= (bb << 15) & ~FILE_H;
    attacks |= (bb << 10) & ~(FILE_A | FILE_B);
    attacks |= (bb <<  6) & ~(FILE_G | FILE_H);
    attacks |= (bb >> 17) & ~FILE_H;
    attacks |= (bb >> 15) & ~FILE_A;
    attacks |= (bb >> 10) & ~(FILE_G | FILE_H);
    attacks |= (bb >>  6) & ~(FILE_A | FILE_B);
    return attacks;
}

/**
 * Generate all pseudo-legal knight moves for the side to move.
 */
__host__ __device__ void generate_knight_moves(const BoardState& board, MoveList& list) {
    Color us = board.side_to_move;
    uint64_t our_knights = board.pieces[us][KNIGHT];
    uint64_t enemy = board.occupied[(us == WHITE) ? BLACK : WHITE];
    uint64_t friendly = board.occupied[us];

    while (our_knights) {
        int from = pop_lsb(our_knights);
        // NOTE: [pedagogical] Masking out friendly pieces prevents generating moves that
        // land on our own pieces. What remains is either empty squares (quiet moves) or
        // enemy-occupied squares (captures).
        uint64_t targets = knight_attacks(from) & ~friendly;

        while (targets) {
            int to = pop_lsb(targets);
            MoveFlag flag = (enemy & (1ULL << to)) ? CAPTURE : QUIET;
            add_move(list, from, to, flag);
        }
    }
}

// === King Moves (Non-Castling) ===

/**
 * Compute the bitboard of all squares a king can reach from the given square.
 *
 * The king moves one square in any direction (horizontal, vertical, or diagonal),
 * giving up to 8 destinations. Like the knight, only file masks are needed to prevent
 * wrapping — the king can never go off the top or bottom of the board since shifts
 * past bit 63 or below bit 0 produce zero.
 */
__host__ __device__ inline uint64_t king_attacks(int square) {
    uint64_t bb = 1ULL << square;

    // NOTE: [pedagogical] The 8 king directions map to these bit shifts:
    //   North: +8    South: -8       (no file mask needed, vertical only)
    //   East:  +1    West:  -1       (mask FILE_A/FILE_H to prevent wrap)
    //   NE:    +9    SW:    -9       (mask FILE_A/FILE_H)
    //   NW:    +7    SE:    -7       (mask FILE_H/FILE_A)
    uint64_t attacks = 0;
    attacks |= (bb << 8);                // north
    attacks |= (bb >> 8);                // south
    attacks |= (bb << 1) & ~FILE_A;     // east
    attacks |= (bb >> 1) & ~FILE_H;     // west
    attacks |= (bb << 9) & ~FILE_A;     // north-east
    attacks |= (bb << 7) & ~FILE_H;     // north-west
    attacks |= (bb >> 7) & ~FILE_A;     // south-east
    attacks |= (bb >> 9) & ~FILE_H;     // south-west
    return attacks;
}

/**
 * Generate all pseudo-legal king moves for the side to move (excluding castling).
 *
 * NOTE: [thought process] Castling is handled separately because it has complex
 * prerequisites (rights, clear squares, no attacks on the path) that don't fit the
 * simple attack-table pattern used here.
 */
__host__ __device__ void generate_king_moves(const BoardState& board, MoveList& list) {
    Color us = board.side_to_move;
    uint64_t our_king = board.pieces[us][KING];
    uint64_t enemy = board.occupied[(us == WHITE) ? BLACK : WHITE];
    uint64_t friendly = board.occupied[us];

    // NOTE: [thought process] There is always exactly one king per side, so this loop
    // runs exactly once. We use pop_lsb for consistency with the other piece generators.
    while (our_king) {
        int from = pop_lsb(our_king);
        uint64_t targets = king_attacks(from) & ~friendly;

        while (targets) {
            int to = pop_lsb(targets);
            MoveFlag flag = (enemy & (1ULL << to)) ? CAPTURE : QUIET;
            add_move(list, from, to, flag);
        }
    }
}

// === Sliding Piece Attacks ===

// NOTE: [pedagogical] Sliding pieces (bishops, rooks, queens) move along rays — straight
// lines that extend until hitting a piece or the board edge. Unlike knights and kings
// whose attack sets are fixed per square, sliding piece attacks depend on what's in the
// way. A rook on a1 with nothing blocking it attacks the entire a-file and 1st rank, but
// a pawn on a4 would block everything beyond it on the a-file.
//
// We compute ray attacks by walking one square at a time in a direction until we hit a
// piece or fall off the board. This is the simplest approach and is easy to follow.
//
// NOTE: [performance improvement] On the GPU, this loop-per-ray approach causes thread
// divergence because different games may have different blocker positions, leading to
// different loop lengths within a warp. The Kogge-Stone fill algorithm computes ray
// attacks using only shifts and ORs (no loops), which eliminates this divergence. It's
// a natural optimization target once correctness is established.

// NOTE: [pedagogical] Each direction is encoded as a (file_delta, rank_delta) pair. To
// walk along a ray, we repeatedly add file_delta to the file and rank_delta to the rank.
// The direction indices 0-3 are for rook (orthogonal) and 4-7 are for bishop (diagonal).
// Direction encoding:
//   0: North      1: South      2: West       3: East
//   4: NorthWest  5: NorthEast  6: SouthWest  7: SouthEast

/**
 * Compute the attack bitboard for a sliding piece along a single ray direction.
 *
 * Walks from the given square in the specified direction, marking each empty square
 * as attacked. Stops when hitting a piece (which is also marked as attacked, since
 * the slider can capture it) or the board edge.
 */
__host__ __device__ inline uint64_t ray_attacks(int square, int direction,
                                                uint64_t all_occupied) {
    // NOTE: [pedagogical] These delta arrays are defined inside the function rather than
    // as global constants because CUDA __constant__ memory is only accessible from device
    // code, while constexpr arrays are only accessible from host code. Since this function
    // is __host__ __device__ (runs on both), local arrays are the cleanest solution — the
    // compiler will optimize them into registers or constant loads on both targets.
    const int file_delta[8] = { 0, 0, -1, +1,  -1, +1, -1, +1};
    const int rank_delta[8] = {+1, -1,  0,  0,  +1, +1, -1, -1};

    uint64_t attacks = 0;
    int file = square % 8;
    int rank = square / 8;
    int df = file_delta[direction];
    int dr = rank_delta[direction];

    while (true) {
        file += df;
        rank += dr;
        if (file < 0 || file > 7 || rank < 0 || rank > 7) break;

        int target = rank * 8 + file;
        attacks |= (1ULL << target);

        // Stop after the first occupied square (the slider can capture it but not
        // pass through it)
        if (all_occupied & (1ULL << target)) break;
    }
    return attacks;
}

/**
 * Compute the combined attack bitboard for a sliding piece across multiple ray directions.
 *
 * Bishops use directions 4-7 (diagonals), rooks use 0-3 (orthogonals), queens use all 8.
 */
__host__ __device__ inline uint64_t sliding_attacks_naive(int square, uint64_t all_occupied,
                                                          int start_dir, int end_dir) {
    uint64_t attacks = 0;
    for (int dir = start_dir; dir < end_dir; dir++) {
        attacks |= ray_attacks(square, dir, all_occupied);
    }
    return attacks;
}

// === Kogge-Stone Sliding Attacks ===
// NOTE: [pedagogical] Kogge-Stone is a parallel-prefix (scan) algorithm originally from
// digital adders. Applied to chess, it computes a "fill" — every square reachable from
// a starting bitboard along a fixed direction, stopping at blockers — using a fixed
// sequence of 5 shift/AND/OR steps regardless of how far the fill propagates. The trick
// is doubling: step 1 fills one square, step 2 fills two more, step 3 fills four more,
// and so on (1 + 2 + 4 + 8 + 16 = 31 squares max — more than enough for a chess board).
//
// The variables:
//   gen  = "generator" — squares filled so far (starts with the source piece).
//   prop = "propagator" — empty squares we are allowed to fill into.
//
// At each step: any square in prop that is one shift away from gen joins gen. Then we
// double the reach by shifting both by twice the previous distance.
//
// To get the attack set (rather than just the fill), we shift gen once more in the
// direction. That final shift lands on either the last empty square plus the first
// blocker (a capture target) — exactly what we want.
//
// NOTE: [performance improvement] Kogge-Stone shines even more when filling from many
// source pieces at once (e.g., "all squares attacked by my rooks combined"). We don't
// do that here because move generation needs to attribute each destination back to the
// source piece, so we still loop over pieces and fill from a single bit at a time. Our
// win is purely warp-divergence reduction: every thread executes the same fixed-length
// instruction sequence regardless of where blockers sit on its board.
//
// NOTE: [pedagogical] File masks prevent the bitboard's row wraparound. Shifting east
// (<<1, <<9, >>7) can move a bit from h-file onto a-file of an adjacent rank — a
// non-move that would corrupt the attack set. We pre-mask the propagator with the
// "destination forbidden" file so wraparound bits get ANDed away before they pollute
// gen. The final "shift one more" also gets the same mask applied.

/**
 * Compute the attack bitboard for a single direction using a Kogge-Stone fill.
 *
 * The `shift` template parameter is the bit shift for one step in the direction
 * (positive = left shift, negative = right shift, expressed via the helper inline).
 * The `dest_mask` is the file mask that prevents wraparound on each step.
 */
__host__ __device__ inline uint64_t ks_north(uint64_t piece, uint64_t empty) {
    uint64_t gen = piece;
    gen   |= empty & (gen   << 8);
    empty &=          (empty << 8);
    gen   |= empty & (gen   << 16);
    empty &=          (empty << 16);
    gen   |= empty & (gen   << 32);
    return gen << 8;
}

__host__ __device__ inline uint64_t ks_south(uint64_t piece, uint64_t empty) {
    uint64_t gen = piece;
    gen   |= empty & (gen   >> 8);
    empty &=          (empty >> 8);
    gen   |= empty & (gen   >> 16);
    empty &=          (empty >> 16);
    gen   |= empty & (gen   >> 32);
    return gen >> 8;
}

__host__ __device__ inline uint64_t ks_east(uint64_t piece, uint64_t empty) {
    // NOTE: [pedagogical] Pre-masking empty with ~FILE_A means any east-shifted bit
    // landing on the a-file gets dropped at every step. The bit that would wrap from
    // h-file to a-file of the next rank is filtered out before it ever enters gen.
    uint64_t prop = empty & ~FILE_A;
    uint64_t gen  = piece;
    gen  |= prop & (gen  << 1);
    prop &=        (prop << 1);
    gen  |= prop & (gen  << 2);
    prop &=        (prop << 2);
    gen  |= prop & (gen  << 4);
    return (gen << 1) & ~FILE_A;
}

__host__ __device__ inline uint64_t ks_west(uint64_t piece, uint64_t empty) {
    uint64_t prop = empty & ~FILE_H;
    uint64_t gen  = piece;
    gen  |= prop & (gen  >> 1);
    prop &=        (prop >> 1);
    gen  |= prop & (gen  >> 2);
    prop &=        (prop >> 2);
    gen  |= prop & (gen  >> 4);
    return (gen >> 1) & ~FILE_H;
}

__host__ __device__ inline uint64_t ks_northeast(uint64_t piece, uint64_t empty) {
    uint64_t prop = empty & ~FILE_A;
    uint64_t gen  = piece;
    gen  |= prop & (gen  << 9);
    prop &=        (prop << 9);
    gen  |= prop & (gen  << 18);
    prop &=        (prop << 18);
    gen  |= prop & (gen  << 36);
    return (gen << 9) & ~FILE_A;
}

__host__ __device__ inline uint64_t ks_northwest(uint64_t piece, uint64_t empty) {
    uint64_t prop = empty & ~FILE_H;
    uint64_t gen  = piece;
    gen  |= prop & (gen  << 7);
    prop &=        (prop << 7);
    gen  |= prop & (gen  << 14);
    prop &=        (prop << 14);
    gen  |= prop & (gen  << 28);
    return (gen << 7) & ~FILE_H;
}

__host__ __device__ inline uint64_t ks_southeast(uint64_t piece, uint64_t empty) {
    uint64_t prop = empty & ~FILE_A;
    uint64_t gen  = piece;
    gen  |= prop & (gen  >> 7);
    prop &=        (prop >> 7);
    gen  |= prop & (gen  >> 14);
    prop &=        (prop >> 14);
    gen  |= prop & (gen  >> 28);
    return (gen >> 7) & ~FILE_A;
}

__host__ __device__ inline uint64_t ks_southwest(uint64_t piece, uint64_t empty) {
    uint64_t prop = empty & ~FILE_H;
    uint64_t gen  = piece;
    gen  |= prop & (gen  >> 9);
    prop &=        (prop >> 9);
    gen  |= prop & (gen  >> 18);
    prop &=        (prop >> 18);
    gen  |= prop & (gen  >> 36);
    return (gen >> 9) & ~FILE_H;
}

/**
 * Compute the combined attack bitboard for a sliding piece using Kogge-Stone fills.
 *
 * Same signature as sliding_attacks_naive. Direction range matches the ray_attacks
 * encoding: 0-3 = orthogonal (rook), 4-7 = diagonal (bishop), 0-7 = all (queen).
 */
__host__ __device__ inline uint64_t sliding_attacks_kogge_stone(int square,
                                                                uint64_t all_occupied,
                                                                int start_dir, int end_dir) {
    uint64_t piece = 1ULL << square;
    uint64_t empty = ~all_occupied;
    uint64_t attacks = 0;

    // NOTE: [thought process] We branch on direction range to match the naive function's
    // selective dispatch. The compiler can fold these branches when start/end_dir are
    // compile-time constants (which they are at every call site). Even when not folded,
    // the branches are uniform across a warp because all threads call with the same
    // (start_dir, end_dir) pair, so there is no warp divergence.
    if (start_dir <= 0 && 0 < end_dir) attacks |= ks_north    (piece, empty);
    if (start_dir <= 1 && 1 < end_dir) attacks |= ks_south    (piece, empty);
    if (start_dir <= 2 && 2 < end_dir) attacks |= ks_west     (piece, empty);
    if (start_dir <= 3 && 3 < end_dir) attacks |= ks_east     (piece, empty);
    if (start_dir <= 4 && 4 < end_dir) attacks |= ks_northwest(piece, empty);
    if (start_dir <= 5 && 5 < end_dir) attacks |= ks_northeast(piece, empty);
    if (start_dir <= 6 && 6 < end_dir) attacks |= ks_southwest(piece, empty);
    if (start_dir <= 7 && 7 < end_dir) attacks |= ks_southeast(piece, empty);
    return attacks;
}

/**
 * Compute sliding attacks, dispatching at compile time between the naive walker and
 * Kogge-Stone fill. Default is naive so existing host-side tests need no changes.
 */
template<bool UseKoggeStone = false>
__host__ __device__ inline uint64_t sliding_attacks(int square, uint64_t all_occupied,
                                                    int start_dir, int end_dir) {
    if constexpr (UseKoggeStone) {
        return sliding_attacks_kogge_stone(square, all_occupied, start_dir, end_dir);
    } else {
        return sliding_attacks_naive(square, all_occupied, start_dir, end_dir);
    }
}

// === Bishop Moves ===

/**
 * Generate all pseudo-legal bishop moves for the side to move.
 *
 * Bishops slide along the 4 diagonal directions (NW, NE, SW, SE), which are ray
 * directions 4-7 in our encoding.
 */
template<bool UseKoggeStone = false>
__host__ __device__ void generate_bishop_moves(const BoardState& board, MoveList& list) {
    Color us = board.side_to_move;
    uint64_t our_bishops = board.pieces[us][BISHOP];
    uint64_t enemy = board.occupied[(us == WHITE) ? BLACK : WHITE];
    uint64_t friendly = board.occupied[us];

    while (our_bishops) {
        int from = pop_lsb(our_bishops);
        uint64_t targets = sliding_attacks<UseKoggeStone>(from, board.all_occupied, 4, 8) & ~friendly;

        while (targets) {
            int to = pop_lsb(targets);
            MoveFlag flag = (enemy & (1ULL << to)) ? CAPTURE : QUIET;
            add_move(list, from, to, flag);
        }
    }
}

// === Rook Moves ===

/**
 * Generate all pseudo-legal rook moves for the side to move.
 *
 * Rooks slide along the 4 orthogonal directions (N, S, W, E), which are ray
 * directions 0-3 in our encoding.
 */
template<bool UseKoggeStone = false>
__host__ __device__ void generate_rook_moves(const BoardState& board, MoveList& list) {
    Color us = board.side_to_move;
    uint64_t our_rooks = board.pieces[us][ROOK];
    uint64_t enemy = board.occupied[(us == WHITE) ? BLACK : WHITE];
    uint64_t friendly = board.occupied[us];

    while (our_rooks) {
        int from = pop_lsb(our_rooks);
        uint64_t targets = sliding_attacks<UseKoggeStone>(from, board.all_occupied, 0, 4) & ~friendly;

        while (targets) {
            int to = pop_lsb(targets);
            MoveFlag flag = (enemy & (1ULL << to)) ? CAPTURE : QUIET;
            add_move(list, from, to, flag);
        }
    }
}

// === Queen Moves ===

/**
 * Generate all pseudo-legal queen moves for the side to move.
 *
 * The queen combines the movement of a bishop and a rook: it slides along all 8 ray
 * directions (4 orthogonal + 4 diagonal), which is directions 0-7 in our encoding.
 */
template<bool UseKoggeStone = false>
__host__ __device__ void generate_queen_moves(const BoardState& board, MoveList& list) {
    Color us = board.side_to_move;
    uint64_t our_queens = board.pieces[us][QUEEN];
    uint64_t enemy = board.occupied[(us == WHITE) ? BLACK : WHITE];
    uint64_t friendly = board.occupied[us];

    while (our_queens) {
        int from = pop_lsb(our_queens);
        // NOTE: [pedagogical] The queen's attack set is exactly the union of bishop attacks
        // (directions 4-7) and rook attacks (directions 0-3). Using sliding_attacks with
        // range 0-8 computes all 8 directions in one call.
        uint64_t targets = sliding_attacks<UseKoggeStone>(from, board.all_occupied, 0, 8) & ~friendly;

        while (targets) {
            int to = pop_lsb(targets);
            MoveFlag flag = (enemy & (1ULL << to)) ? CAPTURE : QUIET;
            add_move(list, from, to, flag);
        }
    }
}

// === Castling ===

// NOTE: [pedagogical] Castling has several prerequisites:
//   1. The king has not moved (tracked by castling rights bits).
//   2. The relevant rook has not moved (also tracked by castling rights).
//   3. All squares between the king and rook must be empty.
//   4. The king must not be in check, and must not pass through or land on a
//      square attacked by the opponent.
//
// This function checks conditions 1-3. Condition 4 (attack checks) is deferred to
// the legality filter, which will reject castling moves that pass through check. This
// keeps the move generator simple and consistent with the pseudo-legal approach.

// Bitmasks for the squares that must be empty between king and rook for each castle type.
constexpr uint64_t WHITE_KINGSIDE_PATH  = (1ULL << F1) | (1ULL << G1);
constexpr uint64_t WHITE_QUEENSIDE_PATH = (1ULL << D1) | (1ULL << C1) | (1ULL << B1);
constexpr uint64_t BLACK_KINGSIDE_PATH  = (1ULL << F8) | (1ULL << G8);
constexpr uint64_t BLACK_QUEENSIDE_PATH = (1ULL << D8) | (1ULL << C8) | (1ULL << B8);

/**
 * Generate pseudo-legal castling moves for the side to move.
 *
 * Only checks that the castling rights are set and the path is clear. Does NOT
 * check whether the king is in check or passes through an attacked square — that
 * is handled by the legality filter.
 */
__host__ __device__ void generate_castling_moves(const BoardState& board, MoveList& list) {
    Color us = board.side_to_move;
    uint64_t occ = board.all_occupied;

    if (us == WHITE) {
        if ((board.castling_rights & WHITE_KINGSIDE) &&
            !(occ & WHITE_KINGSIDE_PATH)) {
            add_move(list, E1, G1, KINGSIDE_CASTLE);
        }
        if ((board.castling_rights & WHITE_QUEENSIDE) &&
            !(occ & WHITE_QUEENSIDE_PATH)) {
            add_move(list, E1, C1, QUEENSIDE_CASTLE);
        }
    } else {
        if ((board.castling_rights & BLACK_KINGSIDE) &&
            !(occ & BLACK_KINGSIDE_PATH)) {
            add_move(list, E8, G8, KINGSIDE_CASTLE);
        }
        if ((board.castling_rights & BLACK_QUEENSIDE) &&
            !(occ & BLACK_QUEENSIDE_PATH)) {
            add_move(list, E8, C8, QUEENSIDE_CASTLE);
        }
    }
}

// === Combined Pseudo-Legal Move Generation ===

/**
 * Generate all pseudo-legal moves for the side to move.
 *
 * Calls every piece-specific generator and collects the results into a single MoveList.
 * These moves may leave the king in check — use generate_legal_moves for filtered results.
 */
template<bool UseKoggeStone = false>
__host__ __device__ void generate_all_pseudo_legal_moves(const BoardState& board,
                                                         MoveList& list) {
    list.count = 0;
    generate_pawn_moves(board, list);
    generate_knight_moves(board, list);
    generate_bishop_moves<UseKoggeStone>(board, list);
    generate_rook_moves<UseKoggeStone>(board, list);
    generate_queen_moves<UseKoggeStone>(board, list);
    generate_king_moves(board, list);
    generate_castling_moves(board, list);
}

// === Square Attack Detection ===

/**
 * Check whether a given square is attacked by any piece of the specified color.
 *
 * This is used for king-in-check detection and castling legality. The approach works
 * by asking: "if a piece of type X were on the target square, could it capture an
 * enemy piece of the same type?" This reversal trick avoids generating all enemy moves.
 */
template<bool UseKoggeStone = false>
__host__ __device__ inline bool is_square_attacked(const BoardState& board, int square,
                                                   Color attacker) {
    uint64_t attackers;

    // NOTE: [pedagogical] Pawn attacks are asymmetric — they depend on color. A white pawn
    // on square S attacks S+7 (NW) and S+9 (NE). So to check if a square is attacked by
    // a white pawn, we look at S-7 and S-9 (the squares a white pawn would be on to attack
    // here). For black pawns, it's reversed: they attack S-7 (SE) and S-9 (SW), so we
    // check S+7 and S+9.
    uint64_t enemy_pawns = board.pieces[attacker][PAWN];
    if (attacker == WHITE) {
        // White pawns attack NE (+9) and NW (+7), so check SE and SW from target
        uint64_t pawn_attackers = 0;
        pawn_attackers |= ((1ULL << square) >> 9) & ~FILE_H; // SW: pawn on square-9
        pawn_attackers |= ((1ULL << square) >> 7) & ~FILE_A; // SE: pawn on square-7
        if (pawn_attackers & enemy_pawns) return true;
    } else {
        // Black pawns attack SE (-7) and SW (-9), so check NE and NW from target
        uint64_t pawn_attackers = 0;
        pawn_attackers |= ((1ULL << square) << 9) & ~FILE_A; // NE: pawn on square+9
        pawn_attackers |= ((1ULL << square) << 7) & ~FILE_H; // NW: pawn on square+7
        if (pawn_attackers & enemy_pawns) return true;
    }

    // NOTE: [pedagogical] For symmetric pieces (knight, king, sliders), the reversal is
    // simple: if a knight on the target square could reach an enemy knight, then that
    // enemy knight attacks the target square. Knight and king attacks are symmetric.
    attackers = knight_attacks(square) & board.pieces[attacker][KNIGHT];
    if (attackers) return true;

    attackers = king_attacks(square) & board.pieces[attacker][KING];
    if (attackers) return true;

    // NOTE: [pedagogical] For sliding pieces, we compute what a bishop/rook on the target
    // square could see, then check if any enemy bishop/queen or rook/queen is there.
    // Queens appear in both checks because they move both diagonally and orthogonally.
    uint64_t diagonal = sliding_attacks<UseKoggeStone>(square, board.all_occupied, 4, 8);
    attackers = diagonal & (board.pieces[attacker][BISHOP] | board.pieces[attacker][QUEEN]);
    if (attackers) return true;

    uint64_t orthogonal = sliding_attacks<UseKoggeStone>(square, board.all_occupied, 0, 4);
    attackers = orthogonal & (board.pieces[attacker][ROOK] | board.pieces[attacker][QUEEN]);
    if (attackers) return true;

    return false;
}

// === Pin / Check Mask Helpers ===
// NOTE: [pedagogical] These four helpers exist to support a faster legality filter that
// avoids the per-move "copy the board, apply the move, check if the king is attacked"
// pattern. Instead, we compute four pieces of information once per position:
//   1. checkers          — bitboard of enemy pieces currently giving check
//   2. check_mask        — squares a non-king move must land on to resolve check
//   3. pin_rays[64]      — for each of our pieces that is pinned, the line it may
//                          move along (king-exclusive, pinner-inclusive)
//   4. enemy_attacks     — every square attacked by any enemy piece, used to filter
//                          king moves
// The legality filter then becomes O(1) bitwise math per pseudo-legal move.

/**
 * Bitboard of every piece of `attacker` that currently attacks `square`.
 *
 * Mirrors is_square_attacked but accumulates the attacker bitboard rather than
 * short-circuiting. Returning the bitboard lets us tell single check from double check
 * (popcount) and identify the checker for building the check mask.
 */
template<bool UseKoggeStone = false>
__host__ __device__ inline uint64_t compute_checkers(const BoardState& board, int square,
                                                     Color attacker) {
    uint64_t checkers = 0;

    // NOTE: [pedagogical] Pawn-attack reversal: see is_square_attacked. The same
    // squares-relative-to-target logic applies — we just OR results instead of
    // returning early.
    uint64_t enemy_pawns = board.pieces[attacker][PAWN];
    uint64_t sq_bb = 1ULL << square;
    if (attacker == WHITE) {
        uint64_t pawn_attackers = 0;
        pawn_attackers |= (sq_bb >> 9) & ~FILE_H;
        pawn_attackers |= (sq_bb >> 7) & ~FILE_A;
        checkers |= pawn_attackers & enemy_pawns;
    } else {
        uint64_t pawn_attackers = 0;
        pawn_attackers |= (sq_bb << 9) & ~FILE_A;
        pawn_attackers |= (sq_bb << 7) & ~FILE_H;
        checkers |= pawn_attackers & enemy_pawns;
    }

    checkers |= knight_attacks(square) & board.pieces[attacker][KNIGHT];
    // NOTE: [edge case callout] King-attacks-king is impossible in legal play but we
    // include it for symmetry with is_square_attacked. The bit is always 0 here.
    checkers |= king_attacks(square)   & board.pieces[attacker][KING];

    uint64_t diag = sliding_attacks<UseKoggeStone>(square, board.all_occupied, 4, 8);
    checkers |= diag & (board.pieces[attacker][BISHOP] | board.pieces[attacker][QUEEN]);

    uint64_t orth = sliding_attacks<UseKoggeStone>(square, board.all_occupied, 0, 4);
    checkers |= orth & (board.pieces[attacker][ROOK]   | board.pieces[attacker][QUEEN]);

    return checkers;
}

/**
 * Build the check mask: the set of squares a non-king move must land on to be legal.
 *
 * - Not in check: all-ones (no constraint from check).
 * - Single check by knight/pawn: the checker's square (only capture resolves it).
 * - Single check by slider: squares between king and slider, plus the slider itself
 *   (any block or capture resolves it).
 * - Double check: 0 (only king moves are legal).
 */
__host__ __device__ inline uint64_t compute_check_mask(const BoardState& board,
                                                       int king_sq, uint64_t checkers,
                                                       Color attacker) {
    if (checkers == 0) return ~0ULL;

    // NOTE: [pedagogical] (x & (x - 1)) clears the lowest set bit. If the result is
    // nonzero, x had at least two bits set. This is a branch-free popcount-equals-1
    // test that avoids relying on a hardware popcount intrinsic.
    if (checkers & (checkers - 1)) return 0ULL;

    int checker_sq = lsb(checkers);
    uint64_t checker_bb = 1ULL << checker_sq;

    // Knight or pawn checks have no blockable squares — only capture resolves them.
    bool is_slider = (checker_bb & (board.pieces[attacker][BISHOP]
                                  | board.pieces[attacker][ROOK]
                                  | board.pieces[attacker][QUEEN])) != 0;
    if (!is_slider) return checker_bb;

    // NOTE: [thought process] We walk one square at a time from the king toward the
    // checker, accumulating each square visited. The walk is a clean alternative to
    // intersecting bitboards from both endpoints — that approach has a subtle bug
    // when the checker is adjacent to the king, because perpendicular rays from each
    // endpoint intersect at off-line squares (e.g. king e1, queen e2: king's east ray
    // and queen's SE ray both pass through f1, giving a spurious "blockable" square).
    // The directional walk only ever visits squares on the king-checker line.
    int king_file    = king_sq    % 8;
    int king_rank    = king_sq    / 8;
    int checker_file = checker_sq % 8;
    int checker_rank = checker_sq / 8;
    int df = (checker_file > king_file) ? 1 : (checker_file < king_file) ? -1 : 0;
    int dr = (checker_rank > king_rank) ? 1 : (checker_rank < king_rank) ? -1 : 0;

    uint64_t mask = 0;
    int file = king_file, rank = king_rank;
    while (true) {
        file += df;
        rank += dr;
        int sq = rank * 8 + file;
        mask |= (1ULL << sq);
        if (sq == checker_sq) break;
    }
    return mask;
}

/**
 * Detect pinned friendly pieces and record each one's pin ray.
 *
 * Walks each of the 8 ray directions from the king. The first blocker on a ray is a
 * pin candidate if it's our piece; we then look at the next blocker. If that next
 * blocker is an enemy slider that moves in this ray's direction, the candidate is
 * pinned and its allowed-move mask is the squares from the king (exclusive) through
 * the pinner (inclusive). The pinned piece may move along this line (capturing the
 * pinner) but no further.
 *
 * Returns the bitboard of all pinned pieces. Fills `pin_rays_out[from_square]` with
 * the pin ray for each pinned square; entries for non-pinned squares are not written
 * (callers must initialize the array to 0 if they want unused entries to read as 0).
 *
 * NOTE: [performance improvement] The walk-one-square-at-a-time inner loop has the
 * same warp-divergence shape as the naive ray attacks. It's called once per position
 * (not per piece per direction), so the overall impact is small — but for completeness
 * a Kogge-Stone style fill that finds the first and second blockers via shifts could
 * eliminate divergence here too.
 */
__host__ __device__ inline uint64_t compute_pin_rays(const BoardState& board, int king_sq,
                                                     Color us, uint64_t pin_rays_out[64]) {
    Color them = (us == WHITE) ? BLACK : WHITE;
    uint64_t our_pieces   = board.occupied[us];
    uint64_t enemy_rq     = board.pieces[them][ROOK]   | board.pieces[them][QUEEN];
    uint64_t enemy_bq     = board.pieces[them][BISHOP] | board.pieces[them][QUEEN];
    uint64_t all_occ      = board.all_occupied;

    const int file_delta[8] = { 0, 0, -1, +1,  -1, +1, -1, +1};
    const int rank_delta[8] = {+1, -1,  0,  0,  +1, +1, -1, -1};

    uint64_t pinned = 0;

    int king_file = king_sq % 8;
    int king_rank = king_sq / 8;

    for (int dir = 0; dir < 8; dir++) {
        // NOTE: [thought process] Orthogonal rays (dirs 0-3) can only be exploited by a
        // rook or queen pin. Diagonal rays (dirs 4-7) only by a bishop or queen. We
        // pick the matching enemy slider set per direction.
        uint64_t enemy_sliders = (dir < 4) ? enemy_rq : enemy_bq;

        int df = file_delta[dir];
        int dr = rank_delta[dir];

        int file = king_file;
        int rank = king_rank;

        // Walk to the first blocker
        int candidate_sq = -1;
        uint64_t ray_so_far = 0;  // squares from king-exclusive up to first blocker-inclusive
        while (true) {
            file += df;
            rank += dr;
            if (file < 0 || file > 7 || rank < 0 || rank > 7) break;
            int sq = rank * 8 + file;
            ray_so_far |= (1ULL << sq);
            if (all_occ & (1ULL << sq)) {
                candidate_sq = sq;
                break;
            }
        }

        // No blocker, or first blocker is enemy: no pin from this direction
        if (candidate_sq < 0) continue;
        if (!(our_pieces & (1ULL << candidate_sq))) continue;

        // Walk past the candidate to find the next blocker
        int pinner_sq = -1;
        uint64_t ray_extension = 0;  // squares from candidate-exclusive to second blocker-inclusive
        while (true) {
            file += df;
            rank += dr;
            if (file < 0 || file > 7 || rank < 0 || rank > 7) break;
            int sq = rank * 8 + file;
            ray_extension |= (1ULL << sq);
            if (all_occ & (1ULL << sq)) {
                pinner_sq = sq;
                break;
            }
        }

        if (pinner_sq < 0) continue;
        if (!(enemy_sliders & (1ULL << pinner_sq))) continue;

        // Confirmed pin. The pin ray is everything we walked: king-exclusive through
        // pinner-inclusive (which is ray_so_far | ray_extension).
        pinned |= (1ULL << candidate_sq);
        pin_rays_out[candidate_sq] = ray_so_far | ray_extension;
    }

    return pinned;
}

/**
 * Compute the bitboard of every square attacked by any piece of `attacker`, with our
 * king removed from occupancy.
 *
 * NOTE: [pedagogical] Removing our king from the occupancy mask before computing slider
 * attacks is essential. Without this, an enemy rook checking the king on the e-file
 * would have its attack ray "stop" at the king, hiding e-file squares behind the king
 * from the enemy attack set — which would let the king illegally step backwards along
 * the ray to e.g. e-king minus 1. By removing the king, the rook's ray extends through
 * those squares, marking them as attacked.
 */
template<bool UseKoggeStone = false>
__host__ __device__ inline uint64_t compute_enemy_attacks(const BoardState& board,
                                                          int our_king_sq, Color attacker) {
    uint64_t occ_no_king = board.all_occupied & ~(1ULL << our_king_sq);
    uint64_t attacks = 0;

    // === Pawns ===
    uint64_t pawns = board.pieces[attacker][PAWN];
    if (attacker == WHITE) {
        attacks |= (pawns & ~FILE_A) << 7;   // NW captures
        attacks |= (pawns & ~FILE_H) << 9;   // NE captures
    } else {
        attacks |= (pawns & ~FILE_H) >> 7;   // SE captures
        attacks |= (pawns & ~FILE_A) >> 9;   // SW captures
    }

    // === Knights ===
    uint64_t knights = board.pieces[attacker][KNIGHT];
    while (knights) {
        int sq = pop_lsb(knights);
        attacks |= knight_attacks(sq);
    }

    // === King ===
    if (board.pieces[attacker][KING]) {
        attacks |= king_attacks(lsb(board.pieces[attacker][KING]));
    }

    // === Sliders ===
    uint64_t bishops_queens = board.pieces[attacker][BISHOP] | board.pieces[attacker][QUEEN];
    while (bishops_queens) {
        int sq = pop_lsb(bishops_queens);
        attacks |= sliding_attacks<UseKoggeStone>(sq, occ_no_king, 4, 8);
    }
    uint64_t rooks_queens = board.pieces[attacker][ROOK] | board.pieces[attacker][QUEEN];
    while (rooks_queens) {
        int sq = pop_lsb(rooks_queens);
        attacks |= sliding_attacks<UseKoggeStone>(sq, occ_no_king, 0, 4);
    }

    return attacks;
}
