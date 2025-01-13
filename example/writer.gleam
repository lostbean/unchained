import gleam/option.{Some}
import gleeunit
import graph
import unchained

pub fn main() {
  gleeunit.main()
}

// Define your state type
pub type EssayState {
  EssayState(
    topic: String,
    latest_revision: String,
    latest_feedback: String,
    num_of_revisions: Int,
  )
}

pub fn graph_test() {
  // Create nodes
  let write_first_draft = fn(chain, state) {
    // Your implementation here
    Ok(state)
  }

  let write_revision = fn(chain, state) {
    // Your implementation here
    Ok(state)
  }

  let provide_feedback = fn(chain, state) {
    // Your implementation here
    Ok(state)
  }

  // Create a function to extract the final output
  let get_final_output = fn(state: EssayState) -> Result(
    String,
    unchained.Error,
  ) {
    Ok(state.latest_revision)
  }
  // Create and configure the graph
  let essay_graph =
    graph.new(
      "first_draft",
      EssayState(
        topic: "AI",
        latest_revision: "",
        latest_feedback: "",
        num_of_revisions: 0,
      ),
      get_final_output,
    )
    |> graph.add_node("first_draft", write_first_draft)
    |> graph.add_node("write", write_revision)
    |> graph.add_node("provide_feedback", provide_feedback)
    |> graph.add_edge("first_draft", "provide_feedback")
    |> graph.add_edge("provide_feedback", "write")
    |> graph.add_conditional_edge(
      "write",
      "provide_feedback",
      Some(fn(state: EssayState) { state.num_of_revisions <= 2 }),
    )

  // Run the graph
  let chain = unchained.new()
  graph.run(essay_graph, chain)
}
