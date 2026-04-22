/**
 * @file test_rook_movegen.cu
 * @brief Tests for rook move generation.
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
 * Rook in center of empty-ish board: covers full rank and file minus blocked squares.
 *
 * Rook on d4, only kings on the board:
 *   North: d5, d6, d7, d8 (4)
 *   South: d3, d2, d1 (3)
 *   West:  c4, b4, a4 (3)
 *   East:  e4, f4, g4, h4 (4)
 *   Total: 14
 */
void test_rook_center_open() {
    printf("=== Rook Center Open Board ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][ROOK], D4);
    set_bit(board.pieces[WHITE][KING], A1);
    set_bit(board.pieces[BLACK][KING], H8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_rook_moves(board, list);

    // d-file: d5,d6,d7,d8 (4) + d3,d2,d1 (but a1 has our king, d1 is fine) (3) = 7
    // 4th rank: c4,b4,a4 (but a1 is king, a4 is fine) (3) + e4,f4,g4,h4 (but h8 is king, h4 fine) (4) = 7
    // Total: 14
    printf("  Rook moves: %d (expected 14)\n", list.count);
    assert(list.count == 14);

    assert(has_move(list, D4, D8, QUIET));
    assert(has_move(list, D4, D1, QUIET));
    assert(has_move(list, D4, A4, QUIET));
    assert(has_move(list, D4, H4, QUIET));

    printf("  Passed.\n\n");
}

/**
 * Rook in corner (a1): covers entire a-file and 1st rank.
 */
void test_rook_corner() {
    printf("=== Rook Corner (a1) ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][ROOK], A1);
    set_bit(board.pieces[WHITE][KING], H8);
    set_bit(board.pieces[BLACK][KING], H1);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_rook_moves(board, list);

    // North: a2-a8 (7)
    // East: b1-g1 + h1 (capture) (7)
    // South, West: off board (0)
    // Total: 14
    printf("  Rook moves: %d (expected 14)\n", list.count);
    assert(list.count == 14);

    assert(has_move(list, A1, A8, QUIET));
    assert(has_move(list, A1, H1, CAPTURE));

    printf("  Passed.\n\n");
}

/**
 * Rook blocked on all sides by friendly pieces.
 */
void test_rook_fully_blocked() {
    printf("=== Rook Fully Blocked ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][ROOK], D4);
    set_bit(board.pieces[WHITE][PAWN], D5);
    set_bit(board.pieces[WHITE][PAWN], D3);
    set_bit(board.pieces[WHITE][PAWN], C4);
    set_bit(board.pieces[WHITE][PAWN], E4);
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_rook_moves(board, list);

    printf("  Rook moves: %d (expected 0)\n", list.count);
    assert(list.count == 0);

    printf("  Passed.\n\n");
}

/**
 * Rook with captures: enemy pieces on the file and rank block and can be captured.
 */
void test_rook_captures() {
    printf("=== Rook Captures ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][ROOK], D4);
    set_bit(board.pieces[BLACK][PAWN], D6);  // blocks north after d5
    set_bit(board.pieces[BLACK][PAWN], B4);  // blocks west after c4
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_rook_moves(board, list);

    // North: d5, d6 (capture) (2)
    // South: d3, d2, d1 (3)
    // West: c4, b4 (capture) (2)
    // East: e4, f4, g4, h4 (4)
    // Total: 11
    printf("  Rook moves: %d (expected 11)\n", list.count);
    assert(list.count == 11);

    assert(has_move(list, D4, D6, CAPTURE));
    assert(has_move(list, D4, B4, CAPTURE));
    assert(has_move(list, D4, D5, QUIET));
    assert(count_moves_with_flag(list, CAPTURE) == 2);

    printf("  Passed.\n\n");
}

/**
 * Starting position: rooks are hemmed in, 0 moves.
 */
void test_starting_position_rooks() {
    printf("=== Starting Position Rooks ===\n");
    BoardState board;
    initialize_board(board);

    MoveList list = {.count = 0};
    generate_rook_moves(board, list);

    printf("  Rook moves: %d (expected 0)\n", list.count);
    assert(list.count == 0);

    printf("  Passed.\n\n");
}

/**
 * Two rooks on the same file: they block each other.
 */
void test_two_rooks_same_file() {
    printf("=== Two Rooks Same File ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][ROOK], A1);
    set_bit(board.pieces[WHITE][ROOK], A8);
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_rook_moves(board, list);

    // a1 rook:
    //   North: a2,a3,a4,a5,a6,a7 (blocked by own rook on a8) = 6
    //   East: b1,c1,d1 (blocked by own king on e1) = 3
    //   Total: 9
    // a8 rook:
    //   South: a7,a6,a5,a4,a3,a2 (blocked by own rook on a1) = 6
    //   East: b8,c8,d8 (blocked by enemy king on e8, which is capture) = 4
    //   Total: 10
    // Grand total: 19
    printf("  Rook moves: %d (expected 19)\n", list.count);
    assert(list.count == 19);

    assert(has_move(list, A8, E8, CAPTURE));

    printf("  Passed.\n\n");
}

int main() {
    test_rook_center_open();
    test_rook_corner();
    test_rook_fully_blocked();
    test_rook_captures();
    test_starting_position_rooks();
    test_two_rooks_same_file();

    printf("All rook move generation tests passed.\n");
    return 0;
}
