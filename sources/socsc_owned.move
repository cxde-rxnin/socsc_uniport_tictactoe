module socsc_owned::owned;

use sui::event;
use sui::transfer::Receiving;

public struct Game has key, store {
    id: UID,
    board: vector<u8>,
    turn: u8,
    x: address,
    o: address,
    admin: address,
}

public struct TurnCap has key {
    id: UID,
    game: ID,
}

public struct Mark has key, store {
    id: UID,
    player: address,
    row: u8,
    col: u8,
}

public struct Trophy has key {
    id: UID,
    status: u8,
    board: vector<u8>,
    turn: u8,
    other: address,
}

public struct MarkSent has copy, drop {
    game: ID,
    mark: ID,
}

public struct GameEnd has copy, drop {
    game: ID,
}

const MARK__: u8 = 0;
const MARK_X: u8 = 1;
const MARK_O: u8 = 2;

const TROPHY_NONE: u8 = 0;
const TROPHY_DRAW: u8 = 1;
const TROPHY_WIN: u8 = 2;

#[error]
const EInvalidLocation: vector<u8> = b"Move was for a position that doesn't exist on the board";

#[error]
const EWrongPlayer: vector<u8> = b"Game expected a move from another player";

#[error]
const ENotFinished: vector<u8> = b"Game has not reached an end condition";

#[error]
const EAlreadyFinished: vector<u8> = b"Can't place a mark on a finished game";

#[error]
const EInvalidEndState: vector<u8> = b"Game reached an end state that wasn't expected";

#[error]
const ENotAdmin: u64 = 0xA1;

public fun new(x: address, o: address, admin: address, ctx: &mut TxContext): Game {
    let game = Game {
        id: object::new(ctx),
        board: vector[MARK__, MARK__, MARK__, MARK__, MARK__, MARK__, MARK__, MARK__, MARK__],
        turn: 0,
        x,
        o,
        admin,
    };

    let turn = TurnCap {
        id: object::new(ctx),
        game: object::id(&game),
    };

    transfer::transfer(turn, x);
    game
}

public fun send_mark(cap: TurnCap, row: u8, col: u8, ctx: &mut TxContext) {
    assert!(row < 3 && col < 3, EInvalidLocation);

    let TurnCap { id, game } = cap;
    id.delete();

    let mark = Mark {
        id: object::new(ctx),
        player: ctx.sender(),
        row,
        col,
    };

    event::emit(MarkSent { game, mark: object::id(&mark) });
    transfer::transfer(mark, game.to_address());
}

public fun place_mark(game: &mut Game, mark: Receiving<Mark>, ctx: &mut TxContext) {
    assert!(ctx.sender() == game.x || ctx.sender() == game.o || ctx.sender() == game.admin, ENotAdmin);
    assert!(game.ended() == TROPHY_NONE, EAlreadyFinished);

    let Mark { id, row, col, player } = transfer::receive(&mut game.id, mark);
    id.delete();

    let (me, them, sentinel) = game.next_player();
    assert!(me == player, EWrongPlayer);

    if (game[row, col] == MARK__) {
        *(&mut game[row, col]) = sentinel;
        game.turn = game.turn + 1;
    };

    let end = game.ended();
    if (end == TROPHY_WIN) {
        transfer::transfer(game.mint_trophy(end, them, ctx), me);
        event::emit(GameEnd { game: object::id(game) });
    } else if (end == TROPHY_DRAW) {
        transfer::transfer(game.mint_trophy(end, them, ctx), me);
        transfer::transfer(game.mint_trophy(end, me, ctx), them);
        event::emit(GameEnd { game: object::id(game) });
    } else if (end == TROPHY_NONE) {
        let cap = TurnCap { id: object::new(ctx), game: object::id(game) };
        let (to, _, _) = game.next_player();
        transfer::transfer(cap, to);
    } else {
        abort EInvalidEndState
    }
}

public fun burn(game: Game, ctx: &mut TxContext) {
    assert!(ctx.sender() == game.x || ctx.sender() == game.o || ctx.sender() == game.admin, ENotAdmin);
    assert!(game.ended() != TROPHY_NONE, ENotFinished);
    let Game { id, .. } = game;
    id.delete();
}

public fun ended(game: &Game): u8 {
    if (
        test_triple(game, 0, 1, 2) ||
        test_triple(game, 3, 4, 5) ||
        test_triple(game, 6, 7, 8) ||
        test_triple(game, 0, 3, 6) ||
        test_triple(game, 1, 4, 7) ||
        test_triple(game, 2, 5, 8) ||
        test_triple(game, 0, 4, 8) ||
        test_triple(game, 2, 4, 6)) {
        TROPHY_WIN
    } else if (game.turn == 9) {
        TROPHY_DRAW
    } else {
        TROPHY_NONE
    }
}

#[syntax(index)]
public fun mark(game: &Game, row: u8, col: u8): &u8 {
    &game.board[(row * 3 + col) as u64]
}

#[syntax(index)]
fun mark_mut(game: &mut Game, row: u8, col: u8): &mut u8 {
    &mut game.board[(row * 3 + col) as u64]
}

fun next_player(game: &Game): (address, address, u8) {
    if (game.turn % 2 == 0) {
        (game.x, game.o, MARK_X)
    } else {
        (game.o, game.x, MARK_O)
    }
}

fun test_triple(game: &Game, x: u8, y: u8, z: u8): bool {
    let x = game.board[x as u64];
    let y = game.board[y as u64];
    let z = game.board[z as u64];

    MARK__ != x && x == y && y == z
}

fun mint_trophy(game: &Game, status: u8, other: address, ctx: &mut TxContext): Trophy {
    Trophy {
        id: object::new(ctx),
        status,
        board: game.board,
        turn: game.turn,
        other,
    }
}

#[test_only]
public use fun game_board as Game.board;
#[test_only]
public use fun trophy_status as Trophy.status;
#[test_only]
public use fun trophy_board as Trophy.board;
#[test_only]
public use fun trophy_turn as Trophy.turn;
#[test_only]
public use fun trophy_other as Trophy.other;

#[test_only]
public fun game_board(game: &Game): vector<u8> {
    game.board
}

#[test_only]
public fun trophy_status(trophy: &Trophy): u8 {
    trophy.status
}

#[test_only]
public fun trophy_board(trophy: &Trophy): vector<u8> {
    trophy.board
}

#[test_only]
public fun trophy_turn(trophy: &Trophy): u8 {
    trophy.turn
}

#[test_only]
public fun trophy_other(trophy: &Trophy): address {
    trophy.other
}