import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import unchained.{type Chain, type ChainEval, type Error, ChainEval}

pub type Graph(state) {
  Graph(
    nodes: Dict(String, Node(state)),
    edges: Dict(String, List(Edge(state))),
    entry_point: String,
    final_output_fn: fn(state) -> Result(String, Error),
    initial_state: state,
  )
}

pub type Node(state) {
  Node(executor: fn(Chain, state) -> Result(state, Error))
}

pub type Edge(state) {
  Edge(from: String, to: String, condition: Option(fn(state) -> Bool))
}

// Create a new graph
pub fn new(
  entry_point: String,
  initial_state: state,
  final_output_fn: fn(state) -> Result(String, Error),
) -> Graph(state) {
  Graph(
    nodes: dict.new(),
    edges: dict.new(),
    entry_point: entry_point,
    final_output_fn: final_output_fn,
    initial_state: initial_state,
  )
}

// Add a node to the graph
pub fn add_node(
  graph: Graph(state),
  name: String,
  executor: fn(Chain, state) -> Result(state, Error),
) -> Graph(state) {
  Graph(..graph, nodes: dict.insert(graph.nodes, name, Node(executor)))
}

// Add an edge between nodes
pub fn add_edge(graph: Graph(state), from: String, to: String) -> Graph(state) {
  add_conditional_edge(graph, from, to, None)
}

// Add a conditional edge between nodes
pub fn add_conditional_edge(
  graph: Graph(state),
  from: String,
  to: String,
  condition: Option(fn(state) -> Bool),
) -> Graph(state) {
  let current_edges = dict.get(graph.edges, from) |> result.unwrap([])
  let new_edges = [Edge(from, to, condition), ..current_edges]
  Graph(..graph, edges: dict.insert(graph.edges, from, new_edges))
}

// Set initial state
pub fn set_initial_state(graph: Graph(state), new_state: state) -> Graph(state) {
  Graph(..graph, initial_state: new_state)
}

// Execute the graph
pub fn run(graph: Graph(state), chain: Chain) -> Result(ChainEval, Error) {
  execute_node(graph, chain, graph.entry_point, graph.initial_state)
}

fn execute_node(
  graph: Graph(state),
  chain: Chain,
  current_node: String,
  state: state,
) -> Result(ChainEval, Error) {
  case dict.get(graph.nodes, current_node) {
    Ok(Node(executor)) -> {
      case executor(chain, state) {
        Ok(new_state) -> {
          // Find next node based on edges and conditions
          case find_next_node(graph, current_node, new_state) {
            Some(next_node) -> execute_node(graph, chain, next_node, new_state)
            None -> {
              // End of execution, return final state
              case graph.final_output_fn(new_state) {
                Ok(output) ->
                  Ok(ChainEval(output: output, memory: chain.memory))
                Error(e) -> Error(e)
              }
            }
          }
        }
        Error(e) -> Error(e)
      }
    }
    Error(_) -> Error(unchained.ChainError("Node not found: " <> current_node))
  }
}

fn find_next_node(
  graph: Graph(state),
  current_node: String,
  state: state,
) -> Option(String) {
  case dict.get(graph.edges, current_node) {
    Ok(edges) ->
      list.find_map(edges, fn(edge) {
        case edge.condition {
          Some(condition) ->
            case condition(state) {
              True -> Ok(edge.to)
              False -> Error(Nil)
            }
          None -> Ok(edge.to)
        }
      })
      |> option.from_result
    Error(_) -> None
  }
}
