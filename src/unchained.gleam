import birl.{type Time}
import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import gleam/string_builder
import handles
import handles/ctx
import handles/error.{type TokenizerError}

pub type Chain {
  Chain(steps: List(ChainStep), memory: Memory)
}

pub type ChainEval {
  ChainEval(output: String, memory: Memory)
}

pub type TooSelector {
  ToolSelector(selector: fn(String) -> Option(String), tool: Tool)
}

pub type ChainStep {
  LLMStep(llm_config: LLMConfig)
  LLMStepWithToolSelection(
    llm_config: LLMConfig,
    tools: List(TooSelector),
    template: handles.Template,
  )
  ToolStep(tool: Tool)
  PromptTemplate(template: handles.Template)
  ChainBreaker(should_stop: fn(String) -> Option(String))
}

pub type Memory {
  Memory(variables: Dict(String, String), history: List(HistoryEntry))
}

pub type HistoryEntry {
  LLMCall(input: String, output: String, timestamp: Time)
  ToolExecution(input: String, output: String, tool: Tool, timestamp: Time)
  ChainBreak(input: String, output: String, timestamp: Time)
}

pub type Tool {
  Tool(
    name: String,
    description: String,
    function: fn(String) -> Result(String, Error),
  )
}

pub type Error {
  ChainError(String)
  LLMError(String)
  HTTPError(String)
}

pub type LLMConfig {
  LLMConfig(host: String, model: String, temperature: Float)
}

pub type LLMResponse {
  Response(response: String)
}

// Create a new chain
pub fn new() -> Chain {
  Chain(steps: [], memory: Memory(variables: dict.new(), history: []))
}

// Add an LLM step to the chain
pub fn add_llm(chain: Chain, llm_config: LLMConfig) -> Chain {
  Chain(..chain, steps: list.append(chain.steps, [LLMStep(llm_config)]))
}

// Add a tool step to the chain
pub fn add_tool(chain: Chain, tool: Tool) -> Chain {
  Chain(..chain, steps: list.append(chain.steps, [ToolStep(tool)]))
}

pub fn add_llm_with_tool_selection(
  chain: Chain,
  llm_config: LLMConfig,
  template_str: String,
  tool_selectors: List(TooSelector),
) -> Result(Chain, TokenizerError) {
  handles.prepare(template_str)
  |> result.map(fn(template) {
    Chain(
      ..chain,
      steps: list.append(chain.steps, [
        LLMStepWithToolSelection(llm_config, tool_selectors, template),
      ]),
    )
  })
}

// Add a prompt template step
pub fn add_prompt_template(
  chain: Chain,
  template_str: String,
) -> Result(Chain, TokenizerError) {
  handles.prepare(template_str)
  |> result.map(fn(template) {
    Chain(..chain, steps: list.append(chain.steps, [PromptTemplate(template)]))
  })
}

// Set a variable in memory
pub fn set_variable(chain: Chain, key: String, value: String) -> Chain {
  Chain(
    ..chain,
    memory: Memory(
      ..chain.memory,
      variables: dict.insert(chain.memory.variables, key, value),
    ),
  )
}

pub fn get_eval_output(eval: ChainEval) -> String {
  eval.output
}

pub fn get_eval_memory(eval: ChainEval) -> Memory {
  eval.memory
}

// Execute the chain
pub fn run(chain: Chain) -> Result(ChainEval, Error) {
  execute_steps(chain.steps, "", chain.memory, call_ollama)
}

pub fn run_with(
  chain: Chain,
  llm_engine: fn(String, LLMConfig) -> Result(LLMResponse, Error),
) -> Result(ChainEval, Error) {
  execute_steps(chain.steps, "", chain.memory, llm_engine)
}

fn interpolate_template(
  template: handles.Template,
  values: dict.Dict(String, String),
  tools: List(TooSelector),
) -> String {
  let ctxs =
    dict.to_list(values)
    |> list.map(fn(entry) {
      let #(k, v) = entry
      ctx.Prop(k, ctx.Str(v))
    })
  let tool_descriptions =
    ctx.Prop(
      "tools",
      tools
        |> list.map(fn(t) {
          [
            ctx.Prop("name", ctx.Str(t.tool.name)),
            ctx.Prop("description", ctx.Str(t.tool.description)),
          ]
          |> ctx.Dict()
        })
        |> ctx.List(),
    )
  let assert Ok(string) =
    handles.run(template, ctx.Dict([tool_descriptions, ..ctxs]), [])

  string
  |> string_builder.to_string
}

// Call Ollama API
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

fn update_memory_history(
  memory: Memory,
  input: String,
  output: String,
) -> Memory {
  Memory(
    variables: memory.variables,
    history: list.append(memory.history, [LLMCall(input, output, birl.now())]),
  )
}

fn update_memory_history_tool(
  memory: Memory,
  input: String,
  output: String,
  tool: Tool,
) -> Memory {
  Memory(
    variables: memory.variables,
    history: list.append(memory.history, [
      ToolExecution(input, output, tool, birl.now()),
    ]),
  )
}

// Internal function to execute chain steps
fn execute_steps(
  steps: List(ChainStep),
  input: String,
  memory: Memory,
  llm_engine: fn(String, LLMConfig) -> Result(LLMResponse, Error),
) -> Result(ChainEval, Error) {
  case steps {
    [] -> Ok(ChainEval(input, memory))

    [LLMStep(llm_config), ..rest] -> {
      // Call Ollama with the prompt and input
      case llm_engine(input, llm_config) {
        Ok(Response(output)) -> {
          let new_memory = update_memory_history(memory, input, output)
          execute_steps(rest, output, new_memory, llm_engine)
        }
        Error(e) -> Error(e)
      }
    }

    [LLMStepWithToolSelection(llm_config, tool_selectors, template), ..rest] -> {
      // Call Ollama with the prompt and input
      let tool_prompt =
        interpolate_template(template, memory.variables, tool_selectors)
      case llm_engine(input <> "\n" <> tool_prompt, llm_config) {
        Ok(Response(output)) -> {
          let new_memory = update_memory_history(memory, input, output)
          let foun_tool =
            list.find_map(tool_selectors, fn(tool_selector) {
              let ToolSelector(selector, tool) = tool_selector
              selector(output)
              |> option.map(fn(tool_input) { #(tool_input, tool) })
              |> option.to_result(Nil)
            })
          let fun_output = case foun_tool {
            Ok(#(tool_input, tool)) -> {
              tool.function(tool_input)
            }
            Error(Nil) -> Ok(output)
          }
          case fun_output {
            Ok(output) -> {
              let new_memory = case foun_tool {
                Ok(#(_, tool)) ->
                  update_memory_history_tool(new_memory, input, output, tool)
                Error(Nil) -> new_memory
              }
              execute_steps(rest, output, new_memory, llm_engine)
            }
            Error(e) -> Error(e)
          }
        }
        Error(e) -> Error(e)
      }
    }

    [ToolStep(tool), ..rest] -> {
      case tool.function(input) {
        Ok(output) -> {
          let new_memory =
            update_memory_history_tool(memory, input, output, tool)
          execute_steps(rest, output, new_memory, llm_engine)
        }
        Error(e) -> Error(e)
      }
    }

    [PromptTemplate(template), ..rest] -> {
      let output = interpolate_template(template, memory.variables, [])
      execute_steps(rest, output, memory, llm_engine)
    }

    [ChainBreaker(should_break), ..rest] ->
      case should_break(input) {
        option.Some(output) -> {
          let new_memory =
            Memory(
              variables: memory.variables,
              history: list.append(memory.history, [
                ChainBreak(input, output, birl.now()),
              ]),
            )
          execute_steps([], output, new_memory, llm_engine)
        }
        _ -> execute_steps(rest, input, memory, llm_engine)
      }
  }
}
