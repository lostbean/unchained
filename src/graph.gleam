import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

// Core types for the framework
pub type NodeId =
  String

pub type Edge(input) {
  Edge(from: NodeId, to: NodeId, condition: Option(fn(Message(input)) -> Bool))
}

pub type Message(input) {
  Message(id: String, payload: input, metadata: Dict(String, dynamic.Dynamic))
}

pub type Node(state, input, output) {
  Node(
    id: NodeId,
    state: state,
    behavior: fn(Message(input), state) -> NodeResult(state, input, output),
  )
}

pub type NodeResult(state, input, output) {
  NodeResult(
    new_state: state,
    messages: List(Message(input)),
    graph_updates: Option(GraphUpdate(state, input, output)),
  )
  Halt
  // Stateless(output: output)
}

pub type GraphUpdate(state, input, output) {
  AddNode(node: Node(state, input, output))
  RemoveNode(id: NodeId)
  AddEdge(edge: Edge(input))
  RemoveEdge(edge: Edge(input))
}

pub type Graph(state, input, output) {
  Graph(
    nodes: Dict(NodeId, Node(state, input, output)),
    edges: List(Edge(input)),
  )
}

// Actor implementation for graph nodes
pub type AgentMsg(state, input) {
  ProcessMessage(Message(input))
  UpdateState(state)
  Stop
}

pub fn start_agent(node: Node(state, input, output)) {
  let init_state = #(node.id, node.state, node.behavior)

  actor.start(init_state, handle_message)
}

fn handle_message(
  msg: AgentMsg(state, input),
  state: #(
    NodeId,
    state,
    fn(Message(input), state) -> NodeResult(state, input, output),
  ),
) {
  case msg {
    ProcessMessage(message) -> {
      let #(id, current_state, behavior) = state
      case behavior(message, current_state) {
        NodeResult(new_state, messages, updates) -> {
          // Handle graph updates if any
          case updates {
            Some(update) -> broadcast_graph_update(update)
            None -> Nil
          }

          // Forward messages to next nodes
          list.map(messages, forward_message)

          actor.continue(#(id, new_state, behavior))
        }
        Halt -> actor.Stop(process.Normal)
      }
    }

    UpdateState(new_state) -> {
      let #(id, _, behavior) = state
      actor.continue(#(id, new_state, behavior))
    }

    Stop -> {
      actor.Stop(process.Normal)
    }
  }
}

// Supervisor implementation
pub type SupervisorMsg(state, input, output) {
  NodeFailed(NodeId)
  RestartNode(NodeId)
  UpdateTopology(GraphUpdate(state, input, output))
}

pub fn start_supervisor(initial_graph: Graph(state, input, output)) {
  let init_state = #(initial_graph, dict.new())

  actor.start(init_state, handle_supervisor_message)
}

fn handle_supervisor_message(
  msg: SupervisorMsg(state, input, output),
  state: #(
    Graph(state, input, output),
    Dict(NodeId, process.Subject(AgentMsg(state, input))),
  ),
) {
  case msg {
    NodeFailed(node_id) -> {
      let #(graph, pids) = state

      // Implement restart strategy
      case dict.get(graph.nodes, node_id) {
        Ok(node) -> {
          let assert Ok(new_agent) = start_agent(node)
          let new_agents = dict.insert(pids, node_id, new_agent)
          actor.continue(#(graph, new_agents))
        }
        Error(_) -> actor.continue(state)
      }
    }

    RestartNode(node_id) -> {
      // Similar to NodeFailed but explicit restart
      handle_supervisor_message(NodeFailed(node_id), state)
    }

    UpdateTopology(update) -> {
      let #(graph, pids) = state
      let new_graph = apply_graph_update(graph, update)
      actor.continue(#(new_graph, pids))
    }
  }
}

// Helper functions
pub fn apply_graph_update(
  graph: Graph(state, input, output),
  update: GraphUpdate(state, input, output),
) -> Graph(state, input, output) {
  case update {
    AddNode(node) -> {
      Graph(nodes: dict.insert(graph.nodes, node.id, node), edges: graph.edges)
    }

    RemoveNode(id) -> {
      Graph(
        nodes: dict.delete(graph.nodes, id),
        edges: list.filter(graph.edges, fn(edge) {
          edge.from != id && edge.to != id
        }),
      )
    }

    AddEdge(edge) -> {
      Graph(nodes: graph.nodes, edges: [edge, ..graph.edges])
    }

    RemoveEdge(edge) -> {
      Graph(
        nodes: graph.nodes,
        edges: list.filter(graph.edges, fn(e) { e != edge }),
      )
    }
  }
}

fn broadcast_graph_update(_update: GraphUpdate(state, input, output)) {
  // Implementation to broadcast topology updates to supervisor
  Nil
}

fn forward_message(_message: Message(input)) {
  // Implementation to route message to next node(s)
  Nil
}
