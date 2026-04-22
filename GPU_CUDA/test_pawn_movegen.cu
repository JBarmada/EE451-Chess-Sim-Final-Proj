/**
 * @file test_pawn_movegen.cu
 * @brief Tests for pawn move generation across a variety of board positions.
 *
 * Each test sets up a specific position by manually placing pieces on the bitboards,
 * generates pawn moves, and verifies the results against known-correct move counts
 * and specific expected moves.
 */

#include "board.cuh"
#include "board_print.cuh"
#include "movegen.cuh"
#include <cstdio>
#include <cassert>

/**
 * Zero out all fields of a BoardState.
 */
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

/**
 * Recompute occupancy bitboards from the piece bitboards.
 */
void recompute_occupancy(BoardState& board) {
    board.occupied[WHITE] = 0;
    board.occupied[BLACK] = 0;
    for (int p = 0; p < 6; p++) {
        board.occupied[WHITE] |= board.pieces[WHITE][p];
        board.occupied[BLACK] |= board.pieces[BLACK][p];
    }
    board.all_occupied = board.occupied[WHITE] | board.occupied[BLACK];
}

/**
 * Check whether a specific move exists in the move list.
 */
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
 * Count moves in the list that have a specific flag.
 */
int count_moves_with_flag(const MoveList& list, MoveFlag flag) {
    int count = 0;
    for (int i = 0; i < list.count; i++) {
        if (list.moves[i].flag == flag) count++;
    }
    return count;
}

/**
 * Print all moves in a move list for debugging.
 */
void print_moves(const MoveList& list) {
    const char* flag_names[] = {
        "quiet", "double_push", "O-O", "O-O-O",
        "capture", "en_passant", "?6", "?7",
        "=N", "=B", "=R", "=Q",
        "x=N", "x=B", "x=R", "x=Q"
    };
    for (int i = 0; i < list.count; i++) {
        Move m = list.moves[i];
        int from_file = m.from % 8, from_rank = m.from / 8;
        int to_file = m.to % 8, to_rank = m.to / 8;
        printf("  %c%d -> %c%d  [%s]\n",
               'a' + from_file, from_rank + 1,
               'a' + to_file, to_rank + 1,
               flag_names[m.flag]);
    }
}

// === Tests ===

/**
 * Starting position: each side has 16 pawn moves (8 single + 8 double pushes).
 */
void test_starting_position() {
    printf("=== Starting Position ===\n");
    BoardState board;
    initialize_board(board);

    MoveList list = {.count = 0};
    generate_pawn_moves(board, list);

    printf("  White pawn moves: %d (expected 16)\n", list.count);
    assert(list.count == 16);

    assert(count_moves_with_flag(list, QUIET) == 8);
    assert(count_moves_with_flag(list, DOUBLE_PAWN_PUSH) == 8);

    // Spot check: e2-e3 (single) and e2-e4 (double)
    assert(has_move(list, E2, E3, QUIET));
    assert(has_move(list, E2, E4, DOUBLE_PAWN_PUSH));

    printf("  Passed.\n\n");
}

/**
 * Black's turn from the starting position: same 16 moves but in the opposite direction.
 */
void test_starting_position_black() {
    printf("=== Starting Position (Black) ===\n");
    BoardState board;
    initialize_board(board);
    board.side_to_move = BLACK;

    MoveList list = {.count = 0};
    generate_pawn_moves(board, list);

    printf("  Black pawn moves: %d (expected 16)\n", list.count);
    assert(list.count == 16);

    assert(has_move(list, E7, E6, QUIET));
    assert(has_move(list, E7, E5, DOUBLE_PAWN_PUSH));

    printf("  Passed.\n\n");
}

/**
 * A blocked pawn cannot push. Place a white pawn on e4 with an enemy piece on e5.
 */
void test_blocked_pawn() {
    printf("=== Blocked Pawn ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][PAWN], E4);
    set_bit(board.pieces[BLACK][PAWN], E5);
    set_bit(board.pieces[WHITE][KING], E1); // king needed for a valid position
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_pawn_moves(board, list);

    printf("  White pawn moves: %d (expected 0)\n", list.count);
    assert(list.count == 0);

    printf("  Passed.\n\n");
}

/**
 * Captures: a white pawn on d4 with black pawns on c5 and e5 can capture both.
 */
void test_pawn_captures() {
    printf("=== Pawn Captures ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][PAWN], D4);
    set_bit(board.pieces[BLACK][PAWN], C5);
    set_bit(board.pieces[BLACK][PAWN], E5);
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_pawn_moves(board, list);

    print_moves(list);
    // d4-d5 (single push), d4xc5, d4xe5
    printf("  White pawn moves: %d (expected 3)\n", list.count);
    assert(list.count == 3);

    assert(has_move(list, D4, D5, QUIET));
    assert(has_move(list, D4, C5, CAPTURE));
    assert(has_move(list, D4, E5, CAPTURE));

    printf("  Passed.\n\n");
}

/**
 * A-file pawn should not wrap captures to the h-file.
 */
void test_a_file_no_wrap() {
    printf("=== A-File No Wrap ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][PAWN], A4);
    set_bit(board.pieces[BLACK][PAWN], B5); // valid capture target
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_pawn_moves(board, list);

    print_moves(list);
    // a4-a5 (push), a4xb5 (capture). No wrap to h-file.
    printf("  White pawn moves: %d (expected 2)\n", list.count);
    assert(list.count == 2);

    assert(has_move(list, A4, A5, QUIET));
    assert(has_move(list, A4, B5, CAPTURE));

    printf("  Passed.\n\n");
}

/**
 * H-file pawn should not wrap captures to the a-file.
 */
void test_h_file_no_wrap() {
    printf("=== H-File No Wrap ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][PAWN], H4);
    set_bit(board.pieces[BLACK][PAWN], G5); // valid capture target
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_pawn_moves(board, list);

    // h4-h5 (push), h4xg5 (capture). No wrap to a-file.
    printf("  White pawn moves: %d (expected 2)\n", list.count);
    assert(list.count == 2);

    assert(has_move(list, H4, H5, QUIET));
    assert(has_move(list, H4, G5, CAPTURE));

    printf("  Passed.\n\n");
}

/**
 * En passant: white pawn on e5, black just double-pushed d7-d5.
 */
void test_en_passant() {
    printf("=== En Passant ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][PAWN], E5);
    set_bit(board.pieces[BLACK][PAWN], D5); // just double-pushed
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    board.en_passant_file = 3; // d-file
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_pawn_moves(board, list);

    print_moves(list);
    // e5-e6 (push), e5xd6 (en passant)
    printf("  White pawn moves: %d (expected 2)\n", list.count);
    assert(list.count == 2);

    assert(has_move(list, E5, E6, QUIET));
    assert(has_move(list, E5, D6, EN_PASSANT));

    printf("  Passed.\n\n");
}

/**
 * Double en passant: two white pawns can both capture en passant.
 */
void test_double_en_passant() {
    printf("=== Double En Passant ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][PAWN], C5);
    set_bit(board.pieces[WHITE][PAWN], E5);
    set_bit(board.pieces[BLACK][PAWN], D5); // just double-pushed
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    board.en_passant_file = 3; // d-file
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_pawn_moves(board, list);

    print_moves(list);
    // c5-c6, e5-e6 (pushes), c5xd6 (en passant), e5xd6 (en passant)
    printf("  White pawn moves: %d (expected 4)\n", list.count);
    assert(list.count == 4);

    assert(has_move(list, C5, D6, EN_PASSANT));
    assert(has_move(list, E5, D6, EN_PASSANT));

    printf("  Passed.\n\n");
}

/**
 * Promotion: a white pawn on e7 with no blocking piece pushes to e8 and promotes.
 */
void test_promotion_push() {
    printf("=== Promotion Push ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][PAWN], E7);
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], A8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_pawn_moves(board, list);

    print_moves(list);
    // e7-e8 promotes to Q, R, B, N = 4 moves
    printf("  White pawn moves: %d (expected 4)\n", list.count);
    assert(list.count == 4);

    assert(has_move(list, E7, E8, PROMOTE_QUEEN));
    assert(has_move(list, E7, E8, PROMOTE_ROOK));
    assert(has_move(list, E7, E8, PROMOTE_BISHOP));
    assert(has_move(list, E7, E8, PROMOTE_KNIGHT));

    printf("  Passed.\n\n");
}

/**
 * Promotion with capture: white pawn on e7, black rook on d8 and black knight on f8.
 */
void test_promotion_capture() {
    printf("=== Promotion Capture ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][PAWN], E7);
    set_bit(board.pieces[BLACK][ROOK], D8);
    set_bit(board.pieces[BLACK][KNIGHT], F8);
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], A8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_pawn_moves(board, list);

    print_moves(list);
    // e7-e8 (push promote) x4 + e7xd8 (capture promote) x4 + e7xf8 (capture promote) x4 = 12
    printf("  White pawn moves: %d (expected 12)\n", list.count);
    assert(list.count == 12);

    assert(has_move(list, E7, E8, PROMOTE_QUEEN));
    assert(has_move(list, E7, D8, CAPTURE_PROMOTE_QUEEN));
    assert(has_move(list, E7, F8, CAPTURE_PROMOTE_KNIGHT));

    printf("  Passed.\n\n");
}

/**
 * Black promotion: black pawn on b2, white piece on a1 for capture.
 */
void test_black_promotion() {
    printf("=== Black Promotion ===\n");
    BoardState board;
    clear_board(board);
    board.side_to_move = BLACK;

    set_bit(board.pieces[BLACK][PAWN], B2);
    set_bit(board.pieces[WHITE][ROOK], A1);
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_pawn_moves(board, list);

    print_moves(list);
    // b2-b1 (push promote) x4 + b2xa1 (capture promote) x4 = 8
    printf("  Black pawn moves: %d (expected 8)\n", list.count);
    assert(list.count == 8);

    assert(has_move(list, B2, B1, PROMOTE_QUEEN));
    assert(has_move(list, B2, A1, CAPTURE_PROMOTE_QUEEN));

    printf("  Passed.\n\n");
}

/**
 * Double push blocked: pawn on e2, friendly piece on e3 blocks both single and double push.
 */
void test_double_push_blocked_intermediate() {
    printf("=== Double Push Blocked By Intermediate Piece ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][PAWN], E2);
    set_bit(board.pieces[WHITE][KNIGHT], E3); // blocks single and double push
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_pawn_moves(board, list);

    printf("  White pawn moves: %d (expected 0)\n", list.count);
    assert(list.count == 0);

    printf("  Passed.\n\n");
}

/**
 * Double push blocked on destination only: pawn on e2, piece on e4, e3 is empty.
 */
void test_double_push_blocked_destination() {
    printf("=== Double Push Blocked On Destination ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][PAWN], E2);
    set_bit(board.pieces[BLACK][PAWN], E4); // blocks only the double push
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_pawn_moves(board, list);

    print_moves(list);
    // e2-e3 only (double push blocked by piece on e4)
    printf("  White pawn moves: %d (expected 1)\n", list.count);
    assert(list.count == 1);

    assert(has_move(list, E2, E3, QUIET));

    printf("  Passed.\n\n");
}

int main() {
    test_starting_position();
    test_starting_position_black();
    test_blocked_pawn();
    test_pawn_captures();
    test_a_file_no_wrap();
    test_h_file_no_wrap();
    test_en_passant();
    test_double_en_passant();
    test_promotion_push();
    test_promotion_capture();
    test_black_promotion();
    test_double_push_blocked_intermediate();
    test_double_push_blocked_destination();

    printf("All pawn move generation tests passed.\n");
    return 0;
}
