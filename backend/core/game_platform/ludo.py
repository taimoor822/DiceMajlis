"""
Ludo on the platform: :mod:`ludo_engine` behind the :class:`GameEngine` contract.

The engine stays exactly as it is (and in step with the app's Dart copy through
the shared test vectors); this adapter only translates.
"""

from __future__ import annotations

from typing import Any, Iterable, Mapping, Sequence

import ludo_engine as le
from ludo_engine import GameState, PlayerStatus, Rules, TurnPhase

from .contract import RandomSource, RoomOption, TurnInfo, Variant

LUDO = "ludo"
CLASSIC = "classic"


class LudoGame:
    game_type = LUDO
    default_variant = CLASSIC
    variants: Mapping[str, Variant] = {
        # Today's rules (ludo_engine.Rules defaults). Ranked plays Classic.
        CLASSIC: Variant(
            code=CLASSIC,
            min_players=le.MIN_PLAYERS,
            max_players=le.MAX_PLAYERS,
            default_players=le.MAX_PLAYERS,
            ranked=True,
            # Custom rules a private room's host may pick (keys are Rules fields;
            # the app shows them by key). Any change makes the room unranked.
            options=(
                RoomOption("turn_timeout_seconds", 30, (15, 30, 60)),
                RoomOption("capture_enabled", True, (True, False)),
                RoomOption("extra_turn_on_six", True, (True, False)),
                # False: play on after the first winner, until every place is decided.
                RoomOption("end_when_first_player_finishes", True, (True, False)),
            ),
        ),
    }
    rule_error = le.EngineError
    player_action_types = frozenset({"roll", "move"})

    # ---- setup -------------------------------------------------------------

    def rules(self, variant: str, options: Mapping[str, Any] | None = None) -> Rules:
        preset = self.variants[variant].rules
        return Rules.from_dict({**Rules().to_dict(), **preset, **(options or {})})

    def rules_for(self, variant: str) -> dict[str, Any]:
        return self.rules(variant).to_dict()

    def new_game(
        self,
        game_id: str,
        player_ids: Sequence[str],
        *,
        variant: str,
        seats: Sequence[int] | None = None,
        first_player_id: str | None = None,
        options: Mapping[str, Any] | None = None,
    ) -> GameState:
        if not self.variants[variant].allows(len(player_ids)):
            raise le.InvalidSetup(f"{variant} needs a different number of players")
        return le.new_game(
            game_id,
            player_ids,
            seats=seats,
            rules=self.rules(variant, options),
            first_player_id=first_player_id,
        )

    # ---- storage -------------------------------------------------------------

    def load(self, data: Mapping[str, Any]) -> GameState:
        return GameState.from_dict(data)

    def dump(self, state: GameState) -> dict[str, Any]:
        return state.to_dict()

    def info(self, state: GameState) -> TurnInfo:
        return TurnInfo(
            version=state.version,
            finished=state.is_finished,
            current_player_id=state.current_player.player_id,
            turn_number=state.turn_number,
            turn_seconds=state.rules.turn_timeout_seconds,
            warning_seconds=state.rules.timeout_warning_seconds,
            winner_id=state.winner_id,
            active_player_ids=tuple(
                p.player_id for p in state.players if p.status is PlayerStatus.ACTIVE
            ),
        )

    # ---- actions -------------------------------------------------------------

    def prepare_action(
        self, state: GameState, action: Mapping[str, Any], random: RandomSource
    ) -> dict[str, Any]:
        """
        The server's part of an action:
          - "roll": the server rolls (a value sent by the app is ignored)
          - "bot": the bot's roll or move for ``player_id``
          - "timeout": the turn's dice, when a roll is due
        Everything else is passed on for the engine to check.
        """
        kind = action.get("type")
        if kind == "roll":
            player_id = str(action["player_id"])
            le.check_roll(state, player_id)  # refused requests never touch the dice
            return {"type": "roll", "player_id": player_id, "value": _die(random)}
        if kind == "bot":
            player_id = str(action["player_id"])
            if state.is_finished or state.current_player.player_id != player_id:
                le.check_roll(state, player_id)  # raises the right error
            return self.prepare_action(state, self.bot_action(state), random)
        if kind == "timeout":
            expected_turn = action.get("turn_number", state.turn_number)
            le.check_timeout(state, expected_turn)  # stale timers never touch the dice
            rolling = state.phase is TurnPhase.AWAITING_ROLL
            return {
                "type": "timeout",
                "turn_number": expected_turn,
                "dice_value": _die(random) if rolling else None,
            }
        return dict(action)

    def apply_action(self, state: GameState, action: Mapping[str, Any]) -> le.Transition:
        return le.apply_action(state, action)

    def legal_actions(self, state: GameState, player_id: str) -> list[dict[str, Any]]:
        if state.is_finished or state.current_player.player_id != player_id:
            return []
        if state.phase is TurnPhase.AWAITING_ROLL:
            return [{"type": "roll", "player_id": player_id}]
        return [
            {"type": "move", "player_id": player_id, "token_index": m.token_index}
            for m in le.legal_moves(state)
        ]

    def bot_action(self, state: GameState) -> dict[str, Any]:
        player_id = state.current_player.player_id
        if state.phase is TurnPhase.AWAITING_ROLL:
            return {"type": "roll", "player_id": player_id}
        return {
            "type": "move",
            "player_id": player_id,
            "token_index": le.choose_move(state).token_index,
        }

    # ---- reading -------------------------------------------------------------

    def view_for(self, state: GameState, player_id: str | None) -> dict[str, Any]:
        return state.to_dict()  # Ludo has no hidden information

    def standings(self, state: GameState) -> list[dict[str, Any]]:
        return le.standings(state)

    def replay(self, initial: GameState, actions: Iterable[Mapping[str, Any]]) -> GameState:
        return le.replay(initial, actions)


def _die(random: RandomSource) -> int:
    return random.randbelow(6) + 1
