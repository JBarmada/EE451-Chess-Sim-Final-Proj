/**
 * @file test_bishop_movegen.cu
 * @brief Tests for bishop move generation.
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
 * Bishop in the center of an empty board: should reach maximum diagonal squares.
 *
 * A bishop on d4 with no blockers can reach:
 *   NW: c5, b6, a7 (3)
 *   NE: e5, f6, g7, h8 (4)
 *   SW: c3, b2, a1 (3)
 *   SE: e3, f2, g1 (3)
 *   Total: 13
 */
void test_bishop_center_open() {
    printf("=== Bishop Center Open Board ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][BISHOP], D4);
    set_bit(board.pieces[WHITE][KING], A1);
    set_bit(board.pieces[BLACK][KING], H8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_bishop_moves(board, list);

    // a1 and h8 are occupied by kings — bishop will be blocked/capture
    // NW: c5, b6, a7 (3)
    // NE: e5, f6, g7, h8 (capture) (4)
    // SW: c3, b2, a1 (blocked by own king, so c3, b2 only) (2)
    // SE: e3, f2, g1 (3)
    // Total: 12
    printf("  Bishop moves: %d (expected 12)\n", list.count);
    assert(list.count == 12);

    assert(has_move(list, D4, C5, QUIET));
    assert(has_move(list, D4, A7, QUIET));
    assert(has_move(list, D4, H8, CAPTURE));
    assert(has_move(list, D4, G1, QUIET));

    printf("  Passed.\n\n");
}

/**
 * Bishop blocked on all diagonals by friendly pieces close by.
 */
void test_bishop_fully_blocked() {
    printf("=== Bishop Fully Blocked ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][BISHOP], D4);
    set_bit(board.pieces[WHITE][PAWN], C5);
    set_bit(board.pieces[WHITE][PAWN], E5);
    set_bit(board.pieces[WHITE][PAWN], C3);
    set_bit(board.pieces[WHITE][PAWN], E3);
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_bishop_moves(board, list);

    printf("  Bishop moves: %d (expected 0)\n", list.count);
    assert(list.count == 0);

    printf("  Passed.\n\n");
}

/**
 * Bishop in corner (a1): can only go along one diagonal.
 */
void test_bishop_corner() {
    printf("=== Bishop Corner (a1) ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][BISHOP], A1);
    set_bit(board.pieces[WHITE][KING], H1);
    set_bit(board.pieces[BLACK][KING], H8);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_bishop_moves(board, list);

    // Only NE diagonal: b2, c3, d4, e5, f6, g7, h8 (capture) = 7
    printf("  Bishop moves: %d (expected 7)\n", list.count);
    assert(list.count == 7);

    assert(has_move(list, A1, B2, QUIET));
    assert(has_move(list, A1, G7, QUIET));
    assert(has_move(list, A1, H8, CAPTURE));

    printf("  Passed.\n\n");
}

/**
 * Bishop with captures: enemy pieces on some diagonals act as blockers and capture targets.
 */
void test_bishop_captures() {
    printf("=== Bishop Captures ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][BISHOP], D4);
    set_bit(board.pieces[BLACK][PAWN], F6);   // blocks NE diagonal after e5
    set_bit(board.pieces[BLACK][ROOK], B2);   // blocks SW diagonal after c3
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_bishop_moves(board, list);

    // NW: c5, b6, a7 (3)
    // NE: e5, f6 (capture, stops) (2)
    // SW: c3, b2 (capture, stops) (2)
    // SE: e3, f2, g1 (3)
    // Total: 10
    printf("  Bishop moves: %d (expected 10)\n", list.count);
    assert(list.count == 10);

    assert(has_move(list, D4, F6, CAPTURE));
    assert(has_move(list, D4, B2, CAPTURE));
    assert(has_move(list, D4, E5, QUIET));
    assert(count_moves_with_flag(list, CAPTURE) == 2);

    printf("  Passed.\n\n");
}

/**
 * Starting position: bishops are completely blocked by pawns, 0 moves.
 */
void test_starting_position_bishops() {
    printf("=== Starting Position Bishops ===\n");
    BoardState board;
    initialize_board(board);

    MoveList list = {.count = 0};
    generate_bishop_moves(board, list);

    printf("  Bishop moves: %d (expected 0)\n", list.count);
    assert(list.count == 0);

    printf("  Passed.\n\n");
}

/**
 * Two bishops generating moves simultaneously.
 */
void test_two_bishops() {
    printf("=== Two Bishops ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][BISHOP], C1);
    set_bit(board.pieces[WHITE][BISHOP], F1);
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_bishop_moves(board, list);

    // c1 bishop:
    //   NW: b2, a3 (2)
    //   NE: d2, e3, f4, g5, h6 (but e1 is king direction? No, NE from c1 is d2,e3,etc)
    //   Wait: d2 is NE? c1 is file 2, rank 0. NE = file+1, rank+1 = d2. Yes.
    //   NE: d2, e3, f4, g5, h6 (5)
    //   SW: b0? off board (0)
    //   SE: d0? off board (0)
    //   Total: 7
    // f1 bishop:
    //   NW: e2, d3, c4, b5, a6 (but e1 has king... e2 is rank 1 file 4, f1 NW is e2)
    //   NW: e2, d3, c4, b5, a6 (5)
    //   NE: g2, h3 (2)
    //   SW: e0? off board (0)
    //   SE: g0? off board (0)
    //   Total: 7
    printf("  Bishop moves: %d (expected 14)\n", list.count);
    assert(list.count == 14);

    printf("  Passed.\n\n");
}

int main() {
    test_bishop_center_open();
    test_bishop_fully_blocked();
    test_bishop_corner();
    test_bishop_captures();
    test_starting_position_bishops();
    test_two_bishops();

    printf("All bishop move generation tests passed.\n");
    return 0;
}
