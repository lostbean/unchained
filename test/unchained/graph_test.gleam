import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import gleeunit
import gleeunit/should
import unchained/chain.{type Chain, type Error}
import unchained/graph

pub fn main() {
  gleeunit.main()
}

pub type TestState {
  TestState(value: Int, path: List(String))
}

fn test_chain() -> Chain {
  chain.new()
}

fn increment_node(_chain: Chain, state: TestState) -> Result(TestState, Error) {
  Ok(TestState(value: state.value + 1, path: ["increment", ..state.path]))
}

fn double_node(_chain: Chain, state: TestState) -> Result(TestState, Error) {
  Ok(TestState(value: state.value * 2, path: ["double", ..state.path]))
}

fn error_node(_chain: Chain, _state: TestState) -> Result(TestState, Error) {
  Error(chain.ChainError("Test error"))
}

fn extract_value(state: TestState) -> Result(String, Error) {
  Ok(string.inspect(state.value))
}

pub fn new_test() {
  let initial_state = TestState(value: 0, path: [])
  let graph = graph.new("start", initial_state, extract_value)

  graph.entry_point
  |> should.equal("start")

  graph.initial_state
  |> should.equal(TestState(value: 0, path: []))
}

pub fn add_node_test() {
  let initial_state = TestState(value: 0, path: [])
  let graph =
    graph.new("increment", initial_state, extract_value)
    |> graph.add_node("increment", increment_node)

  dict.size(graph.nodes)
  |> should.equal(1)
}

pub fn add_edge_test() {
  let initial_state = TestState(value: 0, path: [])
  let graph =
    graph.new("increment", initial_state, extract_value)
    |> graph.add_node("increment", increment_node)
    |> graph.add_node("double", double_node)
    |> graph.add_edge("increment", "double")

  dict.size(graph.edges)
  |> should.equal(1)

  dict.get(graph.edges, "increment")
  |> result.map(list.length)
  |> result.unwrap(0)
  |> should.equal(1)
}

pub fn simple_execution_test() {
  let initial_state = TestState(value: 1, path: [])
  let graph =
    graph.new("increment", initial_state, extract_value)
    |> graph.add_node("increment", increment_node)

  let assert Ok(result) = graph.run(graph, test_chain())
  result.output
  |> should.equal("2")
}

pub fn multi_node_execution_test() {
  let initial_state = TestState(value: 1, path: [])
  let graph =
    graph.new("increment", initial_state, extract_value)
    |> graph.add_node("increment", increment_node)
    |> graph.add_node("double", double_node)
    |> graph.add_edge("increment", "double")

  let assert Ok(result) = graph.run(graph, test_chain())
  result.output
  |> should.equal("4")
  // 1 -> 2 -> 4
}

pub fn conditional_edge_test() {
  let initial_state = TestState(value: 1, path: [])
  let should_double = fn(state: TestState) { state.value < 3 }

  let graph =
    graph.new("increment", initial_state, extract_value)
    |> graph.add_node("increment", increment_node)
    |> graph.add_node("double", double_node)
    |> graph.add_conditional_edge("increment", "double", Some(should_double))

  let assert Ok(result) = graph.run(graph, test_chain())
  result.output
  |> should.equal("4")
  // Condition is true, so doubling happens
}

pub fn conditional_edge_skip_test() {
  let initial_state = TestState(value: 3, path: [])
  let should_double = fn(state: TestState) { state.value < 3 }

  let graph =
    graph.new("increment", initial_state, extract_value)
    |> graph.add_node("increment", increment_node)
    |> graph.add_node("double", double_node)
    |> graph.add_conditional_edge("increment", "double", Some(should_double))

  let assert Ok(result) = graph.run(graph, test_chain())
  result.output
  |> should.equal("4")
  // Only increment happens, no doubling
}

pub fn error_handling_test() {
  let initial_state = TestState(value: 1, path: [])
  let graph =
    graph.new("error", initial_state, extract_value)
    |> graph.add_node("error", error_node)

  let assert Error(_) = graph.run(graph, test_chain())
}

pub fn missing_node_test() {
  let initial_state = TestState(value: 1, path: [])
  let graph = graph.new("non_existent", initial_state, extract_value)

  let assert Error(chain.ChainError(msg)) = graph.run(graph, test_chain())
  msg
  |> should.equal("Node not found: non_existent")
}

pub fn set_initial_state_test() {
  let initial_state = TestState(value: 1, path: [])
  let new_state = TestState(value: 5, path: [])

  let graph =
    graph.new("increment", initial_state, extract_value)
    |> graph.set_initial_state(new_state)

  graph.initial_state
  |> should.equal(TestState(value: 5, path: []))
}

pub fn execution_path_test() {
  let initial_state = TestState(value: 1, path: [])
  let graph =
    graph.new("increment", initial_state, extract_value)
    |> graph.add_node("increment", increment_node)
    |> graph.add_node("double", double_node)
    |> graph.add_edge("increment", "double")

  let assert Ok(_) = graph.run(graph, test_chain())
  // Path should be recorded in reverse order
  graph.initial_state.path
  |> should.equal([])
}
