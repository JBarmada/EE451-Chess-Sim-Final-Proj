/**
 * @file test_board.cu
 * @brief Verification that the board state initializes correctly.
 *
 * Checks the starting position by counting pieces, verifying occupancy consistency,
 * and printing the board for visual inspection.
 */

#include "board.cuh"
#include "board_print.cuh"
#include <cstdio>
#include <cassert>

// NOTE: [pedagogical] __builtin_popcountll counts the number of set bits in a 64-bit
// integer. In chess programming this is called "popcount" and it tells you how many
// pieces are on a given bitboard. Modern CPUs and GPUs have hardware instructions for
// this, so it's essentially free.
int popcount(uint64_t bitboard) {
    return __builtin_popcountll(bitboard);
}

/**
 * Verify that all piece bitboards have the correct number of pieces for a starting position.
 */
void verify_piece_counts(const BoardState& board) {
    printf("=== Piece Count Verification ===\n");

    int expected_counts[2][6] = {
        {8, 2, 2, 2, 1, 1}, // white: 8 pawns, 2 knights, 2 bishops, 2 rooks, 1 queen, 1 king
        {8, 2, 2, 2, 1, 1}  // black: same
    };
    const char* piece_names[6] = {"pawns", "knights", "bishops", "rooks", "queens", "kings"};
    const char* color_names[2] = {"White", "Black"};

    for (int color = 0; color < 2; color++) {
        for (int piece = 0; piece < 6; piece++) {
            int count = popcount(board.pieces[color][piece]);
            printf("  %s %s: %d (expected %d)\n",
                   color_names[color], piece_names[piece],
                   count, expected_counts[color][piece]);
            assert(count == expected_counts[color][piece]);
        }
    }
    printf("  All piece counts correct.\n\n");
}

/**
 * Verify that occupancy bitboards are consistent with the individual piece boards.
 */
void verify_occupancy(const BoardState& board) {
    printf("=== Occupancy Verification ===\n");

    for (int color = 0; color < 2; color++) {
        uint64_t recomputed = 0;
        for (int piece = 0; piece < 6; piece++) {
            recomputed |= board.pieces[color][piece];
        }
        printf("  %s occupied matches: %s\n",
               color == WHITE ? "White" : "Black",
               recomputed == board.occupied[color] ? "yes" : "NO - MISMATCH");
        assert(recomputed == board.occupied[color]);
    }

    uint64_t recomputed_all = board.occupied[WHITE] | board.occupied[BLACK];
    printf("  All occupied matches: %s\n",
           recomputed_all == board.all_occupied ? "yes" : "NO - MISMATCH");
    assert(recomputed_all == board.all_occupied);

    // NOTE: [edge case callout] No two piece bitboards should share any set bits. If they
    // do, it means two pieces occupy the same square, which is an invalid board state.
    for (int c1 = 0; c1 < 2; c1++) {
        for (int p1 = 0; p1 < 6; p1++) {
            for (int c2 = c1; c2 < 2; c2++) {
                for (int p2 = (c1 == c2 ? p1 + 1 : 0); p2 < 6; p2++) {
                    uint64_t overlap = board.pieces[c1][p1] & board.pieces[c2][p2];
                    assert(overlap == 0 && "Two pieces occupy the same square!");
                }
            }
        }
    }
    printf("  No overlapping pieces.\n");

    printf("  Total pieces on board: %d (expected 32)\n", popcount(board.all_occupied));
    assert(popcount(board.all_occupied) == 32);
    printf("  All occupancy checks passed.\n\n");
}

/**
 * Verify the initial game state metadata.
 */
void verify_game_state(const BoardState& board) {
    printf("=== Game State Verification ===\n");

    assert(board.side_to_move == WHITE);
    printf("  Side to move: White ✓\n");

    assert(board.castling_rights == ALL_CASTLING);
    printf("  Castling rights: KQkq ✓\n");

    assert(board.en_passant_file == 8);
    printf("  En passant: none ✓\n");

    assert(board.halfmove_clock == 0);
    printf("  Halfmove clock: 0 ✓\n");

    assert(board.fullmove_counter == 1);
    printf("  Fullmove counter: 1 ✓\n");

    printf("  All game state checks passed.\n\n");
}

int main() {
    BoardState board;
    initialize_board(board);

    print_board(board);
    verify_piece_counts(board);
    verify_occupancy(board);
    verify_game_state(board);

    printf("All tests passed.\n");
    return 0;
}
