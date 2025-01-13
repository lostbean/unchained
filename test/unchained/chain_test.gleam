import gleam/dict
import gleam/float
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import unchained/chain.{
  type ChainEval, type Error, type LLMConfig, type LLMResponse, type Tool,
  type ToolArg, ChainError, ChainEval, LLMConfig, Memory, Response, Tool,
  ToolArg, ToolSelector, add_llm, add_llm_with_tool_selection,
  add_prompt_template, add_tool, get_eval_memory, get_eval_output, new, run_with,
  set_variable,
}

pub fn main() {
  gleeunit.main()
}

fn mock_llm_engine(
  _prompt: String,
  _config: LLMConfig,
) -> Result(LLMResponse, Error) {
  Ok(Response("mock response"))
}

fn mock_calc_llm_engine(
  _prompt: String,
  _config: LLMConfig,
) -> Result(LLMResponse, Error) {
  Ok(Response("add|4.0|3.0"))
}

fn mock_error_llm_engine(
  _prompt: String,
  _config: LLMConfig,
) -> Result(LLMResponse, Error) {
  Error(chain.LLMError("mock error"))
}

fn create_calculator_tool() -> Tool {
  Tool(
    name: "calculator",
    description: "Performs basic arithmetic operations",
    args: [
      ToolArg(
        "operation",
        "The operation to perform (add, subtract, multiply, divide)",
      ),
      ToolArg("first_number", "The first number"),
      ToolArg("second_number", "The second number"),
    ],
    function: fn(args) {
      case args {
        ["add", a, b] -> {
          case float.parse(a), float.parse(b) {
            Ok(x), Ok(y) -> Ok(float.to_string(x +. y))
            _, _ -> Error(ChainError("Invalid number format"))
          }
        }
        ["multiply", a, b] -> {
          case float.parse(a), float.parse(b) {
            Ok(x), Ok(y) -> Ok(float.to_string(x *. y))
            _, _ -> Error(ChainError("Invalid number format"))
          }
        }
        _ ->
          Error(ChainError(
            "Invalid calculator arguments: " <> string.inspect(args),
          ))
      }
    },
  )
}

fn create_text_tool() -> Tool {
  Tool(
    name: "text_processor",
    description: "Process text with various operations",
    args: [
      ToolArg("operation", "The operation to perform (uppercase, lowercase)"),
      ToolArg("text", "The text to process"),
    ],
    function: fn(args) {
      case args {
        ["uppercase", text] -> Ok(string.uppercase(text))
        ["lowercase", text] -> Ok(string.lowercase(text))
        _ -> Error(ChainError("Invalid text processor arguments"))
      }
    },
  )
}

pub fn set_variable_test() {
  let chain =
    chain.new()
    |> chain.set_variable("key", "value")

  chain.memory.variables
  |> dict.get("key")
  |> should.equal(Ok("value"))
}

pub fn calculator_tool_test() {
  let calc = create_calculator_tool()

  // Test addition
  calc.function(["add", "5.2", "3.8"])
  |> should.equal(Ok("9.0"))

  // Test multiplication
  calc.function(["multiply", "4.0", "3.0"])
  |> should.equal(Ok("12.0"))

  // Test invalid operation
  calc.function(["invalid", "1", "2"])
  |> should.be_error()

  // Test invalid number format
  calc.function(["add", "not_a_number", "3"])
  |> should.be_error()
}

pub fn text_tool_test() {
  let text_tool = create_text_tool()

  // Test uppercase
  text_tool.function(["uppercase", "hello"])
  |> should.equal(Ok("HELLO"))

  // Test lowercase
  text_tool.function(["lowercase", "WORLD"])
  |> should.equal(Ok("world"))

  // Test invalid operation
  text_tool.function(["invalid", "text"])
  |> should.be_error()
}

pub fn chain_with_tool_test() {
  let calc = create_calculator_tool()
  let config =
    LLMConfig(host: "localhost:11434", model: "test", temperature: 0.7)

  let chain =
    chain.new()
    |> chain.add_llm(config)
    |> chain.add_tool(calc)

  let eval =
    chain.run_with(chain, mock_calc_llm_engine)
    |> should.be_ok

  eval.memory.history
  |> list.length()
  |> should.equal(2)
}

pub fn chain_with_llm_test() {
  let config =
    LLMConfig(host: "localhost:11434", model: "test", temperature: 0.7)

  let chain =
    chain.new()
    |> chain.add_llm(config)

  let eval =
    chain.run_with(chain, mock_llm_engine)
    |> should.be_ok

  eval.output
  |> should.equal("mock response")
}

pub fn chain_with_error_test() {
  let config =
    LLMConfig(host: "localhost:11434", model: "test", temperature: 0.7)

  let chain =
    chain.new()
    |> chain.add_llm(config)

  chain.run_with(chain, mock_error_llm_engine)
  |> should.be_error()
}

pub fn chain_with_template_test() {
  let chain =
    chain.new()
    |> chain.set_variable("name", "World")
    |> chain.add_prompt_template("Hello {{name}}!")
    |> should.be_ok

  let eval = chain.run_with(chain, mock_llm_engine) |> should.be_ok

  eval.memory.history
  |> list.length()
  |> should.equal(1)
}

pub fn tool_selection_test() {
  let calc = create_calculator_tool()
  let text_tool = create_text_tool()

  let calc_selector = fn(input) {
    case string.contains(input, "calculate") {
      True -> Some("add|5.0|3.0")
      False -> None
    }
  }

  let text_selector = fn(input) {
    case string.contains(input, "uppercase") {
      True -> Some("uppercase|hello")
      False -> None
    }
  }

  let config =
    LLMConfig(host: "localhost:11434", model: "test", temperature: 0.7)

  let chain =
    chain.new()
    |> chain.add_llm_with_tool_selection(
      config,
      "{{#each tools}}{{name}}-{{description}}{{/each}}",
      [
        chain.ToolSelector(calc_selector, calc),
        chain.ToolSelector(text_selector, text_tool),
      ],
    )
    |> should.be_ok

  chain.run_with(chain, mock_llm_engine) |> should.be_ok
}

pub fn chain_eval_getters_test() {
  let eval =
    ChainEval(
      output: "test output",
      memory: Memory(variables: dict.new(), history: []),
    )

  chain.get_eval_output(eval)
  |> should.equal("test output")

  chain.get_eval_memory(eval)
  |> should.equal(Memory(variables: dict.new(), history: []))
}

fn mock_llm_fix_engine(
  _prompt: String,
  _config: LLMConfig,
) -> Result(LLMResponse, chain.Error) {
  Ok(Response("This is a mock LLM response"))
}

fn mock_id_llm_engine(
  prompt: String,
  _config: LLMConfig,
) -> Result(LLMResponse, chain.Error) {
  Ok(Response(string.replace(prompt, each: " ", with: "-")))
}

fn mock_fix_tool() {
  Tool(
    name: "mockoutput",
    description: "to uppercase",
    args: [],
    function: fn(_) { Ok("This is a mock tool response") },
  )
}

fn mock_upper_tool() {
  chain.Tool(
    name: "format",
    description: "to uppercase",
    args: [],
    function: fn(args) {
      case args {
        [x] -> Ok(string.uppercase(x))
        _ -> Error(chain.LLMError("Wrong number of arguments"))
      }
    },
  )
}

fn get_llm_config() {
  chain.LLMConfig(
    host: "localhost:11434",
    model: "llama3.2:3b",
    temperature: 0.0,
  )
}

pub fn new_chain_test() {
  let chain = new()

  chain.steps
  |> should.equal([])

  chain.memory.variables
  |> dict.size
  |> should.equal(0)

  chain.memory.history
  |> should.equal([])
}

pub fn add_llm_test() {
  let chain =
    new()
    |> add_llm(get_llm_config())

  chain.steps
  |> list.length()
  |> should.equal(1)

  chain
  |> chain.run_with(mock_llm_fix_engine)
  |> should.be_ok()
  |> get_eval_output()
  |> should.equal("This is a mock LLM response")
}

pub fn add_tool_test() {
  let chain =
    new()
    |> add_tool(mock_fix_tool())

  chain.steps
  |> list.length()
  |> should.equal(1)

  chain
  |> chain.run_with(mock_id_llm_engine)
  |> should.be_ok()
  |> get_eval_output()
  |> should.equal("This is a mock tool response")
}

pub fn add_prompt_template_test() {
  let chain =
    new()
    |> add_prompt_template("This is a test template with {{variable}}")
    |> should.be_ok()
    |> add_llm(get_llm_config())
    |> set_variable("variable", "a variable")

  chain.steps
  |> list.length()
  |> should.equal(2)

  chain
  |> chain.run_with(mock_id_llm_engine)
  |> should.be_ok()
  |> get_eval_output()
  |> should.equal("\nThis-is-a-test-template-with-a-variable")
}

pub fn run_with_test() {
  let chain =
    new()
    |> add_prompt_template("This is a test prompt")
    |> should.be_ok()
    |> add_llm(get_llm_config())

  let eval =
    run_with(chain, mock_id_llm_engine)
    |> should.be_ok

  get_eval_output(eval)
  |> should.equal("\nThis-is-a-test-prompt")

  get_eval_memory(eval).history
  |> list.length()
  |> should.equal(2)

  get_eval_memory(eval).history
  |> list.map(fn(x) { x.input })
  |> should.equal(["", "This is a test prompt"])
}

pub fn add_llm_with_tool_selection_test() {
  let tool_selector =
    ToolSelector(
      selector: fn(_) { Some("test input") },
      tool: mock_upper_tool(),
    )

  let chain =
    new()
    |> add_llm_with_tool_selection(
      get_llm_config(),
      "{{#each tools}}{{name}}-{{description}}{{/each}}",
      [tool_selector],
    )
    |> should.be_ok

  chain.steps
  |> list.length()
  |> should.equal(1)
}

pub fn history_test() {
  let chain =
    chain.new()
    |> chain.add_prompt_template("Test 1")
    |> should.be_ok()
    |> chain.add_tool(mock_upper_tool())
    |> chain.add_llm(get_llm_config())

  chain.steps
  |> list.length()
  |> should.equal(3)

  let eval =
    chain
    |> chain.run_with(fn(input, _cfg) {
      input |> should.equal("\nTest 1\nTEST 1")
      Ok(chain.Response("test 2"))
    })
    |> should.be_ok()

  eval
  |> chain.get_eval_memory()
  |> fn(x) { x.history }
  |> list.map(fn(x) { x.input })
  |> should.equal(["", "Test 1", "TEST 1"])

  eval
  |> chain.get_eval_memory()
  |> fn(x) { x.history }
  |> list.map(fn(x) { x.output })
  |> should.equal(["Test 1", "TEST 1", "test 2"])

  eval
  |> chain.get_eval_output()
  |> should.equal("test 2")
}
