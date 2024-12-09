import gleam/dynamic
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/string

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

pub fn call_ollama(
  prompt: String,
  config: LLMConfig,
) -> Result(LLMResponse, Error) {
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
