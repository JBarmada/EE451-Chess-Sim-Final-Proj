/**
 * @file test_queen_movegen.cu
 * @brief Tests for queen move generation — verifies it combines bishop and rook behavior.
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
 * Queen in center: should equal bishop moves + rook moves from the same square.
 *
 * Queen on d4 with only kings on the board.
 * Rook component (N+S+W+E): 14 moves (same as rook center test)
 * Bishop component (NW+NE+SW+SE): 13 moves from d4
 *   NW: c5,b6,a7 (3)  NE: e5,f6,g7,h8(capture) (4)
 *   SW: c3,b2,a1(own king) (2)  SE: e3,f2,g1 (3)  => 12
 * Total: 14 + 12 = 26
 */
void test_queen_center() {
    printf("=== Queen Center ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][QUEEN], D4);
    set_bit(board.pieces[WHITE][KING], A1);
    set_bit(board.pieces[BLACK][KING], H8);
    recompute_occupancy(board);

    print_board(board);

    // Generate queen, bishop, and rook moves from the same position to verify
    // queen = bishop + rook.
    MoveList queen_list = {.count = 0};
    generate_queen_moves(board, queen_list);

    // Replace queen with bishop for comparison
    board.pieces[WHITE][QUEEN] = 0;
    set_bit(board.pieces[WHITE][BISHOP], D4);
    recompute_occupancy(board);
    MoveList bishop_list = {.count = 0};
    generate_bishop_moves(board, bishop_list);

    // Replace bishop with rook
    board.pieces[WHITE][BISHOP] = 0;
    set_bit(board.pieces[WHITE][ROOK], D4);
    recompute_occupancy(board);
    MoveList rook_list = {.count = 0};
    generate_rook_moves(board, rook_list);

    printf("  Queen moves: %d, Bishop moves: %d, Rook moves: %d\n",
           queen_list.count, bishop_list.count, rook_list.count);
    printf("  Expected queen = bishop + rook = %d\n",
           bishop_list.count + rook_list.count);

    assert(queen_list.count == bishop_list.count + rook_list.count);

    // Verify all bishop and rook moves appear in queen list
    for (int i = 0; i < bishop_list.count; i++) {
        assert(has_move(queen_list, bishop_list.moves[i].from,
                        bishop_list.moves[i].to, bishop_list.moves[i].flag));
    }
    for (int i = 0; i < rook_list.count; i++) {
        assert(has_move(queen_list, rook_list.moves[i].from,
                        rook_list.moves[i].to, rook_list.moves[i].flag));
    }

    printf("  Passed.\n\n");
}

/**
 * Starting position: queen has 0 moves (surrounded by own pieces).
 */
void test_starting_position_queen() {
    printf("=== Starting Position Queen ===\n");
    BoardState board;
    initialize_board(board);

    MoveList list = {.count = 0};
    generate_queen_moves(board, list);

    printf("  Queen moves: %d (expected 0)\n", list.count);
    assert(list.count == 0);

    printf("  Passed.\n\n");
}

/**
 * Queen with mixed captures and blocks.
 */
void test_queen_captures() {
    printf("=== Queen Captures ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][QUEEN], D4);
    set_bit(board.pieces[BLACK][PAWN], D6);  // blocks N after d5
    set_bit(board.pieces[BLACK][PAWN], F6);  // blocks NE after e5
    set_bit(board.pieces[WHITE][PAWN], B4);  // blocks W after c4
    set_bit(board.pieces[WHITE][KING], E1);
    set_bit(board.pieces[BLACK][KING], E8);
    recompute_occupancy(board);

    print_board(board);

    MoveList list = {.count = 0};
    generate_queen_moves(board, list);

    // Check some specific moves
    assert(has_move(list, D4, D6, CAPTURE));
    assert(has_move(list, D4, F6, CAPTURE));
    assert(!has_move(list, D4, B4, QUIET));   // blocked by own pawn
    assert(!has_move(list, D4, B4, CAPTURE)); // own piece, can't capture
    assert(has_move(list, D4, C4, QUIET));    // one square before own pawn

    printf("  Queen moves: %d\n", list.count);
    assert(count_moves_with_flag(list, CAPTURE) == 2);

    printf("  Passed.\n\n");
}

/**
 * Queen on a1 corner: should cover entire a-file, 1st rank, and a1-h8 diagonal.
 */
void test_queen_corner() {
    printf("=== Queen Corner (a1) ===\n");
    BoardState board;
    clear_board(board);

    set_bit(board.pieces[WHITE][QUEEN], A1);
    set_bit(board.pieces[WHITE][KING], H1);
    set_bit(board.pieces[BLACK][KING], H8);
    recompute_occupancy(board);

    MoveList list = {.count = 0};
    generate_queen_moves(board, list);

    // North: a2-a8 (7)
    // East: b1-g1 (6, blocked by own king on h1)
    // NE diagonal: b2,c3,d4,e5,f6,g7,h8(capture) (7)
    // Other directions: off board (0)
    // Total: 20
    printf("  Queen moves: %d (expected 20)\n", list.count);
    assert(list.count == 20);

    assert(has_move(list, A1, H8, CAPTURE));
    assert(has_move(list, A1, A8, QUIET));

    printf("  Passed.\n\n");
}

int main() {
    test_queen_center();
    test_starting_position_queen();
    test_queen_captures();
    test_queen_corner();

    printf("All queen move generation tests passed.\n");
    return 0;
}
