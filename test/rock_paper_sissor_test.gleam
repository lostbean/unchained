import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleeunit

import smith.{type Agent}
import smith/task
import smith/types.{type AgentError, type AgentId, type Tool}

pub fn main() {
  gleeunit.main()
}

// Game-specific types
pub type Move {
  Rock
  Paper
  Scissors
}

pub type GameResult {
  Win(winner: AgentId)
  Draw
}

// Specific game-related tools
fn create_move_selection_tool() -> Tool {
  types.Tool(
    id: "move_selector",
    name: "Move Selection Tool",
    description: "Generates a random move for the game",
    handler: fn(_) {
      let moves = [Rock, Paper, Scissors]
      Ok(
        list.shuffle(moves) |> list.first |> result.unwrap(Rock) |> dynamic.from,
      )
    },
  )
}

// Game state tracking
pub type GameState {
  GameState(
    players: List(Agent(Option(Move))),
    moves: Dict(AgentId, Move),
    rounds_played: Int,
    max_rounds: Int,
    scores: Dict(AgentId, Int),
    result: Option(GameResult),
  )
}

// Game logic implementation
pub fn determine_winner(move1: Move, move2: Move) -> GameResult {
  case move1, move2 {
    Rock, Scissors -> Win("player1")
    Scissors, Paper -> Win("player1")
    Paper, Rock -> Win("player1")
    Scissors, Rock -> Win("player2")
    Paper, Scissors -> Win("player2")
    Rock, Paper -> Win("player2")
    _, _ -> Draw
  }
}

// Judge agent implementation
pub fn create_judge_agent(initial_state: GameState) {
  let tools = [create_move_selection_tool()]
  smith.start_default_agent(
    id: "judge_agent",
    tools: tools,
    initial_state: initial_state,
  )
}

// Player agent implementation
pub fn create_player_agent(
  name: AgentId,
) -> Result(Agent(Option(Move)), AgentError) {
  let tools = [create_move_selection_tool()]

  smith.start_agent(
    smith.init_agent(id: name, tools: tools, initial_state: None)
    |> smith.with_recovery_strategy(types.RetryWithBackoff(
      max_retries: 3,
      base_delay: 1000,
    )),
  )
}

// Game orchestration
pub fn start_rock_paper_scissors_game() -> Result(Agent(GameState), AgentError) {
  // Create agents
  let judge_agent = {
    use player1_agent <- result.try(create_player_agent("player1"))
    use player2_agent <- result.try(create_player_agent("player2"))
    let initial_game_state =
      GameState(
        players: [player1_agent, player2_agent],
        moves: dict.new(),
        rounds_played: 0,
        max_rounds: 3,
        scores: dict.from_list([#("player1", 0), #("player2", 0)]),
        result: None,
      )
    use judge_agent <- result.try(create_judge_agent(initial_game_state))

    Ok(judge_agent)
  }

  // Initialize game state
  // Create game task
  let game_task =
    task.create_task(
      name: "Rock Paper Scissors Game",
      description: "Full game session",
      priority: types.High,
      sender: "game_coordinator",
      target: "judge_agent",
      context: dynamic.from(Nil),
      required_tools: ["move_selector"],
    )

  case judge_agent {
    Ok(judge) -> {
      // Start game through judge agent
      smith.send_task_to_agent(judge, game_task)
      Ok(judge)
    }
    Error(e) -> Error(e)
  }
}

// Game round execution
pub fn execute_game_round(
  game_state: GameState,
) -> Result(GameState, AgentError) {
  // Select moves for both players
  game_state.players
  |> list.each(smith.run_tool_on_agent(_, "move_selector", dynamic.from(Nil)))

  // TODO: gather moves from agents
  let player1_move = Rock
  let player2_move = Rock
  // Determine round winner
  let round_result = determine_winner(player1_move, player2_move)

  let updated_state = case round_result {
    Win(winner) -> {
      let current_score =
        dict.get(game_state.scores, winner)
        |> result.unwrap(0)

      GameState(
        ..game_state,
        moves: dict.insert(game_state.moves, "player1", player1_move)
          |> dict.insert("player2", player2_move),
        rounds_played: game_state.rounds_played + 1,
        scores: dict.insert(game_state.scores, winner, current_score + 1),
      )
    }
    Draw -> {
      GameState(
        ..game_state,
        moves: dict.insert(game_state.moves, "player1", player1_move)
          |> dict.insert("player2", player2_move),
        rounds_played: game_state.rounds_played + 1,
      )
    }
  }

  // Check if game is complete
  case updated_state.rounds_played >= updated_state.max_rounds {
    True -> {
      let final_winner = determine_game_winner(updated_state.scores)
      notify_game_result(final_winner, updated_state)
      Ok(updated_state)
    }
    False -> Ok(updated_state)
  }
}

// Determine overall game winner
fn determine_game_winner(scores: Dict(AgentId, Int)) -> Option(AgentId) {
  let sorted_scores =
    dict.to_list(scores)
    |> list.sort(fn(a, b) { int.compare(b.1, a.1) })

  case sorted_scores {
    [#(winner, score1), #(_, score2)] if score1 > score2 -> Some(winner)
    _ -> None
  }
}

// Notify game result
fn notify_game_result(winner: Option(AgentId), game_state: GameState) -> Nil {
  let result_message = case winner {
    Some(w) ->
      string.concat([
        "Game winner: ",
        w,
        " with score: ",
        int.to_string(dict.get(game_state.scores, w) |> result.unwrap(0)),
      ])
    None -> "Game ended in a draw"
  }

  // In a real implementation, this would send a message to all agents
  io.println(result_message)
}
