/**
 * @file test_king_movegen.cu
 * @brief Tests for king move generation (non-castling) across a variety of positions.
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
 * King in the center (e4): should have 8 moves.
 */
void test_king_center() {
    printf("=== King Center (e4) ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KING], E4);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_king_moves(board, list);

    printf("  King moves: %d (expected 8)\n", list.count);
    assert(list.count == 8);

    assert(has_move(list, E4, D5, QUIET));
    assert(has_move(list, E4, E5, QUIET));
    assert(has_move(list, E4, F5, QUIET));
    assert(has_move(list, E4, D4, QUIET));
    assert(has_move(list, E4, F4, QUIET));
    assert(has_move(list, E4, D3, QUIET));
    assert(has_move(list, E4, E3, QUIET));
    assert(has_move(list, E4, F3, QUIET));

    printf("  Passed.\n\n");
}

/**
 * King in the corner (a1): should have 3 moves.
 */
void test_king_corner() {
    printf("=== King Corner (a1) ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KING], A1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_king_moves(board, list);

    printf("  King moves: %d (expected 3)\n", list.count);
    assert(list.count == 3);

    assert(has_move(list, A1, A2, QUIET));
    assert(has_move(list, A1, B2, QUIET));
    assert(has_move(list, A1, B1, QUIET));

    printf("  Passed.\n\n");
}

/**
 * King on the edge (a4): should have 5 moves.
 */
void test_king_edge() {
    printf("=== King Edge (a4) ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KING], A4);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_king_moves(board, list);

    printf("  King moves: %d (expected 5)\n", list.count);
    assert(list.count == 5);

    assert(has_move(list, A4, A5, QUIET));
    assert(has_move(list, A4, B5, QUIET));
    assert(has_move(list, A4, B4, QUIET));
    assert(has_move(list, A4, B3, QUIET));
    assert(has_move(list, A4, A3, QUIET));

    printf("  Passed.\n\n");
}

/**
 * King with captures and friendly blocking.
 */
void test_king_captures_and_blocking() {
    printf("=== King Captures and Blocking ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KING], E4);
    set_bit(board.pieces[WHITE][PAWN], E5);  // friendly, blocks
    set_bit(board.pieces[BLACK][PAWN], D5);  // enemy, capturable
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_king_moves(board, list);

    // 8 destinations minus 1 blocked by friendly pawn on e5 = 7 moves
    printf("  King moves: %d (expected 7)\n", list.count);
    assert(list.count == 7);

    assert(has_move(list, E4, D5, CAPTURE));
    assert(count_moves_with_flag(list, CAPTURE) == 1);
    assert(count_moves_with_flag(list, QUIET) == 6);

    printf("  Passed.\n\n");
}

/**
 * Starting position: king on e1 is completely surrounded by friendly pieces, 0 moves.
 */
void test_starting_position_king() {
    printf("=== Starting Position King ===\n");
    BoardState board;
    initialize_board(board);

    MoveList list = {.count = 0};
    generate_king_moves(board, list);

    printf("  King moves: %d (expected 0)\n", list.count);
    assert(list.count == 0);

    printf("  Passed.\n\n");
}

/**
 * H8 corner: king should have 3 moves and not wrap.
 */
void test_king_corner_h8() {
    printf("=== King Corner (h8) ===\n");
    BoardState board;
    clear_board(board);
    board.side_to_move = BLACK;

    set_bit(board.pieces[BLACK][KING], H8);
    set_bit(board.pieces[WHITE][KING], A1);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_king_moves(board, list);

    printf("  King moves: %d (expected 3)\n", list.count);
    assert(list.count == 3);

    assert(has_move(list, H8, G8, QUIET));
    assert(has_move(list, H8, G7, QUIET));
    assert(has_move(list, H8, H7, QUIET));

    printf("  Passed.\n\n");
}

int main() {
    test_king_center();
    test_king_corner();
    test_king_edge();
    test_king_captures_and_blocking();
    test_starting_position_king();
    test_king_corner_h8();

    printf("All king move generation tests passed.\n");
    return 0;
}
