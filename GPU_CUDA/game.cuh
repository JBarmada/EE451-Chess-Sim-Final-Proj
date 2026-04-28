/**
 * @file game.cuh
 * @brief Game logic: making moves, detecting game-over conditions, and legal move generation.
 *
 * This file bridges move generation (movegen.cuh) with actual gameplay. It provides the
 * make_move function that applies a move to a board state, the legality filter that
 * removes pseudo-legal moves which leave the king in check, and game-over detection.
 */

#pragma once

#include "board.cuh"
#include "movegen.cuh"

// === Making Moves ===

/**
 * Find which piece type (if any) of the given color occupies a square.
 *
 * Returns the PieceType, or -1 if no piece of that color is on the square.
 */
__host__ __device__ inline int find_piece_type(const BoardState& board, Color color,
                                               int square) {
    for (int p = 0; p < 6; p++) {
        if (test_bit(board.pieces[color][p], square)) return p;
    }
    return -1;
}

/**
 * Apply a move to a board state, producing the resulting position.
 *
 * This is a "copy-make" approach: the caller copies the board before calling this
 * function. This avoids needing an unmake function, which simplifies the code at the
 * cost of a ~128-byte copy per move. On the GPU, this copy is cheap relative to the
 * move generation work.
 */
__host__ __device__ void make_move(BoardState& board, Move move) {
    Color us = board.side_to_move;
    Color them = (us == WHITE) ? BLACK : WHITE;
    int from = move.from;
    int to = move.to;
    MoveFlag flag = move.flag;
    bool is_capture = (flag & 4) || flag == EN_PASSANT;

    // NOTE: [thought process] We find the moving piece type by checking which bitboard
    // has a bit set at the from-square. This is a linear scan over 6 piece types, but
    // it's only done once per move and the branch is predictable.
    int piece_type = find_piece_type(board, us, from);

    // === Move the piece ===
    clear_bit(board.pieces[us][piece_type], from);
    set_bit(board.pieces[us][piece_type], to);

    // === Handle captures ===
    if (flag == EN_PASSANT) {
        // NOTE: [pedagogical] In en passant, the captured pawn is not on the destination
        // square. It's on the same rank as the capturing pawn's starting square, same
        // file as the destination. Since the capturing pawn moves diagonally forward,
        // the captured pawn is one rank behind the destination.
        int captured_square = (us == WHITE) ? to - 8 : to + 8;
        clear_bit(board.pieces[them][PAWN], captured_square);
    } else if (is_capture) {
        // Find and remove the captured piece
        int captured_type = find_piece_type(board, them, to);
        clear_bit(board.pieces[them][captured_type], to);

        // NOTE: [thought process] If a rook is captured on its starting square, the
        // opponent loses that castling right. This handles the edge case where a rook is
        // captured before it ever moves.
        if (captured_type == ROOK) {
            if (to == A1) board.castling_rights &= ~WHITE_QUEENSIDE;
            else if (to == H1) board.castling_rights &= ~WHITE_KINGSIDE;
            else if (to == A8) board.castling_rights &= ~BLACK_QUEENSIDE;
            else if (to == H8) board.castling_rights &= ~BLACK_KINGSIDE;
        }
    }

    // === Handle promotion ===
    if (flag & 8) {
        // NOTE: [pedagogical] The promotion flag's lower 2 bits encode the piece type:
        // 0 = knight, 1 = bishop, 2 = rook, 3 = queen. We already moved the pawn to the
        // destination square above, so now we remove it from the pawn board and add it to
        // the promoted piece's board.
        clear_bit(board.pieces[us][PAWN], to);
        int promo_piece = KNIGHT + (flag & 3);
        set_bit(board.pieces[us][promo_piece], to);
    }

    // === Handle castling — also move the rook ===
    if (flag == KINGSIDE_CASTLE) {
        // NOTE: [pedagogical] In kingside castling, the king moves from e to g and the
        // rook moves from h to f. We already moved the king above, so just move the rook.
        int rook_from = (us == WHITE) ? H1 : H8;
        int rook_to   = (us == WHITE) ? F1 : F8;
        clear_bit(board.pieces[us][ROOK], rook_from);
        set_bit(board.pieces[us][ROOK], rook_to);
    } else if (flag == QUEENSIDE_CASTLE) {
        int rook_from = (us == WHITE) ? A1 : A8;
        int rook_to   = (us == WHITE) ? D1 : D8;
        clear_bit(board.pieces[us][ROOK], rook_from);
        set_bit(board.pieces[us][ROOK], rook_to);
    }

    // === Update castling rights ===
    // NOTE: [thought process] Any king move (including castling) permanently revokes both
    // castling rights for that side. Any rook move from its starting square revokes that
    // specific right. We use a simple check against the starting squares.
    if (piece_type == KING) {
        if (us == WHITE) board.castling_rights &= ~(WHITE_KINGSIDE | WHITE_QUEENSIDE);
        else             board.castling_rights &= ~(BLACK_KINGSIDE | BLACK_QUEENSIDE);
    } else if (piece_type == ROOK) {
        if (from == A1) board.castling_rights &= ~WHITE_QUEENSIDE;
        else if (from == H1) board.castling_rights &= ~WHITE_KINGSIDE;
        else if (from == A8) board.castling_rights &= ~BLACK_QUEENSIDE;
        else if (from == H8) board.castling_rights &= ~BLACK_KINGSIDE;
    }

    // === Update en passant ===
    if (flag == DOUBLE_PAWN_PUSH) {
        board.en_passant_file = from % 8;
    } else {
        board.en_passant_file = 8; // no en passant possible
    }

    // === Update clocks ===
    if (piece_type == PAWN || is_capture) {
        board.halfmove_clock = 0;
    } else {
        board.halfmove_clock++;
    }
    if (us == BLACK) {
        board.fullmove_counter++;
    }

    // === Recompute occupancy ===
    // NOTE: [performance improvement] We could do incremental updates to occupancy instead
    // of recomputing from scratch. For example, clear the from-bit and set the to-bit on
    // the relevant occupied boards. But with special moves (castling, en passant, promotion)
    // the incremental logic gets complex. Recomputing is 12 ORs — cheap and correct.
    board.occupied[WHITE] = 0;
    board.occupied[BLACK] = 0;
    for (int p = 0; p < 6; p++) {
        board.occupied[WHITE] |= board.pieces[WHITE][p];
        board.occupied[BLACK] |= board.pieces[BLACK][p];
    }
    board.all_occupied = board.occupied[WHITE] | board.occupied[BLACK];

    // === Switch side ===
    board.side_to_move = them;
}

// === Legal Move Generation ===

/**
 * Legacy legality filter: copy-make per pseudo-legal move.
 *
 * For each candidate move, apply it to a board copy and ask "is my king attacked
 * now?". Costs an O(N) board copy and N attack scans per ply. Kept as a reference
 * implementation alongside generate_legal_moves_fast.
 */
template<bool UseKoggeStone = false>
__host__ __device__ void generate_legal_moves_legacy(const BoardState& board, MoveList& legal) {
    Color us = board.side_to_move;
    Color them = (us == WHITE) ? BLACK : WHITE;

    MoveList pseudo;
    generate_all_pseudo_legal_moves<UseKoggeStone>(board, pseudo);

    legal.count = 0;
    for (int i = 0; i < pseudo.count; i++) {
        Move move = pseudo.moves[i];

        // NOTE: [thought process] For castling, we need three additional checks beyond
        // what generate_castling_moves already verified (rights + clear path):
        //   1. King is not currently in check
        //   2. King does not pass through an attacked square
        //   3. King does not land on an attacked square (handled by the general check below)
        // We check conditions 1 and 2 here and let the general filter catch condition 3.
        if (move.flag == KINGSIDE_CASTLE || move.flag == QUEENSIDE_CASTLE) {
            int king_square = (us == WHITE) ? E1 : E8;
            if (is_square_attacked<UseKoggeStone>(board, king_square, them)) continue;

            int pass_through = (move.flag == KINGSIDE_CASTLE)
                ? ((us == WHITE) ? F1 : F8)
                : ((us == WHITE) ? D1 : D8);
            if (is_square_attacked<UseKoggeStone>(board, pass_through, them)) continue;
        }

        // Copy-make: apply the move to a copy, then check if our king is safe
        BoardState after = board;
        make_move(after, move);

        // NOTE: [pedagogical] After making the move, side_to_move has switched to the
        // opponent. So we need to find OUR king (the side that just moved) and check if
        // the OPPONENT (now the side to move) attacks it.
        int king_square = lsb(after.pieces[us][KING]);

        if (!is_square_attacked<UseKoggeStone>(after, king_square, them)) {
            legal.moves[legal.count] = move;
            legal.count++;
        }
    }
}

/**
 * Fast legality filter using precomputed pin and check masks.
 *
 * Computes four pieces of information once per position (checkers, check_mask,
 * pin_rays, enemy_attacks) and then resolves each pseudo-legal move with a few
 * bitwise ops:
 *   - King moves: legal iff destination not in enemy_attacks (plus path checks for castling).
 *   - Non-king moves under double check: never legal.
 *   - Other non-king moves: legal iff destination ∈ check_mask, refined to the pin
 *     ray when the from-square is pinned.
 *
 * NOTE: [edge case callout] En passant has a subtle horizontal-pin scenario where
 * removing two pawns from the same rank simultaneously exposes the king to a sideways
 * slider. The mask logic doesn't catch this case (it considers only the moving piece's
 * pin status, not interactions between source and captured square). EP is rare, so we
 * fall back to copy-make verification just for those moves.
 */
template<bool UseKoggeStone = false>
__host__ __device__ void generate_legal_moves_fast(const BoardState& board, MoveList& legal) {
    Color us = board.side_to_move;
    Color them = (us == WHITE) ? BLACK : WHITE;
    int king_sq = lsb(board.pieces[us][KING]);

    uint64_t checkers      = compute_checkers<UseKoggeStone>(board, king_sq, them);
    uint64_t check_mask    = compute_check_mask(board, king_sq, checkers, them);
    uint64_t enemy_attacks = compute_enemy_attacks<UseKoggeStone>(board, king_sq, them);

    // NOTE: [thought process] Most squares aren't pinned, so most pin_rays entries stay
    // 0. We initialize the whole array to 0 once and only the pinned squares get
    // overwritten by compute_pin_rays. The check `pinned & (1ULL << from)` decides
    // whether to apply the per-square ray.
    uint64_t pin_rays[64] = {};
    uint64_t pinned = compute_pin_rays(board, king_sq, us, pin_rays);

    bool in_double_check = (check_mask == 0);

    MoveList pseudo;
    generate_all_pseudo_legal_moves<UseKoggeStone>(board, pseudo);

    legal.count = 0;
    for (int i = 0; i < pseudo.count; i++) {
        Move move = pseudo.moves[i];
        uint64_t to_bb = 1ULL << move.to;

        if (move.from == king_sq) {
            // Castling: rights and clear path were verified in generate_castling_moves.
            // We additionally need the king not currently in check, and the
            // pass-through square not attacked. The destination square attack check
            // falls through to the general king filter below.
            if (move.flag == KINGSIDE_CASTLE || move.flag == QUEENSIDE_CASTLE) {
                if (checkers != 0) continue;
                int pass_through = (move.flag == KINGSIDE_CASTLE)
                    ? ((us == WHITE) ? F1 : F8)
                    : ((us == WHITE) ? D1 : D8);
                if (enemy_attacks & (1ULL << pass_through)) continue;
            }
            if (enemy_attacks & to_bb) continue;
            legal.moves[legal.count++] = move;
            continue;
        }

        // Non-king moves are illegal under double check
        if (in_double_check) continue;

        // En passant edge case: rare, fall back to copy-make verification
        if (move.flag == EN_PASSANT) {
            BoardState after = board;
            make_move(after, move);
            int new_king_sq = lsb(after.pieces[us][KING]);
            if (!is_square_attacked<UseKoggeStone>(after, new_king_sq, them)) {
                legal.moves[legal.count++] = move;
            }
            continue;
        }

        uint64_t allowed = check_mask;
        if (pinned & (1ULL << move.from)) {
            allowed &= pin_rays[move.from];
        }
        if (to_bb & allowed) {
            legal.moves[legal.count++] = move;
        }
    }
}

/**
 * Generate all legal moves for the side to move, dispatching at compile time between
 * the legacy copy-make filter and the fast pin/check-mask filter.
 *
 * Default is legacy so existing host tests need no changes.
 */
template<bool UseKoggeStone = false, bool UseFastLegality = false>
__host__ __device__ void generate_legal_moves(const BoardState& board, MoveList& legal) {
    if constexpr (UseFastLegality) {
        generate_legal_moves_fast<UseKoggeStone>(board, legal);
    } else {
        generate_legal_moves_legacy<UseKoggeStone>(board, legal);
    }
}

// === Game-Over Detection ===

enum GameResult : int {
    ONGOING         = 0,
    WHITE_WINS      = 1, // black is checkmated
    BLACK_WINS      = 2, // white is checkmated
    DRAW_STALEMATE  = 3,
    DRAW_50_MOVE    = 4
    // NOTE: [edge case callout] Threefold repetition is not implemented. It requires
    // storing position history, which is expensive on the GPU (hash per position * max
    // game length). For random games, threefold repetition is rare enough to skip for now.
};

/**
 * Determine the result of a game given the current position and its legal moves.
 *
 * Call this after generating legal moves. If there are no legal moves, it's either
 * checkmate or stalemate depending on whether the king is in check.
 */
template<bool UseKoggeStone = false>
__host__ __device__ GameResult check_game_over(const BoardState& board,
                                               const MoveList& legal_moves) {
    // 50-move rule: 100 half-moves = 50 full moves without a pawn push or capture
    if (board.halfmove_clock >= 100) return DRAW_50_MOVE;

    if (legal_moves.count > 0) return ONGOING;

    // No legal moves: checkmate or stalemate
    Color us = board.side_to_move;
    Color them = (us == WHITE) ? BLACK : WHITE;

    // Find king square
    int king_square = lsb(board.pieces[us][KING]);

    if (is_square_attacked<UseKoggeStone>(board, king_square, them)) {
        // In check with no legal moves = checkmate
        return (us == WHITE) ? BLACK_WINS : WHITE_WINS;
    }

    return DRAW_STALEMATE;
}
