"""
The Ludo rules engine.

Pure functions only: no Django, no database, no clock, no randomness. Each
public action takes a ``GameState`` and returns a ``Transition`` (new state +
events) or raises an ``EngineError``. Dice values are rolled by the caller
(see ``dice.SecureDice``) and passed in, so the same list of actions always
produces the same game. That is what ``replay`` relies on.

Public actions
    roll(state, player_id, value)
    move(state, player_id, token_index)
    timeout(state, dice_value=..., expected_turn=...)
    forfeit(state, player_id)
    apply_action(state, action_dict)     # one entry point for sockets and replays
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Any, Iterable, Mapping, Sequence

from .board import (
    BASE_PROGRESS,
    HOME_PROGRESS,
    SEAT_COUNT,
    START_PROGRESS,
    absolute_square,
    default_seats_for,
    is_home,
)
from .errors import (
    GameNotActive,
    IllegalMove,
    InvalidAction,
    InvalidDiceValue,
    InvalidSetup,
    NotYourTurn,
    WrongPhase,
)
from .events import Event, EventType, Transition, TurnEndReason
from .rules import DEFAULT_RULES, Rules
from .state import (
    GameState,
    GameStatus,
    PlayerState,
    PlayerStatus,
    TurnPhase,
    initial_tokens,
)


# ---------------------------------------------------------------------------
# Moves
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Capture:
    player_id: str
    token_index: int


@dataclass(frozen=True)
class Move:
    token_index: int
    from_progress: int
    to_progress: int
    to_square: int | None
    captures: tuple[Capture, ...] = ()

    @property
    def enters_board(self) -> bool:
        return self.from_progress == BASE_PROGRESS

    @property
    def finishes_token(self) -> bool:
        return is_home(self.to_progress)

    def to_dict(self) -> dict[str, Any]:
        return {
            "token_index": self.token_index,
            "from_progress": self.from_progress,
            "to_progress": self.to_progress,
            "to_square": self.to_square,
            "captures": [
                {"player_id": c.player_id, "token_index": c.token_index} for c in self.captures
            ],
        }


def legal_moves(state: GameState) -> tuple[Move, ...]:
    """Moves the current player may make right now (empty unless a move is due)."""
    if state.is_finished or state.phase is not TurnPhase.AWAITING_MOVE:
        return ()
    assert state.dice_value is not None
    return _moves_for(state, state.current_index, state.dice_value)


def _moves_for(state: GameState, player_index: int, dice: int) -> tuple[Move, ...]:
    player = state.players[player_index]
    moves: list[Move] = []
    for token_index, progress in enumerate(player.tokens):
        if is_home(progress):
            continue
        if progress == BASE_PROGRESS:
            if dice not in state.rules.entry_rolls:
                continue
            to_progress = START_PROGRESS
        else:
            to_progress = progress + dice
            if to_progress > HOME_PROGRESS:  # must land on home exactly
                continue
        to_square = absolute_square(player.seat, to_progress)
        moves.append(
            Move(
                token_index=token_index,
                from_progress=progress,
                to_progress=to_progress,
                to_square=to_square,
                captures=_captures_at(state, player_index, to_square),
            )
        )
    return tuple(moves)


def _captures_at(state: GameState, mover_index: int, square: int | None) -> tuple[Capture, ...]:
    rules = state.rules
    if square is None or not rules.capture_enabled or square in rules.safe_squares:
        return ()
    captures: list[Capture] = []
    for index, other in enumerate(state.players):
        if index == mover_index or other.status is PlayerStatus.FORFEITED:
            continue
        for token_index, progress in enumerate(other.tokens):
            # Compare ABSOLUTE squares. Comparing raw progress across seats was the
            # bug in game/utils.py: equal progress means different squares.
            if absolute_square(other.seat, progress) == square:
                captures.append(Capture(other.player_id, token_index))
    return tuple(captures)


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------


def new_game(
    game_id: str,
    player_ids: Sequence[str],
    *,
    seats: Sequence[int] | None = None,
    rules: Rules = DEFAULT_RULES,
    first_player_id: str | None = None,
) -> GameState:
    """
    Create a game at version 0. Turn order is clockwise by seat. Two players
    sit opposite each other (seats 0 and 2) unless ``seats`` says otherwise.
    """
    ids = [str(p) for p in player_ids]
    if not 2 <= len(ids) <= SEAT_COUNT:
        raise InvalidSetup(f"Ludo needs 2 to {SEAT_COUNT} players, got {len(ids)}")
    if len(set(ids)) != len(ids):
        raise InvalidSetup("player ids must be unique")

    seat_list = list(seats) if seats is not None else list(default_seats_for(len(ids)))
    if len(seat_list) != len(ids):
        raise InvalidSetup("one seat per player is required")
    for seat in seat_list:
        if not isinstance(seat, int) or isinstance(seat, bool) or not 0 <= seat < SEAT_COUNT:
            raise InvalidSetup(f"seat must be 0..{SEAT_COUNT - 1}, got {seat!r}")
    if len(set(seat_list)) != len(seat_list):
        raise InvalidSetup("seats must be unique")

    players = tuple(
        PlayerState(player_id=pid, seat=seat, tokens=initial_tokens(rules))
        for seat, pid in sorted(zip(seat_list, ids))
    )
    state = GameState(game_id=str(game_id), players=players, rules=rules)
    if first_player_id is not None:
        state = replace(state, current_index=state.index_of(str(first_player_id)))
    return state


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------


class _Step:
    """Collects the events of ONE action; the whole action gets one new version."""

    def __init__(self, state: GameState) -> None:
        self.state = state
        self.version = state.version + 1
        self.events: list[Event] = []

    def emit(self, event_type: EventType, **data: Any) -> None:
        self.events.append(Event(event_type, self.version, data))

    def done(self) -> Transition:
        return Transition(replace(self.state, version=self.version), tuple(self.events))


def check_roll(state: GameState, player_id: str) -> int:
    """
    Raise unless ``player_id`` may roll now; return their player index.
    The server calls this BEFORE rolling, so invalid requests never touch the dice.
    """
    _require_playing(state)
    index = _require_turn(state, player_id)
    if state.phase is not TurnPhase.AWAITING_ROLL:
        raise WrongPhase("dice already rolled: move a token")
    return index


def roll(state: GameState, player_id: str, value: int) -> Transition:
    """Apply a server-rolled dice value for the current player."""
    index = check_roll(state, player_id)
    _check_die(value)
    step = _Step(_reset_missed_turns(state, index))
    _apply_roll(step, value)
    return step.done()


def move(state: GameState, player_id: str, token_index: int) -> Transition:
    """Move one of the current player's tokens by the rolled value."""
    _require_playing(state)
    index = _require_turn(state, player_id)
    if state.phase is not TurnPhase.AWAITING_MOVE:
        raise WrongPhase("roll the dice first")
    if (
        not isinstance(token_index, int)
        or isinstance(token_index, bool)
        or not 0 <= token_index < state.rules.tokens_per_player
    ):
        raise IllegalMove(f"no token {token_index!r}")
    step = _Step(_reset_missed_turns(state, index))
    _apply_move(step, token_index)
    return step.done()


def timeout(
    state: GameState,
    *,
    dice_value: int | None = None,
    expected_turn: int | None = None,
) -> Transition:
    """
    The current player's turn timer ran out (the server owns the clock).

    Counts a missed turn; after ``rules.max_missed_turns`` in a row the player
    forfeits. Otherwise the engine plays for them: rolls ``dice_value`` (the
    server must supply it when a roll is due) and makes the bot's move.

    Pass ``expected_turn`` = the ``turn_number`` the timer was started for, so a
    timer that fires just after the player acted is rejected instead of
    punishing the next player.
    """
    _require_playing(state)
    if expected_turn is not None and expected_turn != state.turn_number:
        raise InvalidAction("stale timeout: that turn is already over")
    if state.phase is TurnPhase.AWAITING_ROLL:
        if dice_value is None:
            raise InvalidDiceValue("a server dice value is needed to auto-roll")
        _check_die(dice_value)

    index = state.current_index
    player = state.current_player
    missed = player.missed_turns + 1
    step = _Step(state.with_player(index, replace(player, missed_turns=missed)))
    step.emit(
        EventType.PLAYER_TIMEOUT,
        player_id=player.player_id,
        missed_turns=missed,
        phase=state.phase.value,
    )

    limit = state.rules.max_missed_turns
    if limit and missed >= limit:
        _apply_forfeit(step, index, reason="timeout")
        return step.done()

    if step.state.phase is TurnPhase.AWAITING_ROLL:
        assert dice_value is not None
        _apply_roll(step, dice_value)
        if step.state.phase is not TurnPhase.AWAITING_MOVE:
            return step.done()  # roll ended the turn (no moves / too many sixes)

    from .bot import choose_move  # local import: bot depends on this module

    _apply_move(step, choose_move(step.state).token_index)
    return step.done()


def forfeit(state: GameState, player_id: str, *, reason: str = "left") -> Transition:
    """A player leaves (or is removed). They take the lowest place still free."""
    _require_playing(state)
    index = state.index_of(player_id)
    step = _Step(state)
    _apply_forfeit(step, index, reason=reason)
    return step.done()


def apply_action(state: GameState, action: Mapping[str, Any]) -> Transition:
    """
    Single entry point used by the socket layer and by ``replay``.

    Actions: {"type": "roll", "player_id", "value"}
             {"type": "move", "player_id", "token_index"}
             {"type": "timeout", "dice_value"?, "turn_number"?}
             {"type": "forfeit", "player_id", "reason"?}
    """
    kind = action.get("type")
    try:
        if kind == "roll":
            return roll(state, str(action["player_id"]), action["value"])
        if kind == "move":
            return move(state, str(action["player_id"]), action["token_index"])
        if kind == "timeout":
            return timeout(
                state,
                dice_value=action.get("dice_value"),
                expected_turn=action.get("turn_number"),
            )
        if kind == "forfeit":
            return forfeit(state, str(action["player_id"]), reason=str(action.get("reason", "left")))
    except KeyError as missing:
        raise InvalidAction(f"{kind} action is missing {missing}") from None
    raise InvalidAction(f"unknown action type {kind!r}")


def replay(initial: GameState, actions: Iterable[Mapping[str, Any]]) -> GameState:
    """Rebuild a game from its starting state and recorded actions (audits, disputes)."""
    state = initial
    for action in actions:
        state = apply_action(state, action).state
    return state


def standings(state: GameState) -> list[dict[str, Any]]:
    """Places 1..n. Final once the game is finished; provisional while it is running."""
    places = _final_places(state)
    order = sorted(range(len(state.players)), key=lambda i: places[i])
    return [
        {
            "player_id": state.players[i].player_id,
            "place": places[i],
            "status": state.players[i].status.value,
        }
        for i in order
    ]


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


def _apply_roll(step: _Step, value: int) -> None:
    state = step.state
    player = state.current_player
    sixes = state.consecutive_sixes + 1 if value == 6 else 0
    limit = state.rules.max_consecutive_sixes

    if limit and sixes >= limit:
        step.emit(
            EventType.DICE_RESULT,
            player_id=player.player_id,
            value=value,
            consecutive_sixes=sixes,
            movable_tokens=[],
        )
        step.state = replace(state, consecutive_sixes=sixes)
        _end_turn(step, TurnEndReason.TOO_MANY_SIXES, extra_turn=False)
        return

    moves = _moves_for(state, state.current_index, value)
    step.emit(
        EventType.DICE_RESULT,
        player_id=player.player_id,
        value=value,
        consecutive_sixes=sixes,
        movable_tokens=[m.token_index for m in moves],
    )
    if not moves:
        step.state = replace(state, consecutive_sixes=sixes)
        _end_turn(step, TurnEndReason.NO_LEGAL_MOVES, extra_turn=False)
        return

    step.state = replace(
        state, phase=TurnPhase.AWAITING_MOVE, dice_value=value, consecutive_sixes=sixes
    )


def _apply_move(step: _Step, token_index: int) -> None:
    state = step.state
    index = state.current_index
    player = state.current_player
    dice = state.dice_value
    assert dice is not None

    chosen = next(
        (m for m in _moves_for(state, index, dice) if m.token_index == token_index), None
    )
    if chosen is None:
        raise IllegalMove(f"token {token_index} cannot move {dice}")

    state = state.with_player(index, player.with_token(token_index, chosen.to_progress))
    step.emit(
        EventType.TOKEN_MOVED,
        player_id=player.player_id,
        token_index=token_index,
        from_progress=chosen.from_progress,
        to_progress=chosen.to_progress,
        from_square=absolute_square(player.seat, chosen.from_progress),
        to_square=chosen.to_square,
        dice=dice,
    )

    for capture in chosen.captures:
        victim_index = state.index_of(capture.player_id)
        victim = state.players[victim_index]
        state = state.with_player(
            victim_index, victim.with_token(capture.token_index, BASE_PROGRESS)
        )
        step.emit(
            EventType.TOKEN_CAPTURED,
            player_id=capture.player_id,
            token_index=capture.token_index,
            square=chosen.to_square,
            by_player_id=player.player_id,
        )

    if chosen.finishes_token:
        step.emit(EventType.TOKEN_FINISHED, player_id=player.player_id, token_index=token_index)

    step.state = state

    if chosen.finishes_token and state.players[index].all_tokens_home:
        _player_finished(step, index)
        if not step.state.is_finished:
            _end_turn(step, TurnEndReason.PLAYER_FINISHED, extra_turn=False)
        return

    rules = state.rules
    extra_turn = (
        (dice == 6 and rules.extra_turn_on_six)
        or (bool(chosen.captures) and rules.extra_turn_on_capture)
        or (chosen.finishes_token and rules.extra_turn_on_finish)
    )
    _end_turn(step, TurnEndReason.MOVED, extra_turn=extra_turn)


def _end_turn(step: _Step, reason: TurnEndReason, *, extra_turn: bool) -> None:
    state = step.state
    current = state.current_player
    keeps_turn = extra_turn and current.status is PlayerStatus.ACTIVE

    step.emit(
        EventType.TURN_ENDED,
        player_id=current.player_id,
        reason=reason.value,
        extra_turn=keeps_turn,
    )

    next_index = state.current_index if keeps_turn else _next_active_index(state)
    step.state = replace(
        state,
        current_index=next_index,
        phase=TurnPhase.AWAITING_ROLL,
        dice_value=None,
        # Sixes keep counting through extra turns; a new player starts from zero.
        consecutive_sixes=state.consecutive_sixes if keeps_turn else 0,
        turn_number=state.turn_number + 1,
    )
    step.emit(
        EventType.TURN_STARTED,
        player_id=step.state.current_player.player_id,
        turn_number=step.state.turn_number,
        extra_turn=keeps_turn,
    )


def _player_finished(step: _Step, index: int) -> None:
    state = step.state
    place = 1 + sum(
        1 for p in state.players if p.status is PlayerStatus.FINISHED and p.finish_place
    )
    player = replace(state.players[index], status=PlayerStatus.FINISHED, finish_place=place)
    step.state = state.with_player(index, player)
    step.emit(EventType.PLAYER_FINISHED, player_id=player.player_id, place=place)

    if state.rules.end_when_first_player_finishes or _active_count(step.state) <= 1:
        _finish_game(step)


def _apply_forfeit(step: _Step, index: int, *, reason: str) -> None:
    state = step.state
    player = state.players[index]
    if player.status is not PlayerStatus.ACTIVE:
        raise InvalidAction(f"player {player.player_id!r} is not active")

    already_out = sum(1 for p in state.players if p.status is PlayerStatus.FORFEITED)
    place = len(state.players) - already_out  # forfeits fill places from the bottom
    state = state.with_player(
        index, replace(player, status=PlayerStatus.FORFEITED, finish_place=place)
    )
    step.state = state
    step.emit(
        EventType.PLAYER_FORFEITED, player_id=player.player_id, reason=reason, place=place
    )

    if _active_count(state) <= 1:
        _finish_game(step)
    elif index == state.current_index:
        _end_turn(step, TurnEndReason.FORFEITED, extra_turn=False)


def _finish_game(step: _Step) -> None:
    state = step.state
    places = _final_places(state)
    players = tuple(
        p if p.finish_place is not None else replace(p, finish_place=places[i])
        for i, p in enumerate(state.players)
    )
    winner = next(p for p in players if p.finish_place == 1)
    step.state = replace(
        state,
        players=players,
        status=GameStatus.FINISHED,
        phase=TurnPhase.AWAITING_ROLL,
        dice_value=None,
        winner_id=winner.player_id,
    )
    step.emit(
        EventType.GAME_FINISHED,
        winner_id=winner.player_id,
        standings=standings(step.state),
    )


def _final_places(state: GameState) -> list[int]:
    """Fixed places (finished/forfeited) stay; everyone else is ranked by progress."""
    count = len(state.players)
    places: list[int | None] = [p.finish_place for p in state.players]
    free = [k for k in range(1, count + 1) if k not in set(places)]
    unplaced = sorted(
        (i for i, p in enumerate(places) if p is None),
        key=lambda i: (-_progress_score(state.players[i]), state.players[i].seat),
    )
    for place, i in zip(free, unplaced):
        places[i] = place
    return [int(p) for p in places]  # type: ignore[arg-type]


def _progress_score(player: PlayerState) -> int:
    return sum(progress + 1 for progress in player.tokens)  # base = 0, home = 57


def _next_active_index(state: GameState) -> int:
    count = len(state.players)
    for step in range(1, count + 1):
        candidate = (state.current_index + step) % count
        if state.players[candidate].status is PlayerStatus.ACTIVE:
            return candidate
    return state.current_index


def _active_count(state: GameState) -> int:
    return sum(1 for p in state.players if p.status is PlayerStatus.ACTIVE)


def _reset_missed_turns(state: GameState, index: int) -> GameState:
    player = state.players[index]
    if player.missed_turns == 0:
        return state
    return state.with_player(index, replace(player, missed_turns=0))


def _require_playing(state: GameState) -> None:
    if state.is_finished:
        raise GameNotActive("the game is finished")


def _require_turn(state: GameState, player_id: str) -> int:
    index = state.index_of(str(player_id))
    if index != state.current_index:
        raise NotYourTurn(f"it is {state.current_player.player_id}'s turn")
    return index


def _check_die(value: Any) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or not 1 <= value <= 6:
        raise InvalidDiceValue(f"dice value must be 1..6, got {value!r}")
