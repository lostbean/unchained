import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

// Core types for the framework
pub type NodeId =
  String

pub type Edge {
  Edge(from: NodeId, to: NodeId, condition: Option(fn(Message) -> Bool))
}

pub type Message {
  Message(
    id: String,
    payload: dynamic.Dynamic,
    metadata: Dict(String, dynamic.Dynamic),
  )
}

pub type Node {
  Node(
    id: NodeId,
    state: dynamic.Dynamic,
    behavior: fn(Message, dynamic.Dynamic) -> NodeResult,
  )
}

pub type NodeResult {
  NodeResult(
    new_state: dynamic.Dynamic,
    messages: List(Message),
    graph_updates: Option(GraphUpdate),
  )
}

pub type GraphUpdate {
  AddNode(node: Node)
  RemoveNode(id: NodeId)
  AddEdge(edge: Edge)
  RemoveEdge(edge: Edge)
}

pub type Graph {
  Graph(nodes: Dict(NodeId, Node), edges: List(Edge))
}

// Actor implementation for graph nodes
pub type AgentMsg {
  ProcessMessage(Message)
  UpdateState(dynamic.Dynamic)
  Stop
}

pub fn start_agent(node: Node) {
  let init_state = #(node.id, node.state, node.behavior)

  actor.start(init_state, handle_message)
}

fn handle_message(
  msg: AgentMsg,
  state: #(NodeId, dynamic.Dynamic, fn(Message, dynamic.Dynamic) -> NodeResult),
) {
  case msg {
    ProcessMessage(message) -> {
      let #(id, current_state, behavior) = state
      let NodeResult(new_state, messages, updates) =
        behavior(message, current_state)

      // Handle graph updates if any
      case updates {
        Some(update) -> broadcast_graph_update(update)
        None -> Nil
      }

      // Forward messages to next nodes
      list.map(messages, forward_message)

      actor.continue(#(id, new_state, behavior))
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
pub type SupervisorMsg {
  NodeFailed(NodeId)
  RestartNode(NodeId)
  UpdateTopology(GraphUpdate)
}

pub fn start_supervisor(initial_graph: Graph) {
  let init_state = #(initial_graph, dict.new())

  actor.start(init_state, handle_supervisor_message)
}

fn handle_supervisor_message(
  msg: SupervisorMsg,
  state: #(Graph, Dict(NodeId, process.Subject(AgentMsg))),
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
pub fn apply_graph_update(graph: Graph, update: GraphUpdate) -> Graph {
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

fn broadcast_graph_update(_update: GraphUpdate) {
  // Implementation to broadcast topology updates to supervisor
  Nil
}

fn forward_message(_message: Message) {
  // Implementation to route message to next node(s)
  Nil
}
