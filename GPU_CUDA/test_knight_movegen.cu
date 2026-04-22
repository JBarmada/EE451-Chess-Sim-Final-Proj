/**
 * @file test_knight_movegen.cu
 * @brief Tests for knight move generation across a variety of board positions.
 */

#include "board.cuh"
#include "board_print.cuh"
#include "movegen.cuh"
#include <cstdio>
#include <cassert>

void clear_board(BoardState& board) {
    for (int c = 0; c < 2; c++)
        for (int p = 0; p < 6; p++)
            board.pieces[c][p] = 0;
    board.occupied[WHITE] = 0;
    board.occupied[BLACK] = 0;
    board.all_occupied = 0;
    board.side_to_move = WHITE;
    board.castling_rights = 0;
    board.en_passant_file = 8;
    board.halfmove_clock = 0;
    board.fullmove_counter = 1;
}

void recompute_occupancy(BoardState& board) {
    board.occupied[WHITE] = 0;
    board.occupied[BLACK] = 0;
    for (int p = 0; p < 6; p++) {
        board.occupied[WHITE] |= board.pieces[WHITE][p];
        board.occupied[BLACK] |= board.pieces[BLACK][p];
    }
    board.all_occupied = board.occupied[WHITE] | board.occupied[BLACK];
}

bool has_move(const MoveList& list, int from, int to, MoveFlag flag) {
    for (int i = 0; i < list.count; i++) {
        if (list.moves[i].from == from
            && list.moves[i].to == to
            && list.moves[i].flag == flag) {
            return true;
        }
    }
    return false;
}

int count_moves_with_flag(const MoveList& list, MoveFlag flag) {
    int count = 0;
    for (int i = 0; i < list.count; i++) {
        if (list.moves[i].flag == flag) count++;
    }
    return count;
}

/**
 * Knight in the center (e4): should have 8 moves.
 */
void test_knight_center() {
    printf("=== Knight Center (e4) ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KNIGHT], E4);
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_knight_moves(board, list);

    printf("  Knight moves: %d (expected 8)\n", list.count);
    assert(list.count == 8);

    // All 8 L-shaped destinations from e4
    assert(has_move(list, E4, D6, QUIET));
    assert(has_move(list, E4, F6, QUIET));
    assert(has_move(list, E4, C5, QUIET));
    assert(has_move(list, E4, G5, QUIET));
    assert(has_move(list, E4, C3, QUIET));
    assert(has_move(list, E4, G3, QUIET));
    assert(has_move(list, E4, D2, QUIET));
    assert(has_move(list, E4, F2, QUIET));

    printf("  Passed.\n\n");
}

/**
 * Knight in the corner (a1): should have only 2 moves.
 */
void test_knight_corner() {
    printf("=== Knight Corner (a1) ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KNIGHT], A1);
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_knight_moves(board, list);

    printf("  Knight moves: %d (expected 2)\n", list.count);
    assert(list.count == 2);

    assert(has_move(list, A1, B3, QUIET));
    assert(has_move(list, A1, C2, QUIET));

    printf("  Passed.\n\n");
}

/**
 * Knight on the edge (a4): should have 4 moves (all on the right side).
 */
void test_knight_edge() {
    printf("=== Knight Edge (a4) ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KNIGHT], A4);
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_knight_moves(board, list);

    printf("  Knight moves: %d (expected 4)\n", list.count);
    assert(list.count == 4);

    assert(has_move(list, A4, B6, QUIET));
    assert(has_move(list, A4, C5, QUIET));
    assert(has_move(list, A4, C3, QUIET));
    assert(has_move(list, A4, B2, QUIET));

    printf("  Passed.\n\n");
}

/**
 * Knight with captures: enemy pieces on some destination squares.
 */
void test_knight_captures() {
    printf("=== Knight Captures ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KNIGHT], E4);
    set_bit(board.pieces[BLACK][PAWN], D6);  // capturable
    set_bit(board.pieces[BLACK][PAWN], G5);  // capturable
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_knight_moves(board, list);

    printf("  Knight moves: %d (expected 8)\n", list.count);
    assert(list.count == 8);

    assert(has_move(list, E4, D6, CAPTURE));
    assert(has_move(list, E4, G5, CAPTURE));
    assert(has_move(list, E4, F6, QUIET));
    assert(count_moves_with_flag(list, CAPTURE) == 2);
    assert(count_moves_with_flag(list, QUIET) == 6);

    printf("  Passed.\n\n");
}

/**
 * Knight blocked by friendly pieces: cannot land on squares occupied by own pieces.
 */
void test_knight_blocked_by_friendly() {
    printf("=== Knight Blocked By Friendly ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KNIGHT], E4);
    set_bit(board.pieces[WHITE][PAWN], D6);  // blocks this square
    set_bit(board.pieces[WHITE][PAWN], F6);  // blocks this square
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_knight_moves(board, list);

    // 8 destinations minus 2 blocked by friendly = 6
    printf("  Knight moves: %d (expected 6)\n", list.count);
    assert(list.count == 6);

    printf("  Passed.\n\n");
}

/**
 * Two knights: both generate moves independently.
 */
void test_two_knights() {
    printf("=== Two Knights ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KNIGHT], B1);
    set_bit(board.pieces[WHITE][KNIGHT], G1);
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_knight_moves(board, list);

    // b1: a3, c3, d2 (but e1 is king = friendly, blocked) = 3 moves
    // g1: f3, h3, e2 = 3 moves (but not e1, blocked by king)
    // Wait, let me recalculate. b1 knight:
    //   up 2 right 1: c3 ✓
    //   up 2 left 1: a3 ✓
    //   up 1 right 2: d2 ✓
    //   up 1 left 2: off board (file -1)
    //   down moves: off board (rank -1 or -2)
    // = 3 moves
    // g1 knight:
    //   up 2 right 1: h3 ✓
    //   up 2 left 1: f3 ✓
    //   up 1 right 2: off board (file 8)
    //   up 1 left 2: e2 ✓
    //   down moves: off board
    // = 3 moves
    printf("  Knight moves: %d (expected 6)\n", list.count);
    assert(list.count == 6);

    assert(has_move(list, B1, A3, QUIET));
    assert(has_move(list, B1, C3, QUIET));
    assert(has_move(list, B1, D2, QUIET));
    assert(has_move(list, G1, F3, QUIET));
    assert(has_move(list, G1, H3, QUIET));
    assert(has_move(list, G1, E2, QUIET));

    printf("  Passed.\n\n");
}

/**
 * Starting position: both knights have 2 moves each (the only squares not blocked).
 */
void test_starting_position_knights() {
    printf("=== Starting Position Knights ===\n");
    BoardState board;
    initialize_board(board);

    MoveList list = {.count = 0};
    generate_knight_moves(board, list);

    // b1 knight: a3, c3 (d2 blocked by pawn)
    // g1 knight: f3, h3 (e2 blocked by pawn)
    printf("  Knight moves: %d (expected 4)\n", list.count);
    assert(list.count == 4);

    assert(has_move(list, B1, A3, QUIET));
    assert(has_move(list, B1, C3, QUIET));
    assert(has_move(list, G1, F3, QUIET));
    assert(has_move(list, G1, H3, QUIET));

    printf("  Passed.\n\n");
}

/**
 * Knight on h8 (opposite corner from a1): should have 2 moves.
 */
void test_knight_corner_h8() {
    printf("=== Knight Corner (h8) ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KNIGHT], H8);
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], A1);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_knight_moves(board, list);

    printf("  Knight moves: %d (expected 2)\n", list.count);
    assert(list.count == 2);

    assert(has_move(list, H8, G6, QUIET));
    assert(has_move(list, H8, F7, QUIET));

    printf("  Passed.\n\n");
}

int main() {
    test_knight_center();
    test_knight_corner();
    test_knight_edge();
    test_knight_captures();
    test_knight_blocked_by_friendly();
    test_two_knights();
    test_starting_position_knights();
    test_knight_corner_h8();

    printf("All knight move generation tests passed.\n");
    return 0;
}
