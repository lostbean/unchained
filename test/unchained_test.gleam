import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit
import gleeunit/should
import unchained.{
  type LLMConfig, type LLMResponse, type Tool, LLMConfig, Response, Tool,
  ToolSelector, add_llm, add_llm_with_tool_selection, add_prompt_template,
  add_tool, get_eval_memory, get_eval_output, new, run_with, set_variable,
}

pub fn main() {
  gleeunit.main()
}

fn mock_llm_fix_engine(
  _prompt: String,
  _config: LLMConfig,
) -> Result(LLMResponse, unchained.Error) {
  Ok(Response("This is a mock LLM response"))
}

fn mock_id_llm_engine(
  prompt: String,
  _config: LLMConfig,
) -> Result(LLMResponse, unchained.Error) {
  Ok(Response(string.replace(prompt, each: " ", with: "-")))
}

fn mock_fix_tool() {
  Tool(name: "mockoutput", description: "to uppercase", function: fn(_) {
    Ok("This is a mock tool response")
  })
}

fn mock_upper_tool() {
  unchained.Tool(name: "format", description: "to uppercase", function: fn(x) {
    Ok(string.uppercase(x))
  })
}

fn get_llm_config() {
  unchained.LLMConfig(
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
  |> unchained.run_with(mock_llm_fix_engine)
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
  |> unchained.run_with(mock_id_llm_engine)
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
  |> unchained.run_with(mock_id_llm_engine)
  |> should.be_ok()
  |> get_eval_output()
  |> should.equal("\nThis-is-a-test-template-with-a-variable")
}

pub fn set_variable_test() {
  let chain =
    new()
    |> set_variable("test_key", "test_value")

  chain.memory.variables
  |> dict.get("test_key")
  |> should.equal(Ok("test_value"))
}

pub fn run_with_test() {
  let chain =
    new()
    |> add_prompt_template("This is a test prompt")
    |> should.be_ok()
    |> add_llm(get_llm_config())

  let assert Ok(eval) = run_with(chain, mock_id_llm_engine)

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

  let assert Ok(chain) =
    new()
    |> add_llm_with_tool_selection(
      get_llm_config(),
      "{{#each tools}}{{name}}-{{description}}{{/each}}",
      [tool_selector],
    )

  chain.steps
  |> list.length()
  |> should.equal(1)
}

pub fn history_test() {
  let chain =
    unchained.new()
    |> unchained.add_prompt_template("Test 1")
    |> should.be_ok()
    |> unchained.add_tool(mock_upper_tool())
    |> unchained.add_llm(get_llm_config())

  chain.steps
  |> list.length()
  |> should.equal(3)

  let eval =
    chain
    |> unchained.run_with(fn(input, _cfg) {
      input |> should.equal("\nTest 1\nTEST 1")
      Ok(unchained.Response("test 2"))
    })
    |> should.be_ok()

  eval
  |> unchained.get_eval_memory()
  |> fn(x) { x.history }
  |> list.map(fn(x) { x.input })
  |> should.equal(["", "Test 1", "TEST 1"])

  eval
  |> unchained.get_eval_memory()
  |> fn(x) { x.history }
  |> list.map(fn(x) { x.output })
  |> should.equal(["Test 1", "TEST 1", "test 2"])

  eval
  |> unchained.get_eval_output()
  |> should.equal("test 2")
}
