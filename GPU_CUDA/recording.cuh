/**
 * @file recording.cuh
 * @brief Game recording and PGN output for the GPU chess simulator.
 *
 * Provides two structs used by the kernel and host respectively:
 *   - GameStats:    lightweight per-game result written by every thread
 *   - RecordedGame: full move history written only for the first N threads
 *
 * Also provides host-side helpers for rendering recorded games as PGN,
 * which is the standard chess game notation accepted by tools like Lichess
 * and Arena.
 *
 * NOTE: [design] Keeping recording separate from main.cu lets the kernel
 * include only this header (not board_print.cuh or ctime) and keeps the
 * PGN logic easy to find and extend independently of simulation logic.
 */

#pragma once

#include "board.cuh"
#include "game.cuh"
#include <cstdio>

// === Constants ===

// NOTE: [thought process] MAX_GAME_LENGTH caps the game loop to avoid
// infinite games in degenerate positions. 1000 half-moves is extremely
// generous — the longest known chess games are under 300 moves (600
// half-moves). This constant sizes the move_history array in RecordedGame,
// so it must be known at compile time.
constexpr int MAX_GAME_LENGTH    = 1000;

// Number of games for which the kernel writes a full move history.
// Only these games incur the extra ~3 KB per-game memory cost.
// The rest write only result + game_length into d_results.
constexpr int NUM_RECORDED_GAMES = 10;

// === Structs ===

/**
 * Lightweight per-game output written by every thread into d_results.
 */
struct GameStats {
    GameResult result;
    uint16_t   game_length; // total half-moves played
};

/**
 * Full per-game record written only for the first NUM_RECORDED_GAMES threads.
 *
 * Memory: sizeof(Move) == 3 bytes, so move_history costs 3 KB per game.
 * At the default of 10 games that is 30 KB on the device — negligible.
 */
struct RecordedGame {
    GameResult result;
    uint16_t   game_length;
    Move       move_history[MAX_GAME_LENGTH];
};

// === PGN Helpers (host-side only) ===

// Convert a 0-63 square index to its file letter ('a'-'h').
static inline char file_char(int square) { return 'a' + (square % 8); }

// Convert a 0-63 square index to its rank digit ('1'-'8').
static inline char rank_char(int square) { return '1' + (square / 8); }

/**
 * Return the promotion piece letter based on the lower 2 bits of the flag.
 *
 * The MoveFlag encoding from movegen.cuh maps the lower 2 bits as:
 *   0 = Knight, 1 = Bishop, 2 = Rook, 3 = Queen
 * This matches the PROMOTE_* and CAPTURE_PROMOTE_* flag values exactly.
 */
static inline const char* promo_letter(MoveFlag flag) {
    switch (flag & 3) {
        case 0:  return "N";
        case 1:  return "B";
        case 2:  return "R";
        case 3:  return "Q";
        default: return "Q";
    }
}

/**
 * Return the standard PGN result token for a game outcome.
 */
static inline const char* result_string(GameResult r) {
    switch (r) {
        case WHITE_WINS: return "1-0";
        case BLACK_WINS: return "0-1";
        default:         return "1/2-1/2";
    }
}

/**
 * Return a human-readable termination description for the PGN Termination tag.
 */
static inline const char* termination_string(GameResult r) {
    switch (r) {
        case WHITE_WINS:     return "White wins by checkmate";
        case BLACK_WINS:     return "Black wins by checkmate";
        case DRAW_STALEMATE: return "Draw by stalemate";
        case DRAW_50_MOVE:   return "Draw by 50-move rule";
        default:             return "Unknown";
    }
}

/**
 * Render a single Move into buf using coordinate (UCI-style) notation.
 *
 * Output format per move type:
 *   - Normal move:   "e2e4"
 *   - Capture:       "d5e6"       (same format — destination tells you it's a capture)
 *   - En passant:    "d5e6e.p."
 *   - Promotion:     "e7e8=Q"
 *   - Capture+promo: "d7e8=Q"
 *   - Kingside:      "O-O"
 *   - Queenside:     "O-O-O"
 *
 * Returns the number of characters written (excluding the null terminator).
 *
 * NOTE: [thought process] Full SAN (e.g. "Nf3", "exd5+") requires replaying
 * the position at each step to determine which piece moved and whether the
 * move gives check. Coordinate notation is unambiguous, nearly as readable,
 * and requires only the from/to squares and the MoveFlag — no board needed.
 */
static inline int move_to_str(char* buf, Move move) {
    MoveFlag flag = move.flag;

    if (flag == KINGSIDE_CASTLE)  return sprintf(buf, "O-O");
    if (flag == QUEENSIDE_CASTLE) return sprintf(buf, "O-O-O");

    // Base coordinate pair: "e2e4"
    int n = sprintf(buf, "%c%c%c%c",
                    file_char(move.from), rank_char(move.from),
                    file_char(move.to),   rank_char(move.to));

    // Promotion suffix — bit 3 of flag set means any promotion variant
    if (flag & 8) {
        n += sprintf(buf + n, "=%s", promo_letter(flag));
    }

    // En passant annotation
    if (flag == EN_PASSANT) {
        n += sprintf(buf + n, "e.p.");
    }

    return n;
}

/**
 * Print a single RecordedGame to stdout as a complete PGN game.
 *
 * Outputs the seven mandatory PGN tag pairs followed by the move text in
 * coordinate notation, soft-wrapped at ~80 columns, and terminated with the
 * result token as required by the PGN standard.
 *
 * The output can be pasted directly into the Lichess analysis board or any
 * PGN-compliant chess GUI.
 */
static inline void print_pgn(int game_number, const RecordedGame& game) {
    const char* result_str = result_string(game.result);

    // --- PGN tag pairs ---
    // NOTE: [pedagogical] PGN requires exactly these seven "roster tags" in this
    // order: Event, Site, Date, Round, White, Black, Result. We omit Date because
    // we'd need to pass it in; chess GUIs tolerate "?" for unknown fields.
    printf("[Event \"GPU Random Game\"]\n");
    printf("[Site \"CUDA GPU\"]\n");
    printf("[Date \"????.??.??\"]\n");
    printf("[Round \"%d\"]\n",       game_number);
    printf("[White \"Random\"]\n");
    printf("[Black \"Random\"]\n");
    printf("[Result \"%s\"]\n",      result_str);
    printf("[PlyCount \"%d\"]\n",    game.game_length);
    printf("[Termination \"%s\"]\n", termination_string(game.result));
    printf("\n");

    // --- Move text ---
    // NOTE: [pedagogical] PGN numbers full moves: "1. e2e4 e7e5 2. g1f3 ...".
    // Half-move index i corresponds to a white move when i is even, black when odd.
    char move_buf[16];
    int  col = 0; // approximate column cursor for soft line-wrapping

    for (int i = 0; i < game.game_length; i++) {
        if (i % 2 == 0) {
            col += printf("%d. ", (i / 2) + 1);
        }

        int len = move_to_str(move_buf, game.move_history[i]);
        printf("%s ", move_buf);
        col += len + 1;

        // Soft-wrap at ~80 columns to keep the file readable in any editor
        if (col >= 72) {
            printf("\n");
            col = 0;
        }
    }

    // PGN standard requires the result token as the last token in the move text
    printf("%s\n\n", result_str);
}