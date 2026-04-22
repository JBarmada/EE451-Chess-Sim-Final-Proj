/**
 * @file test_castling_movegen.cu
 * @brief Tests for castling move generation.
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

/**
 * Both castling sides available with clear paths.
 */
void test_both_sides_available() {
    printf("=== Both Sides Available ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[WHITE][ROOK], A1);
    set_bit(board.pieces[WHITE][ROOK], H1);
    set_bit(board.pieces[BLACK][KING], E8);
    board.castling_rights = WHITE_KINGSIDE | WHITE_QUEENSIDE;
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_castling_moves(board, list);

    printf("  Castling moves: %d (expected 2)\n", list.count);
    assert(list.count == 2);
    assert(has_move(list, E1, G1, KINGSIDE_CASTLE));
    assert(has_move(list, E1, C1, QUEENSIDE_CASTLE));

    printf("  Passed.\n\n");
}

/**
 * Kingside blocked by a piece on f1.
 */
void test_kingside_blocked() {
    printf("=== Kingside Blocked ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[WHITE][ROOK], A1);
    set_bit(board.pieces[WHITE][ROOK], H1);
    set_bit(board.pieces[WHITE][BISHOP], F1); // blocks kingside
    set_bit(board.pieces[BLACK][KING], E8);
    board.castling_rights = WHITE_KINGSIDE | WHITE_QUEENSIDE;
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_castling_moves(board, list);

    printf("  Castling moves: %d (expected 1)\n", list.count);
    assert(list.count == 1);
    assert(has_move(list, E1, C1, QUEENSIDE_CASTLE));

    printf("  Passed.\n\n");
}

/**
 * Queenside blocked by a piece on b1.
 */
void test_queenside_blocked() {
    printf("=== Queenside Blocked ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[WHITE][ROOK], A1);
    set_bit(board.pieces[WHITE][ROOK], H1);
    set_bit(board.pieces[WHITE][KNIGHT], B1); // blocks queenside
    set_bit(board.pieces[BLACK][KING], E8);
    board.castling_rights = WHITE_KINGSIDE | WHITE_QUEENSIDE;
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_castling_moves(board, list);

    printf("  Castling moves: %d (expected 1)\n", list.count);
    assert(list.count == 1);
    assert(has_move(list, E1, G1, KINGSIDE_CASTLE));

    printf("  Passed.\n\n");
}

/**
 * Rights revoked: path is clear but castling rights have been lost.
 */
void test_rights_revoked() {
    printf("=== Rights Revoked ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[WHITE][ROOK], A1);
    set_bit(board.pieces[WHITE][ROOK], H1);
    set_bit(board.pieces[BLACK][KING], E8);
    board.castling_rights = 0; // no rights
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_castling_moves(board, list);

    printf("  Castling moves: %d (expected 0)\n", list.count);
    assert(list.count == 0);

    printf("  Passed.\n\n");
}

/**
 * Only kingside rights, queenside right revoked.
 */
void test_partial_rights() {
    printf("=== Partial Rights (Kingside Only) ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[WHITE][ROOK], A1);
    set_bit(board.pieces[WHITE][ROOK], H1);
    set_bit(board.pieces[BLACK][KING], E8);
    board.castling_rights = WHITE_KINGSIDE; // only kingside
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_castling_moves(board, list);

    printf("  Castling moves: %d (expected 1)\n", list.count);
    assert(list.count == 1);
    assert(has_move(list, E1, G1, KINGSIDE_CASTLE));

    printf("  Passed.\n\n");
}

/**
 * Black castling: both sides available.
 */
void test_black_castling() {
    printf("=== Black Castling Both Sides ===\n");
    BoardState board;
    clear_board(board);
    board.side_to_move = BLACK;

    set_bit(board.pieces[BLACK][KING], E8);
    set_bit(board.pieces[BLACK][ROOK], A8);
    set_bit(board.pieces[BLACK][ROOK], H8);
    set_bit(board.pieces[WHITE][KING], E1);
    board.castling_rights = BLACK_KINGSIDE | BLACK_QUEENSIDE;
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_castling_moves(board, list);

    printf("  Castling moves: %d (expected 2)\n", list.count);
    assert(list.count == 2);
    assert(has_move(list, E8, G8, KINGSIDE_CASTLE));
    assert(has_move(list, E8, C8, QUEENSIDE_CASTLE));

    printf("  Passed.\n\n");
}

/**
 * Starting position: both sides have rights but all paths are blocked.
 */
void test_starting_position_castling() {
    printf("=== Starting Position Castling ===\n");
    BoardState board;
    initialize_board(board);

    MoveList list = {.count = 0};
    generate_castling_moves(board, list);

    printf("  Castling moves: %d (expected 0)\n", list.count);
    assert(list.count == 0);

    printf("  Passed.\n\n");
}

int main() {
    test_both_sides_available();
    test_kingside_blocked();
    test_queenside_blocked();
    test_rights_revoked();
    test_partial_rights();
    test_black_castling();
    test_starting_position_castling();

    printf("All castling move generation tests passed.\n");
    return 0;
}
