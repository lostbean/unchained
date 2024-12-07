import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/option.{None}
import gleam/result
import gleam/string
import graph.{
  type Graph, type Message, type NodeResult, Edge, Graph, Halt, Node, NodeResult,
}

// Domain Types (updated with confidence scores)
pub type Document {
  Document(
    id: String,
    content: String,
    doc_type: String,
    metadata: Dict(String, String),
  )
}

pub type Analysis {
  RawDoc(Document)
  SentimentAnalysis(score: Float, confidence: Float)
  TopicAnalysis(topics: List(#(String, Float)))
}

// Prompts
const sentiment_prompt = "
Analyze the sentiment of the following text. Return a JSON object with:
- score: a number between -1 (very negative) and 1 (very positive)
- confidence: a number between 0 and 1

Text: {content}

Response format:
{\"score\": 0.5, \"confidence\": 0.8}
"

const topics_prompt = "
Identify the main topics in the following text. Return a JSON array of objects with:
- topic: the topic name
- confidence: a confidence score between 0 and 1

List up to 5 topics.

Text: {content}

Response format:
[{\"topic\": \"AI\", \"confidence\": 0.9}, ...]
"

pub type LLMConfig {
  LLMConfig(host: String, model: String, temperature: Float)
}

pub type LLMResponse {
  Response(response: String)
}

pub type Error {
  LLMError(String)
  HTTPError(String)
  InvalidResponse(String)
}

fn call_ollama(prompt: String, config: LLMConfig) -> Result(LLMResponse, Error) {
  let body =
    json.object([
      #("model", json.string(config.model)),
      #("prompt", json.string(prompt)),
      #("temperature", json.float(config.temperature)),
      #("stream", json.bool(False)),
    ])

  let ollama_response_decoder =
    dynamic.decode1(Response, dynamic.field("response", dynamic.string))

  let req =
    request.new()
    // TODO: parse URL
    |> request.set_scheme(http.Http)
    |> request.set_host(config.host)
    |> request.set_method(http.Post)
    |> request.set_path("/api/generate")
    |> request.set_body(json.to_string(body))
    |> request.set_header("content-type", "application/json")

  case httpc.send(req) {
    Ok(resp) -> {
      // Parse Ollama response
      case json.decode(resp.body, ollama_response_decoder) {
        Ok(text) -> Ok(text)
        Error(e) ->
          Error(LLMError(
            "Failed to parse Ollama response: " <> string.inspect(e),
          ))
      }
    }
    Error(e) ->
      Error(HTTPError("Failed to make HTTP request." <> string.inspect(e)))
  }
}

fn create_message(id: String, payload: a) -> Message(a) {
  graph.Message(id: id, payload: payload, metadata: dict.new())
}

// Helper function to create sample documents for testing
pub fn create_sample_document() -> Document {
  Document(
    id: "doc123",
    content: "Sample content for testing",
    doc_type: "test",
    metadata: dict.from_list([
      #("created_at", "2024-11-23"),
      #("source", "test"),
    ]),
  )
}

// Node Behaviors
fn sentiment_analyzer_behavior(
  msg: Message(Analysis),
  state: dynamic.Dynamic,
) -> NodeResult(Dynamic, Analysis, Dynamic) {
  case msg.payload {
    RawDoc(doc) -> {
      let config =
        LLMConfig(
          host: "localhost:11434",
          model: "llama3.2:3b",
          temperature: 0.0,
        )

      let prompt = string.replace(sentiment_prompt, "{content}", doc.content)

      case call_ollama(prompt, config) {
        Ok(response) -> {
          case parse_sentiment_response(response.response) {
            Ok(#(score, confidence)) -> {
              let analysis =
                SentimentAnalysis(score: score, confidence: confidence)

              let result_msg = create_message("sentiment_" <> doc.id, analysis)

              NodeResult(
                new_state: state,
                messages: [result_msg],
                graph_updates: None,
              )
            }
            Error(_) -> todo
          }
        }
        Error(_) -> todo
      }
    }
    _ -> Halt
  }
}

fn topic_analyzer_behavior(
  msg: Message(Analysis),
  state: dynamic.Dynamic,
) -> NodeResult(Dynamic, Analysis, Dynamic) {
  case msg.payload {
    RawDoc(doc) -> {
      let config =
        LLMConfig(
          host: "localhost:11434",
          model: "llama3.2:3b",
          temperature: 0.0,
        )

      let prompt = string.replace(topics_prompt, "{content}", doc.content)

      case call_ollama(prompt, config) {
        Ok(response) -> {
          case parse_topics_response(response.response) {
            Ok(topics) -> {
              let analysis = TopicAnalysis(topics: topics)

              let result_msg = create_message("topics_" <> doc.id, analysis)

              NodeResult(
                new_state: state,
                messages: [result_msg],
                graph_updates: None,
              )
            }
            Error(_) -> todo
          }
        }
        Error(_) -> todo
      }
    }
    _ -> Halt
  }
}

// Response Parsers
fn parse_sentiment_response(text: String) -> Result(#(Float, Float), Error) {
  let dec =
    dynamic.decode2(
      fn(a, b) { #(a, b) },
      dynamic.field("score", dynamic.float),
      dynamic.field("confidence", dynamic.float),
    )
  json.decode(text, dec)
  |> result.map_error(fn(_) { InvalidResponse("Invalid JSON") })
}

fn parse_topics_response(text: String) -> Result(List(#(String, Float)), Error) {
  let dec =
    dynamic.decode2(
      fn(a, b) { #(a, b) },
      dynamic.field("topic", dynamic.string),
      dynamic.field("confidence", dynamic.float),
    )
    |> dynamic.list
  json.decode(text, dec)
  |> result.map_error(fn(_) { InvalidResponse("Invalid JSON") })
}

// Rest of the framework implementation remains the same...

// Graph Setup
pub fn create_processing_pipeline() -> Graph(Dynamic, Analysis, Dynamic) {
  let nodes =
    dict.from_list([
      #(
        "sentiment",
        Node("sentiment", dynamic.from(True), sentiment_analyzer_behavior),
      ),
      #("topics", Node("topics", dynamic.from(True), topic_analyzer_behavior)),
    ])

  let edges = [Edge("sentiment", "topics", None)]

  Graph(nodes: nodes, edges: edges)
}

// HTTP API
pub fn start_server() {
  let pipeline = create_processing_pipeline()
  let _supervisor_pid = graph.start_supervisor(pipeline)
}
