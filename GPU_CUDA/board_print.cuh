/**
 * @file board_print.cuh
 * @brief Host-side ASCII rendering of a BoardState for debugging.
 *
 * This prints the board from white's perspective (rank 8 at top, rank 1 at bottom)
 * using Unicode chess piece characters for readability.
 */

#pragma once

#include "board.cuh"
#include <cstdio>

// NOTE: [pedagogical] Unicode chess symbols make the board much easier to read than
// letter-based notation. The symbols are indexed by [color][piece_type] to match
// our BoardState layout. These are standard Unicode code points in the "Miscellaneous
// Symbols" block (U+2654 to U+265F).
constexpr const char* PIECE_SYMBOLS[2][6] = {
    {"♙", "♘", "♗", "♖", "♕", "♔"}, // WHITE: pawn, knight, bishop, rook, queen, king
    {"♟", "♞", "♝", "♜", "♛", "♚"}  // BLACK: pawn, knight, bishop, rook, queen, king
};

/**
 * Find which piece (if any) occupies a given square.
 *
 * Returns true if a piece was found, and sets color and piece_type accordingly.
 * Returns false if the square is empty.
 */
inline bool find_piece_on_square(const BoardState& board, int square,
                                 Color& color, PieceType& piece_type) {
    for (int c = 0; c < 2; c++) {
        for (int p = 0; p < 6; p++) {
            if (test_bit(board.pieces[c][p], square)) {
                color = static_cast<Color>(c);
                piece_type = static_cast<PieceType>(p);
                return true;
            }
        }
    }
    return false;
}

/**
 * Print the board as ASCII art to stdout.
 *
 * Renders the board from white's perspective with rank and file labels, plus the
 * current game state (side to move, castling rights, en passant, move counters).
 */
inline void print_board(const BoardState& board) {
    printf("\n");
    // NOTE: [thought process] We print from rank 8 down to rank 1 so the board appears
    // with white at the bottom, which is the conventional orientation.
    for (int rank = 7; rank >= 0; rank--) {
        printf("  %d  ", rank + 1);
        for (int file = 0; file < 8; file++) {
            int square = rank * 8 + file;
            Color color;
            PieceType piece_type;
            if (find_piece_on_square(board, square, color, piece_type)) {
                printf(" %s", PIECE_SYMBOLS[color][piece_type]);
            } else {
                printf(" .");
            }
        }
        printf("\n");
    }
    printf("\n     ");
    for (int file = 0; file < 8; file++) {
        printf(" %c", 'a' + file);
    }
    printf("\n\n");

    // === Game State ===
    printf("  Side to move:    %s\n", board.side_to_move == WHITE ? "White" : "Black");
    printf("  Castling rights: %s%s%s%s%s\n",
           (board.castling_rights & WHITE_KINGSIDE)  ? "K" : "",
           (board.castling_rights & WHITE_QUEENSIDE) ? "Q" : "",
           (board.castling_rights & BLACK_KINGSIDE)  ? "k" : "",
           (board.castling_rights & BLACK_QUEENSIDE) ? "q" : "",
           (board.castling_rights == 0)              ? "-" : "");
    printf("  En passant file: %s\n",
           board.en_passant_file < 8
               ? (const char[]){(char)('a' + board.en_passant_file), '\0'}
               : "-");
    printf("  Halfmove clock:  %d\n", board.halfmove_clock);
    printf("  Fullmove:        %d\n", board.fullmove_counter);
    printf("\n");
}
