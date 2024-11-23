import gleam/dict
import gleam/dynamic
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleeunit
import gleeunit/should

import actor.{
  type Message, type Node, AddEdge, AddNode, Edge, Graph, Message, Node,
  NodeFailed, NodeResult, ProcessMessage, RemoveEdge, RemoveNode, Stop,
  UpdateTopology,
} as agent

pub fn main() {
  gleeunit.main()
}

// Test helpers
fn create_test_message(id: String, payload: dynamic.Dynamic) -> Message {
  Message(id: id, payload: payload, metadata: dict.new())
}

fn create_echo_node(id: String) -> Node {
  let behavior = fn(msg: Message, state: dynamic.Dynamic) {
    NodeResult(new_state: state, messages: [msg], graph_updates: None)
  }

  Node(id: id, state: dynamic.from(True), behavior: behavior)
}

fn create_stateful_counter_node(id: String) -> Node {
  let behavior = fn(msg: Message, state: dynamic.Dynamic) {
    let current_count = case dynamic.int(state) {
      Ok(count) -> count
      Error(_) -> 0
    }

    NodeResult(
      new_state: dynamic.from(current_count + 1),
      messages: [msg],
      graph_updates: None,
    )
  }

  Node(id: id, state: dynamic.from(0), behavior: behavior)
}

fn create_graph_updating_node(id: String) -> Node {
  let behavior = fn(_msg: Message, state: dynamic.Dynamic) {
    let update = AddNode(create_echo_node("dynamic_node"))

    NodeResult(new_state: state, messages: [], graph_updates: Some(update))
  }

  Node(id: id, state: dynamic.from(True), behavior: behavior)
}

// Basic Node Tests
pub fn node_creation_test() {
  let node = create_echo_node("test")

  node.id
  |> should.equal("test")

  dynamic.from(True)
  |> should.equal(node.state)
}

pub fn echo_node_behavior_test() {
  let node = create_echo_node("echo")
  let msg = create_test_message("test_msg", dynamic.from("hello"))
  let NodeResult(new_state, messages, updates) = node.behavior(msg, node.state)

  dynamic.from(True)
  |> should.equal(new_state)

  list.length(messages)
  |> should.equal(1)

  updates
  |> should.equal(None)
}

pub fn stateful_counter_node_test() {
  let node = create_stateful_counter_node("counter")
  let msg = create_test_message("test_msg", dynamic.from("increment"))

  let NodeResult(state1, _, _) = node.behavior(msg, node.state)
  let NodeResult(state2, _, _) = node.behavior(msg, state1)

  dynamic.int(state2)
  |> should.be_ok()
  |> should.equal(2)
}

// Edge Tests
pub fn edge_creation_test() {
  let edge = Edge(from: "node1", to: "node2", condition: None)

  edge.from
  |> should.equal("node1")

  edge.to
  |> should.equal("node2")
}

pub fn conditional_edge_test() {
  let condition = fn(msg: Message) -> Bool {
    case dynamic.string(msg.payload) {
      Ok("allow") -> True
      _ -> False
    }
  }

  let edge = Edge(from: "node1", to: "node2", condition: Some(condition))

  let allow_msg = create_test_message("test", dynamic.from("allow"))
  let deny_msg = create_test_message("test", dynamic.from("deny"))

  case edge.condition {
    Some(cond) -> {
      cond(allow_msg) |> should.be_true()
      cond(deny_msg) |> should.be_false()
    }
    None -> should.fail()
  }
}

// Graph Tests
pub fn graph_creation_test() {
  let node1 = create_echo_node("node1")
  let node2 = create_echo_node("node2")
  let edge = Edge(from: "node1", to: "node2", condition: None)

  let nodes = dict.from_list([#("node1", node1), #("node2", node2)])

  let graph = Graph(nodes: nodes, edges: [edge])

  dict.size(graph.nodes)
  |> should.equal(2)

  list.length(graph.edges)
  |> should.equal(1)
}

// Graph Update Tests
pub fn add_node_test() {
  let initial_graph = Graph(nodes: dict.new(), edges: [])
  let node = create_echo_node("test")
  let update = AddNode(node)

  let new_graph = agent.apply_graph_update(initial_graph, update)

  dict.size(new_graph.nodes)
  |> should.equal(1)

  dict.get(new_graph.nodes, "test")
  |> should.be_ok()
}

pub fn remove_node_test() {
  let node = create_echo_node("test")
  let nodes = dict.from_list([#("test", node)])
  let initial_graph = Graph(nodes: nodes, edges: [])
  let update = RemoveNode("test")

  let new_graph = agent.apply_graph_update(initial_graph, update)

  dict.size(new_graph.nodes)
  |> should.equal(0)
}

pub fn add_edge_test() {
  let initial_graph = Graph(nodes: dict.new(), edges: [])
  let edge = Edge(from: "node1", to: "node2", condition: None)
  let update = AddEdge(edge)

  let new_graph = agent.apply_graph_update(initial_graph, update)

  list.length(new_graph.edges)
  |> should.equal(1)
}

pub fn remove_edge_test() {
  let edge = Edge(from: "node1", to: "node2", condition: None)
  let initial_graph = Graph(nodes: dict.new(), edges: [edge])
  let update = RemoveEdge(edge)

  let new_graph = agent.apply_graph_update(initial_graph, update)

  list.length(new_graph.edges)
  |> should.equal(0)
}

// Actor Tests
pub fn agent_startup_test() {
  let node = create_echo_node("test")
  let pid = agent.start_agent(node)

  actor.to_erlang_start_result(pid)
  |> should.be_ok()
  |> process.is_alive()
  |> should.be_true()
}

pub fn agent_message_processing_test() {
  let node = create_stateful_counter_node("counter")
  let assert Ok(pid) = agent.start_agent(node)
  let msg = create_test_message("test", dynamic.from("increment"))

  actor.send(pid, ProcessMessage(msg))
  actor.send(pid, ProcessMessage(msg))

  // Allow time for processing
  process.sleep(100)
  // TODO: How to test it?
  // should.pass()
}

// Supervisor Tests
pub fn supervisor_startup_test() {
  let initial_graph = Graph(nodes: dict.new(), edges: [])
  let pid = agent.start_supervisor(initial_graph)

  actor.to_erlang_start_result(pid)
  |> should.be_ok()
  |> process.is_alive()
  |> should.be_true()
}

pub fn supervisor_node_restart_test() {
  let node = create_echo_node("test")
  let nodes = dict.from_list([#("test", node)])
  let initial_graph = Graph(nodes: nodes, edges: [])
  let assert Ok(pid) = agent.start_supervisor(initial_graph)

  actor.send(pid, NodeFailed("test"))

  // Allow time for restart
  process.sleep(100)
  // TODO: How to test it?
  // should.pass()
}

// Integration Tests
pub fn message_flow_test() {
  let node1 = create_echo_node("node1")
  let node2 = create_stateful_counter_node("node2")
  let edge = Edge(from: "node1", to: "node2", condition: None)

  let nodes = dict.from_list([#("node1", node1), #("node2", node2)])

  let graph = Graph(nodes: nodes, edges: [edge])
  let _supervisor_pid = agent.start_supervisor(graph)

  let msg = create_test_message("test", dynamic.from("hello"))
  let assert Ok(node1_pid) = agent.start_agent(node1)

  actor.send(node1_pid, ProcessMessage(msg))

  // Allow time for message propagation
  process.sleep(100)
  //TODO: How to test it?
  // should.pass()
}

pub fn dynamic_topology_test() {
  let updating_node = create_graph_updating_node("updater")
  let initial_graph =
    Graph(nodes: dict.from_list([#("updater", updating_node)]), edges: [])

  let assert Ok(supervisor_pid) = agent.start_supervisor(initial_graph)
  let _msg = create_test_message("test", dynamic.from("add_node"))

  actor.send(
    supervisor_pid,
    UpdateTopology(AddNode(create_echo_node("dynamic_node"))),
  )

  // Allow time for topology update
  process.sleep(100)
  // TODO: How to test it?
  // should.pass()
}

// Error Handling Tests
pub fn invalid_message_test() {
  let node = create_stateful_counter_node("counter")
  let invalid_msg =
    Message(
      id: "test",
      payload: dynamic.from(True),
      // Counter expects int
      metadata: dict.new(),
    )

  let NodeResult(new_state, _messages, _updates) =
    node.behavior(invalid_msg, node.state)

  // Should handle gracefully and maintain state
  dynamic.int(new_state)
  |> should.be_ok()
  |> should.equal(1)
}

pub fn node_cleanup_test() {
  let node = create_echo_node("test")
  let assert Ok(pid) = agent.start_agent(node)

  actor.send(pid, Stop)

  // Allow time for shutdown
  process.sleep(100)

  actor.to_erlang_start_result(Ok(pid))
  |> should.be_ok()
  |> process.is_alive()
  |> should.be_false()
}
