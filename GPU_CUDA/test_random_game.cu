/**
 * @file test_random_game.cu
 * @brief Play a single random chess game on the CPU to validate the entire pipeline.
 *
 * This is the end-to-end test: initialize a board, generate legal moves, pick one at
 * random, make it, check for game over, repeat. If this works without crashing, we can
 * be reasonably confident the move generation, make_move, and game-over detection are
 * correct before moving to the GPU.
 */

#include "board.cuh"
#include "board_print.cuh"
#include "game.cuh"
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <cassert>

int main() {
    srand(time(nullptr));

    BoardState board;
    initialize_board(board);

    printf("Playing a random game...\n\n");
    print_board(board);

    int move_number = 0;
    constexpr int MAX_DISPLAY_MOVES = 10;
    constexpr int MAX_GAME_LENGTH = 1000;

    while (true) {
        MoveList legal;
        generate_legal_moves(board, legal);

        GameResult result = check_game_over(board, legal);
        if (result != ONGOING) {
            printf("\n=== Game Over (move %d) ===\n", move_number);
            print_board(board);
            switch (result) {
                case WHITE_WINS:     printf("Result: White wins by checkmate!\n"); break;
                case BLACK_WINS:     printf("Result: Black wins by checkmate!\n"); break;
                case DRAW_STALEMATE: printf("Result: Draw by stalemate.\n"); break;
                case DRAW_50_MOVE:   printf("Result: Draw by 50-move rule.\n"); break;
                default: break;
            }
            break;
        }

        // Pick a random legal move
        int choice = rand() % legal.count;
        Move move = legal.moves[choice];

        // Print the first few moves for visual inspection
        if (move_number < MAX_DISPLAY_MOVES) {
            const char* side = (board.side_to_move == WHITE) ? "White" : "Black";
            int from_file = move.from % 8, from_rank = move.from / 8;
            int to_file = move.to % 8, to_rank = move.to / 8;
            printf("Move %d: %s %c%d -> %c%d\n",
                   move_number + 1, side,
                   'a' + from_file, from_rank + 1,
                   'a' + to_file, to_rank + 1);
        } else if (move_number == MAX_DISPLAY_MOVES) {
            printf("... (suppressing further move output)\n");
        }

        make_move(board, move);
        move_number++;

        // NOTE: [edge case callout] Random games can theoretically run forever (e.g.,
        // king vs king shuffling). The 50-move rule should catch this, but we add a hard
        // cap as a safety net.
        if (move_number >= MAX_GAME_LENGTH) {
            printf("\nGame exceeded %d moves, stopping.\n", MAX_GAME_LENGTH);
            print_board(board);
            break;
        }
    }

    printf("\nTotal moves played: %d\n", move_number);

    // Sanity checks on the final board state
    int white_king_count = __builtin_popcountll(board.pieces[WHITE][KING]);
    int black_king_count = __builtin_popcountll(board.pieces[BLACK][KING]);
    assert(white_king_count == 1 && "White should always have exactly 1 king");
    assert(black_king_count == 1 && "Black should always have exactly 1 king");
    printf("Sanity checks passed (both kings present).\n");

    return 0;
}
